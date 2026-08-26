// De kolombreedte-strategie voor een PDF-tabel.
//
// Waarom dit los van `document_pdf_widgets.dart` staat: het is rekenwerk, geen
// tekenwerk. Deze functies raken geen enkele `pw.Widget` en kennen de stijl
// niet — ze krijgen de tekst, de corpsgrootte en de bladbreedte, en geven een
// verdeelsleutel terug. Dat maakt ze los toetsbaar (zie
// `test/pdf/pdf_table_column_widths_test.dart`) en houdt het tekenbestand
// onder zijn regelplafond.

import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import 'document_pdf_blocks.dart';

String _cellText(List<PdfSpan> cell) => cell.map((s) => s.text).join();

/// De ondergrens waaronder de letter van een tabel niet meer krimpt.
///
/// Onder ruwweg twee derde van de broodtekst wordt een rapporttabel eerder
/// onleesbaar dan behulpzaam. Een tabel die zelfs op deze maat niet past —
/// een SHA-512 van 128 tekens is breder dan een A4 ooit kan zijn — houdt zijn
/// afbrekingen; daar is de tabelvorm zelf de verkeerde keuze.
const double minTableFontScale = 0.62;

/// De factor waarmee de letter van een tabel moet krimpen om élke kolom haar
/// langste woord op één regel te laten dragen.
///
/// **Waarom krimpen en niet slimmer verdelen.** [pdfTableColumnWidths] verdeelt
/// de beschikbare breedte evenredig met het langste woord per kolom. Dat werkt
/// zolang de som van die langste woorden op het blad past. Bij zeven
/// prozakolommen is dat niet zo, en dan helpt geen enkele verdeelsleutel meer:
/// de breedte is op. Wat er dan gebeurde was afbreken middenin het woord —
/// `Veiligheidsvraagstu` / `k`, `Kritie` / `k` (#1794) — of middenin een
/// hash of IP-adres, waar de lezer de waarde niet eens meer kan overnemen
/// (#1789).
///
/// Een kleinere letter maakt élk langste woord evenredig smaller en herstelt
/// zo de pasvorm, zonder aan de verdeling te tornen. Zeven kolommen op 8 punt
/// leest een stuk beter dan zeven kolommen op 11 punt met een afbreking in elk
/// tweede woord.
double pdfTableFontScale({
  required List<List<List<PdfSpan>>> rows,
  required int colCount,
  required double tableWidth,
  required double fontSize,
  required double cellPadding,
}) {
  if (rows.isEmpty || colCount <= 0 || tableWidth <= 0) return 1;
  var needed = 0.0;
  for (var c = 0; c < colCount; c++) {
    needed += _estimatedLongestWordWidth(
      rows.map((r) => c < r.length ? r[c] : const <PdfSpan>[]),
      fontSize,
      cellPadding,
    );
  }
  // Een marge op de schatting, want die is stelselmatig iets te optimistisch:
  // `_charWidthFactor` meet in kleine letters (een kapitale G telt als 0,55 em
  // in plaats van ~0,72) en is geijkt op een schreefloze letter, terwijl een
  // rapport vaak een schreefletter zet. Zonder marge kwam elke kolom één teken
  // tekort en brak er alsnog een woord af — net niet is hier hetzelfde als
  // niet.
  needed *= _estimateMargin;
  if (needed <= tableWidth) return 1;
  return math.max(tableWidth / needed, minTableFontScale);
}

/// Hoeveel ruimer de tabel wordt gerekend dan de tekenschatting aangeeft.
const double _estimateMargin = 1.12;

