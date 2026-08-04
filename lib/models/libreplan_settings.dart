/// Configuratie van de optionele LibrePlan-connector. Bewust géén wachtwoord:
/// dat staat versleuteld in de keychain (zie `SecretStore`), gekeyd op
/// [baseUrl] + [username]. Deze waarden mogen wél in het prefs-domein.
///
/// De connector is een read-only REST-importeur: hij haalt een projectsnapshot
/// op van een LibrePlan-instantie en vult OciDeck-slides. Standaard staat alles
/// uit ([enabled] = false): er vertrekt niets van dit apparaat tot de gebruiker
/// een server configureert én een import start. Zie
/// `docs/design/LIBREPLAN_CONNECTOR.md`.
library;

/// Onveranderlijke instellingen voor de LibrePlan-connector. Round-trip via
/// [toJson] / [fromJson] naar het prefs-domein; [copyWith] voor UI-bewerkingen.
class LibreplanSettings {
  /// Hoofdschakelaar. Staat standaard uit; de module is verborgen tot dit
  /// aanstaat. Spiegelt `AiSettings.enabled`.
  final bool enabled;

  /// Basis-URL van de LibrePlan-instantie, bv.
  /// `https://libreplan.example.org/libreplan/`. Zonder trailing slash
  /// gebruikt. De REST-API leeft onder `/ws/rest/` relatief ten opzichte van
  /// deze URL.
  final String baseUrl;

  /// Gebruikersnaam voor HTTP Basic Auth. Het wachtwoord staat in de keychain,
  /// nooit hier. Spiegelt `WebdavServer.username`.
  final String username;

  /// De gebruiker heeft bevestigd dat de server een vertrouwde interne
  /// (privé/LAN) host is; pas dán mag een privé-adres de SSRF-blokkade
  /// passeren en mag plain HTTP. Spiegelt `AiSettings.trustedInternal`.
  final bool trustedInternal;

  const LibreplanSettings({
    this.enabled = false,
    this.baseUrl = '',
    this.username = '',
    this.trustedInternal = false,
  });

  /// Of er een bruikbare server is ingevuld — **los van de schakelaar**.
  ///
  /// Het verschil met [isConfigured] doet ertoe sinds de module een
  /// module-registry-entry krijgt: wie een server en een wachtwoord heeft
  /// ingesteld en daarna de module uitzet, moet die configuratie kunnen blijven
  /// zien en opruimen; anders maakt de schakelaar bestaand werk onbereikbaar.
  /// Dat is de vaste regel uit #648.
  bool get hasBackend => baseUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  /// Of er een bruikbare server is gekozen én de module aan staat.
  bool get isConfigured => enabled && hasBackend;

  /// De host van [baseUrl], of leeg wanneer onparseerbaar.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  /// Of de URL HTTPS gebruikt (of een vertrouwd-intern HTTP-uitzondering
  /// toestaat). Plain HTTP wordt alleen geaccepteerd voor vertrouwde interne
  /// servers — zie het beveiligingscontract in het design-doc §5.3.
  bool get isHttps => Uri.tryParse(baseUrl.trim())?.scheme == 'https';

  LibreplanSettings copyWith({
    bool? enabled,
    String? baseUrl,
    String? username,
    bool? trustedInternal,
  }) {
    return LibreplanSettings(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      trustedInternal: trustedInternal ?? this.trustedInternal,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'baseUrl': baseUrl,
    'username': username,
    'trustedInternal': trustedInternal,
  };

  factory LibreplanSettings.fromJson(Map<String, Object?> json) {
    return LibreplanSettings(
      enabled: (json['enabled'] as bool?) ?? false,
      baseUrl: (json['baseUrl'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      trustedInternal: (json['trustedInternal'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibreplanSettings &&
      other.enabled == enabled &&
      other.baseUrl == baseUrl &&
      other.username == username &&
      other.trustedInternal == trustedInternal;

  @override
  int get hashCode => Object.hash(enabled, baseUrl, username, trustedInternal);
}
