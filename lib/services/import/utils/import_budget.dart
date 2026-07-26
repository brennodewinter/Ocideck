/// Eén samenhangend resourcebudget voor de presentatie-import.
///
/// De import leest een vreemd `.pptx`, `.odp` of `.key` — een bestand dat een
/// aanvaller heeft gemaakt. Elke grens die de invoer mag sturen (hoeveel bytes,
/// hoeveel archiefonderdelen, hoe groot uitgepakt, hoeveel dia's, hoeveel
/// IWA-objecten) hoort hier op één plek, met realistische waarden voor een
/// gewoon werkstation. Zo is er één antwoord op de vraag "waar ligt de grens?"
/// in plaats van losse constanten verspreid over vijf bestanden.
///
/// De grenzen zijn *ruim* voor een echte presentatie en *streng* voor een
/// geconstrueerd bestand: een normaal deck van honderden dia's met media blijft
/// binnen elke grens, een zip-bom of een deck met een miljoen dia's niet.
///
/// **Bewuste afweging.** Door één grens te stellen weigert OciDeck voortaan een
/// *legitiem maar heel groot* deck (bron >512 MiB of >2000 dia's) dat het vroeger
/// — traag — misschien wél inlas. We kiezen robuustheid boven die randgevallen,
/// omdat de weigering het bronbestand ongemoeid laat: de import leest alleen
/// bytes, schrijft of verwijdert de bron nooit, dus de gebruiker raakt geen data
/// kwijt en houdt zijn origineel bruikbaar in het oorspronkelijke programma —
/// alleen deze specifieke, zeldzame conversie is geblokkeerd. De plafonds zijn
/// bovendien op elkaar afgestemd: [maxArchiveEntries] ligt ruim boven wat een
/// deck van [maxSlides] dia's aan onderdelen (elke dia is meerdere parts + media)
/// nodig heeft, zodat de dia-grens niet stil door de entry-grens wordt ingehaald.
///
/// Tijdbudget en annulering horen bij hetzelfde contract, maar krijgen pas
/// betekenis zodra de import op een worker-isolate draait (#875): op de
/// UI-isolate kan niemand het annuleervlag zetten terwijl het parsen loopt.
/// Sinds #875 draagt dit budget daarom óók de [maxDuration]-deadline — een
/// waarde die de worker zelf, binnen zijn eigen isolate, bij elke werkeenheid
/// aftoetst. De *annuleertoken* leeft bewust níét hier: een const, over de
/// isolategrens gekopieerd budget kan geen veranderlijke annuleerstaat dragen,
/// en een isolate deelt geen geheugen. Annuleren wordt daarom buiten dit object
/// om geleverd — de runner beëindigt de worker (desktop) of zet een coöperatief
/// vlag dat de kern bij elke yield afleest (web). Zie `pipeline/import_task.dart`.
library;

const int _kib = 1024;
const int _mib = 1024 * 1024;

/// De grenzen die de bronpresentatie niet mag overschrijden.
///
/// Alle velden zijn `const`, zodat [standard] een compile-time constante is en
/// de handhavingspunten hem als standaardargument kunnen dragen zonder een
/// object per import te maken. Een test bouwt met [ImportBudget.forTest] een
/// piepklein budget, zodat elk overschrijdingspad met een paar bytes invoer te
/// raken is in plaats van met een echte gigabyte.
class ImportBudget {
  const ImportBudget({
    this.maxSourceBytes = 512 * _mib,
    this.maxArchiveEntries = 32768,
    this.maxUncompressedEntry = 384 * _mib,
    this.maxUncompressedTotal = 1536 * _mib, // 1,5 GiB
    this.maxXmlPartBytes = 32 * _mib,
    this.maxSnappyBlockBytes = 128 * _mib,
    this.maxSnappyStreamBytes = 256 * _mib,
    this.maxSlides = 2000,
    this.maxIwaObjects = 500000,
    this.maxDuration = const Duration(minutes: 2),
  });

  /// Het budget dat de app in productie gebruikt: ruim voor elk echt deck, maar
  /// laag genoeg dat een geconstrueerd bestand een gewoon werkstation niet
  /// uitput. Alle handhavingspunten vallen hierop terug als er geen ander
  /// budget wordt meegegeven.
  static const ImportBudget standard = ImportBudget();

  /// Maximale ruwe bestandsgrootte die we in geheugen inlezen.
  final int maxSourceBytes;

  /// Maximaal aantal onderdelen (entries) in het zip-archief. Begrenst de
  /// uitpaklus onafhankelijk van de grootte per onderdeel: een archief met een
  /// miljoen lege onderdelen is even schadelijk als één groot onderdeel. Ruim
  /// boven [maxSlides] gekozen — een dia is meerdere parts (XML, rels, notities)
  /// plus media — zodat een deck dat de dia-grens net haalt niet eerder op de
  /// entry-grens stukloopt.
  final int maxArchiveEntries;

