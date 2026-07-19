/// Hoe de actuele upstream-versie van een standaard te achterhalen is.
///
/// Het onderscheid dat telt is niet "nieuw of oud" maar **"gecontroleerd of
/// niet"**: een bron die we niet bevragen mag nooit voorbijkomen als "actueel",
/// want dan leest stilte als goedkeuring — precies hoe een gebundelde catalogus
/// jarenlang onopgemerkt veroudert.
///
/// **Er is met opzet geen `manual`-waarde.** Die stond er eerst wel, voor CWE en
/// CVSS, tot bleek dat beide gewoon te bevragen zijn: MITRE heeft een REST-API
/// en FIRST publiceert per versie een schema op een voorspelbare URL. "Niet te
/// controleren" was luiheid, geen eigenschap van de bron. Blijkt een toekomstige
/// bron écht gesloten, voeg de waarde dan terug mét de reden — maar begin er
/// niet mee.
enum UpstreamProbe {
  /// De releases van een GitHub-repo (`owner/repo` in [ReferenceStandard.probeTarget]);
  /// vergelijkt de release-tag met [ReferenceStandard.bundledVersion].
  githubReleases,

  /// Idem, maar vergelijkt de **publicatiedatum** van de laatste release met een
  /// gebundelde versie die zelf een datum is (`JJJJ-MM-DD`).
  ///
  /// Bestaat omdat niet elke bron versienummers voert: de MIAUW-methodologie
  /// tagt releases met namen ("Otis"), en die naast een datum leggen levert
  /// eeuwig "verouderd" op. Een poort die altijd afgaat, leert mensen wegkijken
  /// — dan is hij schadelijker dan geen poort. Datums zijn bovendien wél
  /// ordenbaar, dus hier kan "nieuwer dan wat wij hebben" echt worden vastgesteld.
  githubReleaseDate,

  /// De `JDBOR`-datum in de kop van een Orphanet-productbestand.
  ///
  /// Orphanet voert geen versienummers maar datumt elke uitgave in de wortel van
  /// het XML-bestand. Die bestanden zijn ruim 50 MB per taal, dus de poort haalt
  /// alleen de eerste kilobytes op met een range-verzoek — de datum staat in de
  /// eerste regel.
  orphanetDate,

  /// De datum van de laatste commit op de standaardbranch.
  ///
  /// Voor bronnen die géén releases en géén tags voeren — MASWE is er zo een.
  /// Daar is "welke versie" geen zinnige vraag en is de dag van overname het
  /// enige eerlijke antwoord. Een verzonnen versienummer zou hier een precisie
  /// suggereren die de bron niet biedt.
  githubCommitDate,

  /// MITRE's CWE REST API (`cwe-api.mitre.org`), die naast de versie ook de
  /// inhoudsdatum en het **aantal** zwakheden geeft. Dat aantal is een
  /// gratis integriteitscontrole: wijkt onze bundel ervan af, dan is hij
  /// afgekapt of half geregenereerd, en dat is een ander soort fout dan
  /// veroudering.
  cweApi,

  /// Bron die geen "laatste versie" publiceert, maar wél per versie een
  /// document op een voorspelbare URL. We proberen de **opvolgers** van wat we
  /// bundelen: bestaat `…v4.1…` of `…v5.0…` al, dan is er iets nieuwers.
  ///
  /// Levert geen versienummer op maar wel het antwoord dat telt — of we
  /// achterlopen. FIRST publiceert de CVSS-specificatie zo.
  successorDocument,
}

/// Eén gebundelde referentiestandaard: wat we ervan meedragen, welke versie dat
/// is, en waar de echte bron staat.
///
/// Dit is de enige plek waar die feiten als *data* staan. Ze stonden verspreid
/// in proza — een const in de catalogus, een regel in `LICENSE_COMPLIANCE.md`,
/// een zin in een ontwerpdoc — en proza kun je niet toetsen. Zowel de
/// verouderingspoort (`tool/check_reference_data.dart`) als het overzicht in de
/// instellingen als straks de bijlage in het rapport (MIAUW EIS 4.3.2 / 4.8.2)
/// lezen hiervandaan, zodat er geen tweede waarheid kan ontstaan.
class ReferenceStandard {
  /// Stabiele sleutel, bv. `wstg`. Nooit tonen; gebruik [name].
  final String id;