/// Of één van de cellen van [block] zoveel tekst draagt dat de rij hoger wordt
/// dan een bladzijde.
///
/// **Waarom dit ertoe doet.** Een `pw.Table`-rij kan niet over een bladovergang
/// heen breken. Past de rij op geen enkel blad, dan plaatst `MultiPage` niets,
/// begint een nieuw blad, en gebeurt daar precies hetzelfde: de opmaak loopt
/// oneindig rond. De bewaking die dat upstream zou vangen staat in een `assert`
/// en doet in een uitgeleverde app niets — de gebruiker krijgt een bevroren
/// venster zonder melding (#1798).
///
/// Eén lange alinea in een tabelcel is genoeg, en dat is in een rapport heel
/// gewoon. Vandaar dat deze schatting ruim mag zijn: liever een tabel die
/// onnodig in de terugvalvorm belandt dan een export die vastloopt.
///
/// De schatting: de tekst van een cel gedeeld door de kolombreedte geeft het
/// aantal regels, maal de regelhoogte geeft de celhoogte. De kolombreedte is
/// [tableWidth] gedeeld door het aantal kolommen — grof, maar voor "past dit
/// überhaupt op een blad" ruim genoeg.
bool pdfTableRowExceedsPage(
  PdfTableBlock block, {
  required double tableWidth,
  required double pageHeight,
  required double fontSize,
  required double cellPadding,
}) {
  if (block.rows.isEmpty || tableWidth <= 0 || pageHeight <= 0) return false;
  final colCount = block.rows.map((r) => r.length).fold(1, math.max);
  final colWidth = tableWidth / colCount - cellPadding * 2;
  if (colWidth <= 0) return true;
  final lineHeight = fontSize * 1.35;
  for (final row in block.rows) {
    var tallest = 0.0;
    for (final cell in row) {
      var width = 0.0;
      for (final span in cell) {
        width += _estimateWordWidth(span.text, fontSize, span.bold);
      }
      final lines = (width / colWidth).ceil();
      final height = lines * lineHeight + cellPadding * 2;
      if (height > tallest) tallest = height;
    }
    if (tallest > pageHeight) return true;
  }
  return false;
}

/// De tabellen in [blocks] die ook op de kleinste toegestane letter niet op de
/// bladbreedte passen.
///
/// [pdfTableFontScale] laat de letter krimpen tot elke kolom haar langste woord
/// draagt, maar niet onbeperkt: onder [minTableFontScale] wordt een tabel eerder
/// onleesbaar dan behulpzaam. Een tabel die zelfs op die maat te breed blijft —
/// een SHA-512 van 128 tekens is breder dan een A4 ooit kan zijn — krijgt zijn
/// woorden en waarden alsnog middenin doorgehakt.
///
/// Dat is geen renderfout meer maar een vormkeuze die niet uitkomt, en de enige
/// zinnige omgang is het zeggen. Bij een hash of IP-adres is een stille
/// afbreking bovendien geen schoonheidsfout: de lezer kan de waarde daarna niet
/// meer overnemen of vergelijken, en juist daarvoor staat hij er (#1789).
///
/// Loopt door lijstpunten heen, want ook daar kan een tabel in staan.
List<PdfTableBlock> pdfTablesThatCannotFit({
  required List<PdfBlock> blocks,
  required double tableWidth,
  required double fontSize,
  required double cellPadding,
}) {
  final out = <PdfTableBlock>[];
  void walk(List<PdfBlock> list) {
    for (final block in list) {
      switch (block) {
        case PdfTableBlock():
          final colCount = block.rows.isEmpty
              ? 0
              : block.rows.map((r) => r.length).fold(1, math.max);
          final scale = pdfTableFontScale(
            rows: block.rows,
            colCount: colCount,
            tableWidth: tableWidth,
            fontSize: fontSize,
            cellPadding: cellPadding,
          );
          // Gelijk aan de ondergrens betekent: de krimp is opgehouden vóór de
          // tabel paste. De marge vangt het rekenen met drijvende komma.
          if (scale <= minTableFontScale + 0.0001) out.add(block);
        case PdfListBlock(:final items):
          for (final item in items) {
            walk(item.blocks);
          }
        case _:
          break;
      }
    }
  }

  walk(blocks);
  return out;
}

