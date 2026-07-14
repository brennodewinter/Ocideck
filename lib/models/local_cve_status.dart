/// Wat er lokaal ligt: welke release, hoeveel records, hoe groot.
class LocalCveStats {
  /// De release-tag van CVE List V5 waaruit de index gebouwd is.
  final String release;

  /// Wanneer de index gebouwd is (ISO-datum).
  final String builtOn;

  final int records;

  /// Grootte van het indexbestand in bytes.
  final int bytes;

  const LocalCveStats({
    required this.release,
    required this.builtOn,
    required this.records,
    required this.bytes,
  });

  Map<String, dynamic> toJson() => {
    'release': release,
    'builtOn': builtOn,
    'records': records,
    'bytes': bytes,
  };

  static LocalCveStats fromJson(Map<String, dynamic> json) => LocalCveStats(
    release: (json['release'] as String?) ?? '',
    builtOn: (json['builtOn'] as String?) ?? '',
    records: (json['records'] as num?)?.toInt() ?? 0,
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
  );
}

/// De stappen van het opbouwen van de lokale database. Ze duren allemaal lang
/// genoeg om te benoemen: wie een half uur naar een balk kijkt, wil weten
/// wáárop hij wacht.
enum CveIngestPhase {
  /// De nieuwste release opzoeken (welk bestand is het vandaag?).
  discovering,

  /// Het archief binnenhalen (~550 MB).
  downloading,

  /// Het buitenste zip-archief uitpakken (er zit een zip in een zip).
  extracting,

  /// De records lezen en de index schrijven.
  indexing,
}

/// Voortgang van één opbouw, voor de balk in het instellingenscherm.
class CveIngestProgress {
  final CveIngestPhase phase;

  /// Bytes binnen / totaal tijdens [CveIngestPhase.downloading]; 0 als onbekend.
  final int received;
  final int total;

  /// Aantal geïndexeerde records tijdens [CveIngestPhase.indexing].
  final int records;

  const CveIngestProgress({
    required this.phase,
    this.received = 0,
    this.total = 0,
    this.records = 0,
  });

  /// 0..1, of null wanneer de fase geen betekenisvolle breuk heeft (dan hoort
  /// er een onbepaalde balk te staan, geen valse 0%).
  double? get fraction {
    if (phase == CveIngestPhase.downloading && total > 0) {
      return (received / total).clamp(0.0, 1.0);
    }
    return null;
  }
}

/// Opgegooid wanneer een opbouw niet lukt, met de reden die de UI toont.
///
/// Staat bij het model en niet bij de ingest-code, omdat de web-variant (die
/// geen `dart:io` mag aanraken) hem ook moet kunnen gooien.
class CveIngestException implements Exception {
  final CveIngestFailure failure;
  final String? detail;
  const CveIngestException(this.failure, [this.detail]);

  @override
  String toString() =>
      'CveIngestException($failure${detail == null ? '' : ': $detail'})';
}

/// Waarom een opbouw niet gelukt is. Elke reden krijgt zijn eigen zin in de UI:
/// "mislukt" laat de gebruiker raden wat hij eraan kan doen.
enum CveIngestFailure {
  /// Deze knop bestaat niet op het web (geen bestandssysteem, en een download
  /// van honderden megabytes hoort niet in een tab).
  unsupportedPlatform,

  /// Geen toestemming voor uitgaand verkeer.
  noConsent,

  /// De release of het archief was niet op te halen.
  networkFailed,

  /// Het archief was niet wat we verwachtten (geen zip, of geen CVE's erin).
  invalidArchive,

  /// De gebruiker heeft afgebroken.
  cancelled,

  /// Geen ruimte op schijf.
  diskFull,
}
