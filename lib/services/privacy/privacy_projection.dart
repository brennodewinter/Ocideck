// De privacyprojectie: de enige grens waarlangs een bron-Deck een ontvangend
// oppervlak bereikt.
//
// Het uitgangspunt is "niet beschikbaar is niet beschikbaar". Redactie is daarom
// GEEN renderingvlag maar een waarde-transformatie: de gevoelige tekens worden
// hier vervangen, vóór de splitsing naar preview, rasterizer, HTML,
// PPTX-notities en documentmetadata. Wat een widget of een exportbouwer in
// handen krijgt, bevat de oorspronkelijke tekens niet meer — er is dus geen
// tekstlaag onder een zwarte rechthoek, geen leesbare notitie in de PPTX-zip, en
// niets in de semantics-tree van een schermlezer.
//
// De grens wordt afgedwongen door het typesysteem: AudienceDeck heeft een
// private constructor en is alleen in deze library te maken. Een ontvangend
// oppervlak dat een AudienceDeck eist, kan de ongeredigeerde bron dus niet eens
// ontvangen — ook niet als een toekomstig exportformaat het zou proberen. Zie
// docs/design/PRIVACY_SHIELD.md §6.
//
// De bron blijft ongemoeid: wat de gebruiker opslaat is en blijft de
// oorspronkelijke markdown. Redactie geldt voor wat je *toont en exporteert*.

import '../../models/deck.dart';
import '../../models/privacy_disposition.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import 'privacy_scanner.dart';

/// Het teken waarmee geredigeerde tekst wordt vervangen (U+2588 FULL BLOCK).
const String kRedactionBlock = '█';

/// Hoeveel blokken één redactie oplevert.
///
/// Bewust een **vaste** breedte en niet de lengte van het origineel: negen
/// blokjes waar een BSN stond en elf waar een IBAN stond, vertelt de ontvanger
/// welk soort gegeven er is weggehaald en hoe lang het was. Bij korte,
/// gestructureerde waarden komt dat gevaarlijk dicht bij reconstrueerbaar.
const int kRedactionBlockCount = 8;

/// De vervanging zoals die in de uitvoer verschijnt.
final String kRedactionToken = kRedactionBlock * kRedactionBlockCount;

/// De handmatige redactiemarkering in de bron: `[[tekst]]`.
///
/// Detectie is per definitie best-effort — wat de scanner niet ziet, redigeert
/// hij niet. Deze markering geeft de auteur het laatste woord, onafhankelijk van
/// welke detectieregel wel of niet vuurt. Geen geneste blokhaken, zodat een
/// gewone markdown-link (`[tekst](url)`) er niet in loopt.
final RegExp _manualRedaction = RegExp(r'\[\[([^\[\]]*)\]\]');

/// Een deck dat de privacyprojectie is gepasseerd.
///
/// Dit is het **enige** type dat de ontvangende oppervlakken accepteren
/// (preview, thumbnails, presentatie, publieksvenster, rasterizer, HTML-export,
/// PPTX-notities, documentmetadata). De constructor is private: alleen
/// [PrivacyProjection] kan er een maken, en dus kan geen enkel exportpad — ook
/// geen toekomstig — per ongeluk de ongeredigeerde bron in handen krijgen.
class AudienceDeck {
  /// Het geprojecteerde deck. De tekstvelden zijn hier al geredigeerd; dit is
  /// niet de bron.
  final Deck deck;

  /// Hoeveel redacties de projectie heeft toegepast.
  final int redactionCount;

  /// De slides waarop een privacy-shield getoond moet worden: de ontvanger wordt
  /// gewaarschuwd dát er persoonsgegevens op staan, zonder ze weg te halen.
  final Set<int> shieldedSlides;

  const AudienceDeck._(this.deck, this.redactionCount, this.shieldedSlides);

  bool get hasRedactions => redactionCount > 0;

  List<Slide> get slides => deck.slides;
}

/// Tekst plus het aantal redacties dat erin is toegepast.
typedef RedactedText = ({String text, int count});

/// Een half-open bereik in een tekst.
typedef _Range = ({int start, int end});

/// Bouwt een [AudienceDeck] uit een bron-[Deck].
class PrivacyProjection {
  const PrivacyProjection._();

  /// De projectie voor een menselijke ontvanger: publiek, lezer van de export.
  ///
  /// Redigeert wat de auteur met `[[…]]` heeft gemarkeerd, plus de gedetecteerde
  /// gegevens op elke slide waarvan de effectieve stand `redact` is.
  static AudienceDeck forAudience(
    Deck deck, {
    Set<String> disabledRules = const {},
  }) => _project(deck, external: false, disabledRules: disabledRules);

