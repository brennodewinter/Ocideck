/// Configuratie van het optionele ASR-serverprofiel voor transcriptie
/// (docs/design/TRANSCRIPTION.md §4.3, #2524). Bewust géén API-sleutel: die
/// staat in de sleutelbos (`SecretStore.asrApiKeyKey`), gekeyd op [baseUrl].
///
/// De serverroute is de enige plek waar audio het apparaat verlaat — en
/// alleen omdat de gebruiker dit profiel aanzette én per taak bevestigde.
/// Standaard staat alles uit: [enabled] = false, [mode] =
/// [AsrServerMode.none]. Deze waarden mogen in het prefs-domein; round-trip
/// via [toJson]/[fromJson], [copyWith] voor UI-bewerkingen.
library;

/// Welke klasse server de gebruiker koos — bepaalt welke egressregels
/// gelden. Spiegelt de tiers van `AiBackendMode` maar is een eigen enum:
/// de semantiek verschilt (op web is `cloud` juist dé route die #2524
/// bedient) en een gedeelde enum zou elke AI-wijziging stil aan deze poort
/// koppelen.
enum AsrServerMode {
  /// Geen server gekozen — er vertrekt niets.
  none,

  /// Een server op dit apparaat zelf (loopback) — de enige plek waar
  /// `http://` zonder TLS acceptabel is.
  loopback,

  /// Een eigen server in een vertrouwd intern netwerk (LAN). Vereist de
  /// expliciete opt-in [AsrServerProfile.trustedInternal].
  lan,

  /// Een externe dienst — vereist HTTPS én de expliciete bevestiging
  /// [AsrServerProfile.cloudConfirmed] voor díe bestemming.
  cloud,
}

/// Onveranderlijke instellingen voor één ASR-serverprofiel.
class AsrServerProfile {
  /// Staat het profiel aan. Standaard uit: tot de gebruiker bewust kiest
  /// vertrekt er geen byte naar een server.
  final bool enabled;

  final AsrServerMode mode;

  /// Basis-URL van de server, bv. `http://127.0.0.1:8080` of
  /// `https://asr.example.nl`. De adapter hangt er zijn paden aan vast.
  final String baseUrl;

  /// Eigen naam voor dit profiel — verschijnt in de provenienceregel
  /// (`Engine: <name>`) zodat een lezer ziet dat de tekst van buiten het
  /// apparaat kwam (§4.3). Leeg = de host zelf.
  final String name;

  /// Alleen bij [AsrServerMode.lan]: de gebruiker heeft bevestigd dat dit
  /// een vertrouwd intern adres is; pas dan mag een privé-/LAN-adres de
  /// SSRF-blokkade passeren.
  final bool trustedInternal;

  /// Alleen bij [AsrServerMode.cloud]: de gebruiker heeft bevestigd dat
  /// audio naar díe specifieke externe dienst mag.
  final bool cloudConfirmed;

  const AsrServerProfile({
    this.enabled = false,
    this.mode = AsrServerMode.none,
    this.baseUrl = '',
    this.name = '',
    this.trustedInternal = false,
    this.cloudConfirmed = false,
  });

  /// Standaard-basis-URL voor de loopback-tier (whisper.cpp's
  /// `whisper-server`). Alleen een suggestie in de UI.
  static const String defaultLoopbackBaseUrl = 'http://127.0.0.1:8080';

  /// Of er een bruikbare server is ingevuld — los van de schakelaar, zodat
  /// een uitgeschakeld profiel zijn instellingen blijft tonen (zelfde
  /// regel als `AiSettings.hasBackend`, #648).
  bool get hasEndpoint =>
      mode != AsrServerMode.none && baseUrl.trim().isNotEmpty;

  /// Of het profiel aan staat én een endpoint heeft.
  bool get isConfigured => enabled && hasEndpoint;

  /// De host van [baseUrl], of leeg wanneer onparseerbaar.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  /// Wat in de provenienceregel komt: de eigen naam, of de host.
  String get provenanceName => name.trim().isNotEmpty ? name.trim() : host;

  AsrServerProfile copyWith({
    bool? enabled,
    AsrServerMode? mode,
    String? baseUrl,
    String? name,
    bool? trustedInternal,
    bool? cloudConfirmed,
  }) {
    return AsrServerProfile(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      baseUrl: baseUrl ?? this.baseUrl,
      name: name ?? this.name,
      trustedInternal: trustedInternal ?? this.trustedInternal,
      cloudConfirmed: cloudConfirmed ?? this.cloudConfirmed,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'baseUrl': baseUrl,
    'name': name,
    'trustedInternal': trustedInternal,
    'cloudConfirmed': cloudConfirmed,
  };

  factory AsrServerProfile.fromJson(Map<String, Object?> json) {
    return AsrServerProfile(
      enabled: (json['enabled'] as bool?) ?? false,
      mode: _modeFromName(json['mode'] as String?),
      baseUrl: (json['baseUrl'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      trustedInternal: (json['trustedInternal'] as bool?) ?? false,
      cloudConfirmed: (json['cloudConfirmed'] as bool?) ?? false,
    );
  }

  static AsrServerMode _modeFromName(String? name) {
    for (final m in AsrServerMode.values) {
      if (m.name == name) return m;
    }
    return AsrServerMode.none;
  }

  @override
  bool operator ==(Object other) =>
      other is AsrServerProfile &&
      other.enabled == enabled &&
      other.mode == mode &&
      other.baseUrl == baseUrl &&
      other.name == name &&
      other.trustedInternal == trustedInternal &&
      other.cloudConfirmed == cloudConfirmed;

  @override
  int get hashCode => Object.hash(
    enabled,
    mode,
    baseUrl,
    name,
    trustedInternal,
    cloudConfirmed,
  );
}