  /// Maximale uitgepakte grootte van één archiefonderdeel (bv. een ingesloten
  /// afbeelding of video).
  final int maxUncompressedEntry;

  /// Maximale uitgepakte grootte van alle onderdelen samen. De belangrijkste
  /// geheugengrens: dit is wat een zip-bom probeert te overschrijden.
  final int maxUncompressedTotal;

  /// Maximale lengte van één XML-onderdeel dat we in één keer parsen (bv.
  /// `presentation.xml` of één `slideN.xml`).
  final int maxXmlPartBytes;

  /// Maximale uitgepakte grootte van één ruw Snappy-blok in een `.iwa`-stroom.
  final int maxSnappyBlockBytes;

  /// Maximale uitgepakte grootte van een volledige `.iwa` Snappy-stroom.
  final int maxSnappyStreamBytes;

  /// Maximaal aantal dia's dat we bouwen. Begrenst de dure per-dia parseerlus,
  /// die anders wordt gestuurd door het aantal `sldId`/`draw:page`-knopen uit
  /// de bron.
  final int maxSlides;

  /// Maximaal aantal IWA-protobuf-objecten dat één Keynote-archief oplevert.
  /// Begrenst de `objects`-map die tijdens het inlezen groeit.
  final int maxIwaObjects;

  /// Maximale wandkloktijd voor één import. De worker toetst dit binnen zijn
  /// eigen isolate bij elke werkeenheid (na het uitpakken, na het parsen, per
  /// dia); een overschrijding eindigt de import als
  /// [ImportFailureReason.tooLarge] met [durationLabel] als grens.
  ///
  /// Grof met opzet: de dominante eenheid — de importer die het hele deck in
  /// één keer parseert — wordt niet ónderbroken maar wél afgetoetst zodra hij
  /// terugkeert. De geheugen- en iteratiegrenzen hierboven binden ieder van die
  /// eenheden; deze deadline is het bovenplafond dat een pathologisch geval
  /// alsnog tot staan brengt, óók op web waar de worker niet gedood kan worden.
  final Duration maxDuration;

  /// Menselijk leesbare beschrijving van [maxDuration] voor de
  /// gebruikersmelding, in het Nederlands (bv. "120 s verwerkingstijd").
  String get durationLabel => '${maxDuration.inSeconds} s verwerkingstijd';

  /// Een piepklein budget voor tests, zodat elk overschrijdingspad met een paar
  /// bytes te raken is. Alleen de meegegeven velden wijken af; de rest houdt de
  /// standaardwaarde.
  factory ImportBudget.forTest({
    int maxSourceBytes = 4 * _kib,
    int maxArchiveEntries = 8,
    int maxUncompressedEntry = 4 * _kib,
    int maxUncompressedTotal = 8 * _kib,
    int maxXmlPartBytes = 4 * _kib,
    int maxSnappyBlockBytes = 4 * _kib,
    int maxSnappyStreamBytes = 8 * _kib,
    int maxSlides = 4,
    int maxIwaObjects = 16,
    Duration maxDuration = const Duration(minutes: 2),
  }) => ImportBudget(
    maxSourceBytes: maxSourceBytes,
    maxArchiveEntries: maxArchiveEntries,
    maxUncompressedEntry: maxUncompressedEntry,
    maxUncompressedTotal: maxUncompressedTotal,
    maxXmlPartBytes: maxXmlPartBytes,
    maxSnappyBlockBytes: maxSnappyBlockBytes,
    maxSnappyStreamBytes: maxSnappyStreamBytes,
    maxSlides: maxSlides,
    maxIwaObjects: maxIwaObjects,
    maxDuration: maxDuration,
  );
}

/// Gegooid zodra de bronpresentatie een grens uit het [ImportBudget]
/// overschrijdt.
///
/// Draagt een menselijk leesbare [limitLabel] (bv. "2000 dia's", "1,5 GiB
/// uitgepakt") die de importer als `{limiet}`-argument in de
/// [ImportFailureReason.tooLarge]-melding zet. Een aparte klasse zodat de
/// importers hem vóór de generieke `FormatException` kunnen opvangen: een
/// budgetoverschrijding is geen beschadigd bestand, en de gebruiker verdient de
/// echte reden.
class ImportBudgetException implements Exception {
  const ImportBudgetException(this.limitLabel);

  /// Menselijk leesbare beschrijving van de overschreden grens, in het
  /// Nederlands, geschikt om in de gebruikersmelding te tonen.
  final String limitLabel;

  @override
  String toString() => 'ImportBudgetException: $limitLabel overschreden.';
}