  /// De projectie voor verwerking buiten dit apparaat (AI-backends).
  ///
  /// Bewust **strenger**: hier telt de dispositie níét. Dat de auteur besluit dat
  /// een zaal de namen mag zien, is geen toestemming om ze naar een extern model
  /// te sturen. Alles wat de scanner vindt gaat eruit, ook op een slide die op
  /// `accept` staat.
  static AudienceDeck forExternalProcessing(
    Deck deck, {
    Set<String> disabledRules = const {},
  }) => _project(deck, external: true, disabledRules: disabledRules);

  /// De projectie scant **zelf**, en doet dat altijd.
  ///
  /// Twee redenen, en ze zijn allebei fail-closed:
  ///
  /// 1. Zou de aanroeper het scanresultaat moeten meegeven, dan is "vergeten mee
  ///    te geven" een stille lek: er wordt dan niets geredigeerd en niemand merkt
  ///    het. Een grens die je kunt vergeten, is geen grens.
  ///
  /// 2. De instelling "waarschuw bij mogelijke persoonsgegevens" wordt hier
  ///    genegeerd. Die schakelt *waarschuwingen* uit, niet redactie. Een deck met
  ///    `privacy: redact` moet blijven redigeren, ook bij een gebruiker die de
  ///    meldingen niet wil zien — anders zet iemand de meldingen uit en lekt zijn
  ///    briefing stilletjes.
  static AudienceDeck _project(
    Deck deck, {
    required bool external,
    Set<String> disabledRules = const {},
  }) {
    // De uitgezette regels tellen hier wél mee (anders dan de hoofdschakelaar):
    // wie een regel uitzet omdat die het mis heeft over zijn inhoud, wil die
    // inhoud niet zwart in zijn export terugzien. Zie PrivacyScanner.
    final scan = PrivacyScanner(disabledRules: disabledRules).scan(deck);

    var count = 0;
    final shielded = <int>{};

    // Deckvelden voeden de documentmetadata (PDF-properties, PPTX-docProps):
    // leesbaar, ook al staat er op geen enkele slide iets van te zien.
    final deckRedact = external || deck.privacy == PrivacyDisposition.redact;
    final deckFindings = _byFragment(
      scan.findings.where((f) => f.isDeckWide),
      active: deckRedact,
    );

    String deckField(String field, String text) {
      final result = _redact(text, deckFindings['$field:0'] ?? const []);
      count += result.count;
      return result.text;
    }

    final slides = <Slide>[];
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final disposition = effectivePrivacyDisposition(
        deck: deck.privacy,
        slide: slide.privacy,
      );
      if (disposition == PrivacyDisposition.shield) shielded.add(i);

      final active = external || disposition == PrivacyDisposition.redact;
      final byFragment = _byFragment(scan.forSlide(i), active: active);

      final projected = _projectSlide(slide, byFragment);
      count += projected.count;
      // De effectieve stand wordt op de geprojecteerde slide gezet. Zo reist het
      // shield mee mét de slide en kan geen renderoppervlak hem vergeten — een
      // extra parameter door elf aanroepplaatsen heen zou wél te vergeten zijn,
      // en dan verdwijnt de waarschuwing voor de ontvanger stilletjes.
      slides.add(projected.slide.copyWith(privacy: disposition));
    }

    // Deck.userNotes staat er bewust NIET bij. Dat zijn de notities die de
    // ontvanger zélf typt; ze gaan naar een sidecar naast het bestand en
    // bereiken geen enkel exportartefact. Ze wél projecteren zou schade doen in
    // plaats van voorkomen: de presenter schrijft de notitiemap in haar geheel
    // terug, dus één bewerking tijdens het presenteren zou blokken over iemands
    // eigen aantekeningen zetten.
    final projected = deck.copyWith(
      slides: slides,
      title: deckField('deckTitle', deck.title),
      author: deckField('author', deck.author),
      organization: deckField('organization', deck.organization),
      description: deckField('description', deck.description),
      keywords: deckField('keywords', deck.keywords),
    );