/// De kolombreedte-strategie per kolom voor een PDF-tabel.
///
/// **Waarom dit bestaat in plaats van de `package:pdf`-standaard.** Zonder
/// `columnWidths` valt elke kolom op `IntrinsicColumnWidth`: de kolom wordt zo
/// breed als haar tekst op één regel nodig heeft, en omdat geen kolom `flex`
/// heeft (`totalFlex == 0`) schaalt de opmaak alle kolommen pro rato terug tot
/// de bladspiegel. Een prozakolom met een lange cel claimt op één regel een
/// enorme breedte, en pro rato drukt dat de smalle kolommen — "Nr.", "Oordeel"
/// — samen tot één of twee tekens: de tekst komt er verticaal in te staan, een
/// teken per regel. Dat is wat de RWM-beoordeling onleesbaar maakte.
///
/// **Hoe deze functie het oplost.** De breedste kolommen worden één voor één
/// flex (van breed naar smal) tot de overgebleven intrinsic kolommen samen op
/// het blad passen. Zodra één kolom flex heeft, schakelt de pro rato-
/// samendrukking uit en houden de intrinsic kolommen hun echte breedte — geen
/// stapeling meer. De flex-kolommen delen de ruimte die overblijft.
///
/// **Waarom het flex-gewicht op het langste woord staat, niet op de langste
/// cel.** Een kolom met een lange cel maar korte woorden heeft genoeg aan een
/// smalle breedte: de tekst breekt op woordgrenzen netjes af. Een kolom met
/// één lang woord — "Zorgplichtmaatregel", "Bedrijfscontinuïteit" — heeft juist
/// meer breedte nodig, want een lang woord dat niet past breekt midden in het
/// woord af. Het flex-gewicht is daarom het langste woord in de kolom: kolommen
/// met lange woorden krijgen meer van de resterende ruimte.
///
/// **Waarom geen echte lettermeting.** Een `pw.Font` is lui en geeft zijn
/// lettermaten pas tijdens de opmaak, niet bij het bouwen van de widgets. De
/// schatting (0,5 em per teken) is ruim — ze bepaalt alleen wélke kolommen
/// flexen en in welke verhouding, niet hun absolute breedte, en een verkeerde
/// schatting betekent hooguit dat een kolom één regel extra afbreekt, nooit de
/// stapeling van vroeger.
Map<int, pw.TableColumnWidth> pdfTableColumnWidths({
  required List<List<List<PdfSpan>>> rows,
  required int colCount,
  required double tableWidth,
  required double fontSize,
  required double cellPadding,
}) {
  if (rows.isEmpty || colCount <= 0 || tableWidth <= 0) {
    return const {};
  }

  // De langste cel per kolom — bepaalt wélke kolommen flex worden.
  final maxCellLen = <int>[
    for (var c = 0; c < colCount; c++)
      rows
          .map((r) => c < r.length ? _cellText(r[c]).trim().length : 0)
          .fold(1, (longest, len) => len > longest ? len : longest),
  ];
  // De geschatte breedte van het langste woord per kolom, met een correctie
  // voor vetgedrukte tekst en de werkelijke tekenbreedtes. Het flex-gewicht
  // is proportioneel aan deze schatting, zodat een kolom met vetgedrukte
  // tekst meer ruimte krijgt dan een kolom met gewone tekst van dezelfde
  // lengte.
  final wordWidth = <double>[
    for (var c = 0; c < colCount; c++)
      _estimatedLongestWordWidth(
        rows.map((r) => c < r.length ? r[c] : const <PdfSpan>[]),
        fontSize,
        cellPadding,
      ),
  ];

  // Ruime schatting van de kolombreedte op één regel: 0,5 em per teken van de
  // langste cel, plus celopvulling aan beide zijden.
  final est = <double>[
    for (var c = 0; c < colCount; c++)
      maxCellLen[c] * 0.5 * fontSize + cellPadding * 2,
  ];
  final estSum = est.fold<double>(0, (a, b) => a + b);

  // Past de hele tabel op één regel in het blad? Dan gedraagt de standaard
  // (alles intrinsic) zich goed: de kolommen groeien pro rato mee tot de
  // bladspiegel. Geen flex nodig, en zo blijft een korte tabel eruit zien
  // zoals ze altijd al deed.
  if (estSum <= tableWidth) {
    return {
      for (var c = 0; c < colCount; c++) c: const pw.IntrinsicColumnWidth(),
    };
  }

  // De tabel past niet op één regel: maak de breedste kolommen één voor één
  // flex, van breed naar smal, tot de intrinsic kolommen samen ruim op het
  // blad passen. De grens is niet een vaste fractie maar de som van de
  // langste-woordenbreedtes van de flex-kolommen: zolang de intrinsic kolommen
  // meer dan dat overblijft, krijgt elke flex-kolom minstens haar langste woord
  // breedte (want de flex-ruimte wordt evenredig met de woordbreedte verdeeld).
  // Zo breekt package:pdf geen woorden midden in af (#1727). Loopt de tabel over
  // zelfs als alle kolommen flex zijn, dan is afbreken onvermijdelijk.
  final flex = List<bool>.filled(colCount, false);
  final order = List<int>.generate(colCount, (i) => i)
    ..sort((a, b) => est[b].compareTo(est[a]));
  var intrinsicSum = estSum;
  var flexMinSum = 0.0;
  for (final c in order) {
    if (intrinsicSum <= tableWidth - flexMinSum) break;
    flex[c] = true;
    intrinsicSum -= est[c];
    flexMinSum += wordWidth[c];
  }
  // Omdat estSum > tableWidth, zet de lus altijd minstens één kolom op flex —
  // precies wat de pro rato-samendrukking uitschakelt.

  return {
    for (var c = 0; c < colCount; c++)
      c: flex[c]
          ? pw.FlexColumnWidth(wordWidth[c].clamp(1.0, 999.0))
          : const pw.IntrinsicColumnWidth(),
  };
}

