/// Hoe de actuele upstream-versie van een standaard te achterhalen is.
///
/// Het onderscheid dat telt is niet "nieuw of oud" maar **"gecontroleerd of
/// niet"**. Een standaard die we niet automatisch kunnen bevragen mag nooit
/// voorbijkomen als "actueel" — dan zou stilte als goedkeuring lezen, en precies
/// dat is hoe een gebundelde catalogus jarenlang onopgemerkt veroudert.
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

  /// Niet automatisch te bevragen: de bron publiceert geen machineleesbare
  /// release-aanduiding. De poort meldt dit als **onbekend**, niet als actueel.
  manual,
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

  const ReferenceStandard({
    required this.id,
    required this.name,
    required this.bundledVersion,
    required this.url,
    required this.bundled,
    required this.licence,
    required this.probe,
    this.probeTarget = '',
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
