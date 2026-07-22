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
// De grens rust op twee dingen, en het onderscheid is de moeite waard.
//
// Het typesysteem doet de helft: AudienceDeck heeft een private constructor en
// is alleen in deze library te maken. Een ontvangend oppervlak dat een
// AudienceDeck eist, kán de ongeredigeerde bron dus niet ontvangen — ook niet
// als een toekomstig exportformaat het zou proberen.
//
// Wat de compiler NIET weet is wélke functies dat type horen te eisen. Daar zit
// een nieuw uitvoerkanaal dat niemand als zodanig herkende, en dat is de
// werkelijke faalvorm. Die helft doet `tool/check_audience_boundary.dart`: die
// vindt kandidaten zelf en weigert te slagen tot elk kanaal geclassificeerd is.
// Zijn kop noemt ook zijn blinde vlek — een oppervlak dat het schrijven twee
// lagen verderop uitbesteedt, wordt niet gezien.
//
// Zie docs/design/OCIWACHT.md §6.
//
// De bron blijft ongemoeid: wat de gebruiker opslaat is en blijft de
// oorspronkelijke markdown. Redactie geldt voor wat je *toont en exporteert*.

import '../../models/deck.dart';
import '../../models/privacy_disposition.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import '../../models/used_tool.dart';
import '../slide_image_refs.dart';
import 'privacy_own_identity.dart';
import 'privacy_regions.dart';
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
/// Het patroon zelf staat in `privacy_scanner.dart`, want die heeft het óók
/// nodig: een bevinding binnen een markering wordt daar onderdrukt. Eén
/// definitie, in de onderste laag — twee regexes die hetzelfde horen te
/// betekenen lopen vroeg of laat uiteen, en dan redigeert de projectie iets
/// waar de scanner nog over klaagt.
final RegExp _manualRedaction = kManualRedaction;

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
    OwnIdentity ownIdentity = OwnIdentity.empty,
    Set<String> regions = defaultPrivacyRegions,
    PrivacyExportProfile profile = PrivacyExportProfile.full,
  }) => _project(
    deck,
    // In het geredigeerde profiel telt de dispositie niet: "deze zaal mag het
    // zien" is niet hetzelfde als "iedereen mag het zien".
    external: profile == PrivacyExportProfile.redacted,
    disabledRules: disabledRules,
    ownIdentity: ownIdentity,
    regions: regions,
  );

  /// De projectie voor verwerking buiten dit apparaat (AI-backends).
  ///
  /// Bewust **strenger**: hier telt de dispositie níét. Dat de auteur besluit dat
  /// een zaal de namen mag zien, is geen toestemming om ze naar een extern model
  /// te sturen. Alles wat de scanner vindt gaat eruit, ook op een slide die op
  /// `accept` staat.
  /// Neemt bewust **geen** `regions`: de landkeuze van de gebruiker geldt hier
  /// niet. Dat iemand het Nederlandse pakket uitzet omdat het in zíjn deck te
  /// vaak aanslaat, is een uitspraak over zijn kwaliteitspaneel en zijn eigen
  /// export — niet om een BSN naar een model van een derde te sturen. Dezelfde
  /// redenering als hierboven bij de dispositie: strenger, omdat de data het
  /// apparaat verlaat en niet meer terug te halen is.
  static AudienceDeck forExternalProcessing(
    Deck deck, {
    Set<String> disabledRules = const {},
    OwnIdentity ownIdentity = OwnIdentity.empty,
  }) => _project(
    deck,
    external: true,
    disabledRules: disabledRules,
    ownIdentity: ownIdentity,
  );

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
    OwnIdentity ownIdentity = OwnIdentity.empty,
    Set<String> regions = defaultPrivacyRegions,
  }) {
    // De uitgezette regels tellen hier wél mee (anders dan de hoofdschakelaar):
    // wie een regel uitzet omdat die het mis heeft over zijn inhoud, wil die
    // inhoud niet zwart in zijn export terugzien. Zie PrivacyScanner.
    // De eigen gegevens van de gebruiker tellen hier ook mee: zijn adres in de
    // footer is geen bevinding maar de afzender, en zwart in de export zetten zou
    // de contactslide onbruikbaar maken.
    // De landenpakketten tellen hier mee, op dezelfde grond als de uitgezette
    // regels: wie een pakket uitzet zegt "dit zijn voor mij geen
    // persoonsgegevens", en krijgt die waarden dan ook niet zwart in zijn
    // export terug. Zonder dit stonden het kwaliteitspaneel en de export lijnrecht
    // tegenover elkaar — precies waar de gebruiker op het paneel afgaat om te
    // beslissen wat hij deelt.
    //
    // De standaardwaarde blijft `defaultPrivacyRegions` en niet `const {}`: een
    // aanroeper die dit vergeet moet méér redigeren, niet minder. De universele
    // regels (IBAN, e-mail, paspoort) hangen aan geen enkel pakket en blijven
    // hoe dan ook draaien.
    final scan = PrivacyScanner(
      disabledRules: disabledRules,
      ownIdentity: ownIdentity,
      regions: regions,
    ).scan(deck);

    var count = 0;
    final shielded = <int>{};

    // Deckvelden voeden de documentmetadata (PDF-properties, PPTX-docProps):
    // leesbaar, ook al staat er op geen enkele slide iets van te zien.
    final deckRedact = external || deck.privacy == PrivacyDisposition.redact;
    final deckFindings = _byFragment(
      scan.findings.where((f) => f.isDeckWide),
      active: deckRedact,
    );

    String deckField(String field, String text, [int index = 0]) {
      final result = _redact(text, deckFindings['$field:$index'] ?? const []);
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

      final projected = _projectSlide(slide, byFragment, active: active);
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
    // De volgorde van de lijsten en de maps moet dezelfde zijn als in
    // `_deckFragments`: de scanner nummert daar op positie, niet op sleutel.
    // Dart-maps itereren in invoegvolgorde, dus dat komt overeen — maar
    // sorteren of filteren zou de indexen laten verschuiven, en dan landt een
    // redactie op de motivering van een ándere eis.
    var waiverIndex = 0;
    var confirmationIndex = 0;
    final projected = deck.copyWith(
      slides: slides,
      title: deckField('deckTitle', deck.title),
      author: deckField('author', deck.author),
      organization: deckField('organization', deck.organization),
      description: deckField('description', deck.description),
      keywords: deckField('keywords', deck.keywords),
      // Version en date komen uit hetzelfde dialoogvenster als de vijf
      // hierboven en belanden in dezelfde front matter. Ze werden wél gescand
      // maar niet geredigeerd: de exportpoort meldde dan een bevinding die de
      // gebruiker met "redigeren" niet kón oplossen.
      version: deckField('version', deck.version),
      date: deckField('date', deck.date),
      standardsUsed: [
        for (var i = 0; i < deck.standardsUsed.length; i++)
          deckField('standardsUsed', deck.standardsUsed[i], i),
      ],
      toolsUsed: [
        for (var i = 0; i < deck.toolsUsed.length; i++)
          UsedTool(
            name: deckField('toolsUsed', deck.toolsUsed[i].name, i),
            version: deck.toolsUsed[i].version,
            url: deck.toolsUsed[i].url,
            description: deck.toolsUsed[i].description,
          ),
      ],
      // De MIAUW-motiveringen reizen base64-gecodeerd mee in de front matter:
      // onzichtbaar voor wie het bestand naleest, en dus ook voor elk vangnet
      // dat op platte tekst zoekt. Juist daar staat het vaakst een naam
      // ("uitgesloten op verzoek van …").
      miauwWaivers: {
        for (final e in deck.miauwWaivers.entries)
          e.key: deckField('miauwWaivers', e.value, waiverIndex++),
      },
      miauwConfirmations: {
        for (final e in deck.miauwConfirmations.entries)
          e.key: deckField('miauwConfirmations', e.value, confirmationIndex++),
      },
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
      // Een aanwijzing zonder mededeling eromheen slaan we over: zie
      // [PrivacyFinding.isRedactable]. Een zwart blok op het woord "diagnose"
      // verbergt niets en wekt de indruk dat er iets verborgen ís.
      if (!f.isRedactable) continue;
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
  /// Een slide waarin iets is geredigeerd, verliest [Slide.tableEditable] en
  /// krijgt [Slide.contentRedacted]. Dat is geen bijkomstigheid maar de kern van
  /// de grens: de presenter schrijft een live tabelbewerking én een aangevinkt
  /// checklistpunt als *hele slide* terug naar het deck (`presenter_table.dart`,
  /// `presenter_content.dart`). Zou de presenter een geprojecteerde slide mogen
  /// terugschrijven, dan overschreef één bewerking de bron met blokken. Een
  /// oppervlak dat de gegevens niet kán zien, mag ze ook niet terugschrijven.
  ///
  /// Tabellen hebben daar een veld van de auteur voor dat we uitzetten; voor de
  /// checklist bestaat dat niet, vandaar de aparte vlag.
  /// De staplengte van de vlakke celindex: de bréédste rij, niet de rij zelf.
  ///
  /// Moet exact hetzelfde zijn als in `privacy_scanner.dart`, anders redigeert de
  /// projectie een andere cel dan de scanner vond. Met `row.length` per rij was
  /// de afbeelding geen bijectie bij een tabel met ongelijke rijen, en botsten
  /// twee cellen op één sleutel.
  static int _stride(Slide slide) =>
      slide.tableRows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

  static ({Slide slide, int count}) _projectSlide(
    Slide slide,
    Map<String, List<_Range>> byFragment, {
    required bool active,
  }) {
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
      // Het scope-object van een checklist. Het wordt gescand én het staat op
      // de dia (`checklist_preview.dart`), maar het werd nooit geredigeerd: een
      // scope-URL met een tenant- of gebruikersnaam erin ging mee in
      // PDF-pixels, PPTX, beamer én HTML, ook in het profiel *geredigeerd*.
      checklistScope: field('checklistScope', slide.checklistScope),
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
              field('tableRows', slide.tableRows[r][c], r * _stride(slide) + c),
          ],
      ],
    );

    final withMedia = _projectMedia(projected, active: active);
    count += withMedia.count;

    return (
      slide: count > 0
          ? withMedia.slide.copyWith(
              tableEditable: false,
              contentRedacted: true,
            )
          : withMedia.slide,
      count: count,
    );
  }

  /// Haalt afbeeldingen, video en audio weg op een slide die geredigeerd wordt.
  ///
  /// ── Waarom álle media, en niet alleen de gedetecteerde gezichten ──
  ///
  /// Omdat we niet in een afbeelding kunnen kijken. De beeldcontrole vindt
  /// *gezichten*, en mist er aantoonbaar: iemand van achteren, in profiel, met
  /// het hoofd buiten de uitsnede. Ze leest bovendien geen HEIC — de
  /// iPhone-standaard — en ze leest helemaal geen tekst in beeld, dus een
  /// gefotografeerd formulier met een BSN erop ziet ze niet. En de gebruiker mag
  /// haar uitzetten.
  ///
  /// Alleen de gedetecteerde gezichten wegnemen zou dus een afbeelding opleveren
  /// die eruitziet alsof ze is afgehandeld, met een gemist gezicht er nog op. Dat
  /// is exact de fout die deze code elders al één keer heeft gemaakt: een zwart
  /// blok dat niets verbergt en de ontvanger laat denken dat het goed zit.
  ///
  /// De afweging staat al in [statementSpan] en geldt hier onverkort: *te ruim
  /// redigeren is hinderlijk, te krap redigeren is een lek*. Een logo dat op een
  /// geredigeerde slide meesneuvelt is hinderlijk. Een gemist gezicht niet.
  ///
  /// Let op het verschil met de scanner, die mediapaden wél meldt maar niet
  /// redigeert: dáár gaat het om een gebruikersnaam ín het pad, en een pad met
  /// blokjes erin is een kapotte verwijzing. Hier wíssen we de verwijzing.
  ///
  /// ── Waarom er een vlag meereist ──
  ///
  /// Hier stond ooit dat het wissen "de bestaande placeholder oplevert — een
  /// zichtbaar vak, zodat de ontvanger ziet dát er iets weg is". Dat klopte
  /// niet. Die placeholder is hetzelfde grijze vak met het woord "Afbeelding"
  /// dat een slide toont waar de auteur nog géén foto heeft gekozen, en op een
  /// geredigeerde slide leest dat als vergeetachtigheid in plaats van als een
  /// ingreep — terwijl de tekst ernaast wél zwarte blokken laat zien.
  ///
  /// Uit een leeg pad valt dat verschil niet af te leiden, dus zetten we
  /// [Slide.mediaRedacted] en laat de renderer er een zwart vlak van maken. De
  /// vlag wordt niet geserialiseerd; ze bestaat alleen in de projectie.
  ///
  /// De bron blijft ongemoeid: dit raakt alleen wat getoond en geëxporteerd
  /// wordt. Het bestand op schijf houdt zijn afbeelding.
  static ({Slide slide, int count}) _projectMedia(
    Slide slide, {
    required bool active,
  }) {
    if (!active) return (slide: slide, count: 0);
    // Ook de afbeeldingen ín de lopende tekst. Die staan niet in een veld maar
    // als `![…](pad)` in de body, en zonder deze slag reisde een geredigeerde
    // dia gewoon met zijn foto mee naar het scherm en de export — het veld was
    // leeg, de tekst niet.
    final inline = inlineImagePaths(slide.customMarkdown);
    final present =
        [
          slide.imagePath,
          slide.imagePath2,
          slide.videoPath,
          slide.audioPath,
        ].where((p) => p.isNotEmpty).length +
        inline.length;
    if (present == 0) return (slide: slide, count: 0);
    return (
      slide: slide.copyWith(
        imagePath: '',
        imagePath2: '',
        videoPath: '',
        audioPath: '',
        // Het pad eruit, de verwijzing laten staan: `![alt]()` houdt zijn plek
        // in de layout, zodat de tekst niet opschuift alsof er nooit iets stond
        // en de renderer er hetzelfde zwarte vlak van maakt als bij een veld.
        customMarkdown: rewriteInlineImagePaths(
          slide.customMarkdown,
          (_) => '',
        ),
        mediaRedacted: true,
      ),
      count: present,
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