    return AudienceDeck._(projected, count, shielded);
  }

  /// Groepeert de te redigeren bevindingen per tekstfragment.
  ///
  /// Staat de slide niet op `redact`, dan is de map leeg: de gegevens blijven
  /// staan. De handmatige `[[…]]`-markering werkt hoe dan ook — die is een
  /// instructie van de auteur, geen bevinding van de scanner.
  static Map<String, List<_Range>> _byFragment(
    Iterable<PrivacyFinding> findings, {
    required bool active,
  }) {
    if (!active) return const {};
    final map = <String, List<_Range>>{};
    for (final f in findings) {
      map.putIfAbsent('${f.field}:${f.fragmentIndex}', () => []).add((
        start: f.start,
        end: f.end,
      ));
    }
    return map;
  }

  /// Projecteert elk tekstdragend veld van een slide.
  ///
  /// Sprekersnotities staan er nadrukkelijk bij: die zijn onzichtbaar in de
  /// preview, maar gaan als platte tekst mee in de PPTX-notitiepagina's.
  ///
  /// Een slide waarin iets is geredigeerd, verliest [Slide.tableEditable]. Dat
  /// is geen bijkomstigheid maar de kern van de grens: de presenter schrijft een
  /// live tabelbewerking als *hele slide* terug naar het deck
  /// (`presenter_table.dart`). Zou de presenter een geprojecteerde slide mogen
  /// terugschrijven, dan overschreef één bewerking de bron met blokken. Een
  /// oppervlak dat de gegevens niet kán zien, mag ze ook niet terugschrijven.
  static ({Slide slide, int count}) _projectSlide(
    Slide slide,
    Map<String, List<_Range>> byFragment,
  ) {
    var count = 0;

    String field(String name, String text, [int index = 0]) {
      final result = _redact(text, byFragment['$name:$index'] ?? const []);
      count += result.count;
      return result.text;
    }

    final projected = slide.copyWith(
      title: field('title', slide.title),
      subtitle: field('subtitle', slide.subtitle),
      columnTitle1: field('columnTitle1', slide.columnTitle1),
      columnTitle2: field('columnTitle2', slide.columnTitle2),
      imageCaption: field('imageCaption', slide.imageCaption),
      imageCaption2: field('imageCaption2', slide.imageCaption2),
      imageAltText: field('imageAltText', slide.imageAltText),
      imageAltText2: field('imageAltText2', slide.imageAltText2),
      quote: field('quote', slide.quote),
      quoteAuthor: field('quoteAuthor', slide.quoteAuthor),
      customMarkdown: field('customMarkdown', slide.customMarkdown),
      notes: field('notes', slide.notes),
      bullets: [
        for (var i = 0; i < slide.bullets.length; i++)
          field('bullets', slide.bullets[i], i),
      ],
      bullets2: [
        for (var i = 0; i < slide.bullets2.length; i++)
          field('bullets2', slide.bullets2[i], i),
      ],
      tableRows: [
        for (var r = 0; r < slide.tableRows.length; r++)
          [
            for (var c = 0; c < slide.tableRows[r].length; c++)
              field(
                'tableRows',
                slide.tableRows[r][c],
                r * slide.tableRows[r].length + c,
              ),
          ],
      ],
    );

    return (
      slide: count > 0 ? projected.copyWith(tableEditable: false) : projected,
      count: count,
    );
  }

  /// Vervangt de handmatige markeringen én de meegegeven bereiken door blokken.
  ///
  /// Beide bronnen worden samengevoegd en van achteren naar voren vervangen. Dat
  /// is niet cosmetisch: zou je van voren af aan werken, dan verschuiven alle
  /// volgende posities zodra de eerste vervanging een andere lengte heeft, en
  /// redigeer je de verkeerde tekens — of, erger, laat je er een paar staan.
  static RedactedText _redact(String source, List<_Range> ranges) {
    final all = <_Range>[
      ...ranges,
      for (final m in _manualRedaction.allMatches(source))
        (start: m.start, end: m.end),
    ];
    if (all.isEmpty) return (text: source, count: 0);

    all.sort((a, b) => a.start.compareTo(b.start));

    // Overlappende bereiken samenvoegen: een treffer die binnen een handmatige
    // markering valt, mag geen tweede blok opleveren.
    final merged = <_Range>[];
    for (final r in all) {
      if (merged.isNotEmpty && r.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add((
          start: last.start,
          end: r.end > last.end ? r.end : last.end,
        ));
      } else {
        merged.add(r);
      }
    }

    final buf = StringBuffer();
    var cursor = 0;
    for (final r in merged) {
      buf.write(source.substring(cursor, r.start));
      buf.write(kRedactionToken);
      cursor = r.end;
    }
    buf.write(source.substring(cursor));
    return (text: buf.toString(), count: merged.length);
  }

  /// Vervangt elke `[[…]]`-markering door de blokken. Puur en zelfstandig
  /// testbaar.
  static RedactedText redactText(String source) => _redact(source, const []);
}
