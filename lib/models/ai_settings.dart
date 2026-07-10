/// Configuratie van de optionele AI-assistentie. Bewust géén API-sleutel: die
/// staat versleuteld in de keychain (zie `SecretStore`), gekeyd op [baseUrl].
/// Deze waarden mogen wél in het prefs-domein.
///
/// De backend is een OpenAI-compatibele `/v1/chat/completions`-server. Er zijn
/// drie tiers met oplopende privacy-impact — zie [AiBackendMode]. Standaard
/// staat alles uit ([enabled] = false, [mode] = [AiBackendMode.none]): er
/// vertrekt niets van dit apparaat tot de gebruiker een backend kiest én een
/// actie start.
library;

/// De backend-tier waarmee een consument (later: afbeeldingstags, pentesttekst)
/// praat. De volgorde weerspiegelt oplopende egress-impact; de veiligheidsgate
/// ([AiSecurityGate]) handhaaft per tier een ander netwerkregime.
enum AiBackendMode {
  /// Niets gekozen. Standaard, ook wanneer [AiSettings.enabled] al aanstaat:
  /// er wordt niets verstuurd tot de gebruiker bewust een tier kiest.
  none,

  /// Lokaal model op dit apparaat (Ollama/LM Studio/llama.cpp) op een
  /// loopback-adres. Dit is lokale IPC, geen egress: er verlaat niets het
  /// apparaat, dus geen outbound-privacytoestemming nodig.
  local,

  /// Eigen server op het LAN/VPN. Alleen bereikbaar wanneer de gebruiker de
  /// server als vertrouwd intern heeft gemarkeerd ([trustedInternal]); dan via
  /// `NetGuard.safeResolveTrusted(allowPrivate: true)`.
  selfHosted,

  /// Externe clouddienst (publieke host). Fail-closed achter de bestaande
  /// outbound-privacytoestemming plus een expliciete bevestiging die de
  /// bestemming benoemt ([cloudConfirmed]). Nooit standaard; geblokkeerd op web.
  cloud,
}

/// Onveranderlijke instellingen voor de AI-backend. Round-trip via [toJson] /
/// [fromJson] naar het prefs-domein; [copyWith] voor UI-bewerkingen.
class AiSettings {
  /// Hoofdschakelaar. Staat standaard uit; features blijven verborgen tot dit
  /// aanstaat. Ook aan blijft [mode] standaard [AiBackendMode.none].
  final bool enabled;

  /// Gekozen backend-tier.
  final AiBackendMode mode;

  /// Basis-URL van de OpenAI-compatibele API, inclusief `/v1`, bv.
  /// `http://127.0.0.1:11434/v1`. Zonder trailing slash gebruikt.
  final String baseUrl;

  /// Modelnaam zoals de backend die kent, bv. `gemma3:4b`. Nooit hard-coded:
  /// de roster verschuift, dus de gebruiker vult in wat de endpoint aanbiedt.
  final String model;

  /// De gebruiker heeft bevestigd dat de zelf-gehoste server een vertrouwde
  /// interne (privé/LAN) host is; pas dán mag een privé-adres de SSRF-blokkade
  /// passeren. Spiegelt `WebdavServer.trustedInternal`.
  final bool trustedInternal;

  /// De gebruiker heeft, apart van de algemene outbound-toestemming, bevestigd
  /// dat gegevens naar deze specifieke externe clouddienst mogen. Alleen
  /// relevant voor [AiBackendMode.cloud].
  final bool cloudConfirmed;

  const AiSettings({
    this.enabled = false,
    this.mode = AiBackendMode.none,
    this.baseUrl = '',
    this.model = '',
    this.trustedInternal = false,
    this.cloudConfirmed = false,
  });

  /// Standaard-basis-URL voor de lokale tier (Ollama's OpenAI-compat laag).
  /// Alleen een suggestie in de UI; de gebruiker mag de poort aanpassen.
  static const String defaultLocalBaseUrl = 'http://127.0.0.1:11434/v1';

  /// Of er een bruikbare backend is gekozen (los van of de gate hem toestaat).
  bool get isConfigured =>
      enabled && mode != AiBackendMode.none && baseUrl.trim().isNotEmpty;

  /// De host van [baseUrl], of leeg wanneer onparseerbaar.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  AiSettings copyWith({
    bool? enabled,
    AiBackendMode? mode,
    String? baseUrl,
    String? model,
    bool? trustedInternal,
    bool? cloudConfirmed,
  }) {
    return AiSettings(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      trustedInternal: trustedInternal ?? this.trustedInternal,
      cloudConfirmed: cloudConfirmed ?? this.cloudConfirmed,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'baseUrl': baseUrl,
    'model': model,
    'trustedInternal': trustedInternal,
    'cloudConfirmed': cloudConfirmed,
  };

  factory AiSettings.fromJson(Map<String, Object?> json) {
    return AiSettings(
      enabled: (json['enabled'] as bool?) ?? false,
      mode: _modeFromName(json['mode'] as String?),
      baseUrl: (json['baseUrl'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      trustedInternal: (json['trustedInternal'] as bool?) ?? false,
      cloudConfirmed: (json['cloudConfirmed'] as bool?) ?? false,
    );
  }

  static AiBackendMode _modeFromName(String? name) {
    for (final m in AiBackendMode.values) {
      if (m.name == name) return m;
    }
    return AiBackendMode.none;
  }

  @override
  bool operator ==(Object other) =>
      other is AiSettings &&
      other.enabled == enabled &&
      other.mode == mode &&
      other.baseUrl == baseUrl &&
      other.model == model &&
      other.trustedInternal == trustedInternal &&
      other.cloudConfirmed == cloudConfirmed;

  @override
  int get hashCode => Object.hash(
    enabled,
    mode,
    baseUrl,
    model,
    trustedInternal,
    cloudConfirmed,
  );
}