  /// Naam zoals de gebruiker hem kent, bv. `OWASP WSTG`.
  final String name;

  /// De versie die OciDeck meedraagt, bv. `4.2`. Leeg wanneer de bron geen
  /// versienummers voert.
  final String bundledVersion;

  /// Publieke verwijzing naar de bron — MIAUW EIS 4.8.2.3 vraagt hier expliciet
  /// om.
  final String url;

  /// Wat er precies gebundeld is, in één zin. Voor EIS 4.8.2.1, en om de
  /// verwachting te temperen: van de meeste standaarden dragen we de *index*
  /// mee, niet de inhoud.
  final String bundled;

  /// De licentie van het gebundelde materiaal (niet die van OciDeck).
  final String licence;

  final UpstreamProbe probe;

  /// Waar [probe] naar kijkt, bv. `OWASP/wstg`. Leeg bij [UpstreamProbe.manual].
  final String probeTarget;

  /// Of een nieuwere upstreamversie de **poort** mag laten falen.
  ///
  /// Standaard niet-adviserend: een verouderde standaard is een blokkade, want
  /// anders sluipt hij erin. Maar dat is de goede regel voor een catalogus die
  /// de gebruiker *leest* — bij een verouderde CWE-regel staat er een verkeerd
  /// nummer in een lijst.
  ///
  /// Voor een **detectielexicon** klopt hij niet. Daar vuurt elke term, dus een
  /// verversing kost een termdiff lezen en de vals-positievencorpus opnieuw
  /// wegen; en de bron brengt maandelijks uit. Een poort die daarop rood wordt,
  /// staat binnen twee maanden permanent rood en gaat uit — en dan is de
  /// zichtbaarheid weg die het hele doel was. Zulke bronnen melden zich wél,
  /// maar alleen adviserend (`make catalogs-outdated`).
  final bool advisory;

  const ReferenceStandard({
    required this.id,
    required this.name,
    required this.bundledVersion,
    required this.url,
    required this.bundled,
    required this.licence,
    required this.probe,
    this.probeTarget = '',
    this.advisory = false,
  });

  /// Naam met versie, zoals hij in een rapportbijlage hoort te staan.
  String get label => bundledVersion.isEmpty ? name : '$name v$bundledVersion';
}

/// De uitkomst van één vergelijking met upstream.
class StandardFreshness {
  final ReferenceStandard standard;

  /// De actuele upstream-versie, of null wanneer die niet is vastgesteld.
  final String? latestVersion;

  /// Waarom er geen oordeel is, wanneer [latestVersion] null is. Leeg als er
  /// wél een oordeel is.
  final String unknownReason;

  const StandardFreshness({
    required this.standard,
    this.latestVersion,
    this.unknownReason = '',
  });

  /// Er is een upstream-versie vastgesteld én die wijkt af van wat we bundelen.
  ///
  /// Bewust een strikte tekstvergelijking en geen semver-ordening: bij OWASP
  /// betekent een sprong van 4.2 naar 2.0 (MASTG hernummerde bij de herbouw)
  /// dat "nieuwer" niet uit de getallen af te leiden is. Afwijkend is genoeg
  /// reden om een mens te laten kijken.
  bool get isOutdated =>
      latestVersion != null &&
      standard.bundledVersion.isNotEmpty &&
      latestVersion != standard.bundledVersion;

  /// Niet vast te stellen. Let op: dit is géén synoniem voor "actueel".
  bool get isUnknown => latestVersion == null;

  bool get isCurrent => latestVersion == standard.bundledVersion;
}
