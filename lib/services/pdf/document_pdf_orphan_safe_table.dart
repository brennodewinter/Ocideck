// Een tabel die zijn kopregel niet alleen onderaan een blad achterlaat.
//
// Waarom dit bestaat: `package:pdf` plaatst rijen tot er één niet meer past.
// Past onderaan een blad alleen de herhaalde kopregel nog, dan tekent hij die
// daar en begint de inhoud op het volgende blad — met de kop daar opnieuw. De
// lezer ziet een gekleurde balk die niets aankondigt (#1790).
//
// `Table` kent geen instelling om dat te voorkomen. Wat het wél biedt is het
// `SpanningWidget`-contract, en dat is genoeg: `saveContext()` geeft het
// lévende `TableContext` met publieke `firstLine`/`lastLine`, en `paint()` valt
// meteen terug zodra `lastLine` nul is. Een subklasse kan daarmee vaststellen
// dat er alleen herhaalrijen geplaatst zijn en dit blad overslaan.

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Een [pw.Table] die een blad overslaat wanneer er alleen herhaalrijen op
/// zouden passen.
///
/// **Hoe het werkt.** `MultiPage` legt een spannende widget twee keer op: eerst
/// met de volle paginabeperking, en — als hij dan niet past — opnieuw met
/// precies de ruimte die op dit blad over is. Die tweede aanroep maakt de wees.
/// Blijkt daar dat er niets anders dan herhaalrijen geplaatst is, dan zet deze
/// tabel `lastLine` op nul: `paint()` tekent dan niets, en de opmaak gaat
/// verder op het volgende blad. Bij de volgende aanroep wordt de leesregel
/// hersteld, zodat er geen rij overgeslagen of herhaald wordt.
///
/// **Waarom dit niet kan lussen.** Uitwijken mag alleen wanneer de beschikbare
/// hoogte merkbaar kleiner is dan de grootste die deze tabel ooit kreeg — en
/// dat is de volle bladhoogte, die hij op elk blad bij de eerste aanroep ziet.
/// Op een vers blad wijkt hij dus nooit uit. Zelfs een rij die hoger is dan een
/// heel blad — waar `package:pdf` sowieso geen raad mee weet — kan hem niet aan
/// het rondtollen brengen. De tweede grendel, [_deferredAt], zorgt dat er op
/// dezelfde leesregel nooit twee keer wordt uitgeweken — en elke geslaagde
/// opmaak schuift die regel op.
///
/// Dit lost het geval op waar [pw.Inseparable] niet bij kan: een tabel die
/// langer is dan een blad kan zichzelf niet bij elkaar houden, maar hoeft zijn
/// kop niet als wees achter te laten.
class OrphanSafeTable extends pw.Table {
  OrphanSafeTable({required super.children, super.border, super.columnWidths});

  /// De grootste hoogte die deze tabel ooit aangeboden kreeg — in de praktijk
  /// de bladhoogte, want elk blad begint met een aanroep op volle maat.
  double _tallestOffer = 0;

  /// De leesregel waarop het laatst is uitgeweken, of `null`.
  ///
  /// Op dezelfde leesregel wijkt deze tabel nooit twee keer uit. Dat is de
  /// harde vooruitgangsgarantie: elke geslaagde opmaak schuift de leesregel op,
  /// dus een uitwijking kan hoogstens één blad kosten en nooit een lus worden.
  int? _deferredAt;

  /// De leesregel waar we stonden toen we uitweken, of `null` als er geen
  /// uitwijking openstaat.
  ///
  /// Blijft staan tot een opmaak wél iets plaatst. `MultiPage` legt een
  /// spannende widget twee keer op per blad, en kloont de context vóór de
  /// eerste aanroep om hem vóór de tweede terug te zetten — die kloon draagt
  /// onze nul nog. Lieten we deze waarde na de eerste aanroep los, dan begon de
  /// tabel bij die tweede aanroep weer bij rij nul en herhaalde hij alles.
  int? _resumeAt;

  /// Hoeveel kleiner de aangeboden hoogte moet zijn dan de bladhoogte voordat
  /// uitwijken is toegestaan.
  ///
  /// Niet exact vergelijken: `MultiPage` trekt er de kop- en voetband van af,
  /// zodat de "volle" maat per blad een paar punten kan schelen. Negen tiende
  /// is ruim genoeg om een vers blad te herkennen en streng genoeg om een
  /// staartje aan het eind van een blad níet als vers te zien.
  static const _freshPageFraction = 0.9;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    if (constraints.maxHeight > _tallestOffer) {
      _tallestOffer = constraints.maxHeight;
    }

    final resume = _resumeAt;
    if (resume != null) {
      // `restoreContext` zette de leesregel op nul omdat wij `lastLine` op nul
      // hadden gezet. Herstel hem, anders begint de tabel op het nieuwe blad
      // weer bij de eerste rij en herhaalt hij wat er al stond.
      final ctx = saveContext() as pw.TableContext;
      ctx
        ..firstLine = resume
        ..lastLine = resume;
    }

    super.layout(context, constraints, parentUsesSize: parentUsesSize);

    final ctx = saveContext() as pw.TableContext;
    if (_shouldDefer(ctx, constraints)) {
      _resumeAt = ctx.firstLine;
      _deferredAt = ctx.firstLine;
      // Nul betekent voor `paint()`: teken niets. De hoogte gaat mee terug naar
      // nul zodat dit blad geen ruimte reserveert voor wat er niet komt.
      ctx.lastLine = 0;
      box = PdfRect(box!.left, box!.bottom, box!.width, 0);
      return;
    }
    // Pas hier loslaten: deze opmaak heeft werkelijk iets geplaatst.
    _resumeAt = null;
  }

  /// Of er op dit blad alleen herhaalrijen geplaatst zijn, en uitwijken mag.
  bool _shouldDefer(pw.TableContext ctx, pw.BoxConstraints constraints) {
    // Nooit twee keer op dezelfde leesregel: dat is de vooruitgangsgarantie.
    if (_deferredAt == ctx.firstLine) return false;
    // Op een vers blad nooit: dan is er niets beters te krijgen.
    if (constraints.maxHeight >= _tallestOffer * _freshPageFraction) {
      return false;
    }
    // Niets geplaatst is geen wees maar een lege opmaak; die laten we met rust.
    if (ctx.lastLine <= ctx.firstLine) return false;
    // Er staat niets ná dit stuk, dus er valt niets vooruit te schuiven.
    if (ctx.lastLine >= children.length) return false;
    for (var i = ctx.firstLine; i < ctx.lastLine; i++) {
      if (!children[i].repeat) return false;
    }
    return true;
  }
}