/// De geschatte breedte van het langste woord in een kolom, met een correctie
/// voor vetgedrukte tekst en de werkelijke tekenbreedtes.
///
/// Waarom teken-niveau in plaats van tekenaantal: "Onvoldoende" (veel o, v, d,
/// e) is per teken breder dan "Zorgplichtmaatregel" (veel l, i, t, r). Op
/// tekenaantal alleen krijgt de kolom met "Onvoldoende" te weinig ruimte en
/// breekt het woord midden in af. Deze schatting weegt brede tekens (m, w, O)
/// zwaarder dan smalle (i, l, t, r), zodat de flex-verdeling de werkelijke
/// tekstbreedte volgt.
double _estimatedLongestWordWidth(
  Iterable<List<PdfSpan>> cells,
  double fontSize,
  double padding,
) {
  var max = 1.0;
  for (final cell in cells) {
    for (final span in cell) {
      for (final word in span.text.trim().split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final w = _estimateWordWidth(word, fontSize, span.bold);
        if (w > max) max = w;
      }
    }
  }
  return max + padding * 2;
}

/// Schat de breedte van één woord in punten, op basis van tekenbreedtes.
double _estimateWordWidth(String word, double fontSize, bool bold) {
  final factor = bold ? 1.1 : 1.0;
  var width = 0.0;
  for (final char in word.toLowerCase().runes) {
    width += _charWidthFactor(char) * fontSize * factor;
  }
  return width;
}

/// De geschatte breedte van één teken in em, voor een schreefloos font
/// (Helvetica). Brede tekens (m, w) zijn ~0,8 em, smalle (i, l, t) ~0,3 em,
/// de meeste letters ~0,55 em. De schatting hoeft niet exact te zijn — ze
/// bepaalt alleen de verhouding tussen flex-kolommen.
double _charWidthFactor(int rune) {
  switch (rune) {
    case 0x69: // i
    case 0x6c: // l
    case 0x6a: // j
    case 0x66: // f
    case 0x74: // t
    case 0x72: // r
    case 0x7c: // |
      return 0.35;
    case 0x6d: // m
    case 0x77: // w
      return 0.80;
    case 0x4d: // M
    case 0x57: // W
      return 0.85;
    case 0x20: // space
      return 0.25;
    default:
      return 0.55;
  }
}
