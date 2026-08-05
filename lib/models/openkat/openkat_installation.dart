/// Eén aangesloten OpenKAT-installatie (Rocky). Bewust géén toegangstoken:
/// dat staat in de sleutelhanger (`SecretStore`), gekeyd op [id]. Prefs mogen
/// alleen niet-geheime metadata bevatten.
///
/// Meerdere installaties naast elkaar (productie + acceptatie, of meerdere
/// klantomgevingen). Geen globale "actieve server" — de UI toont altijd welke
/// installatie je gebruikt.
library;

import 'package:uuid/uuid.dart';

/// Laatst bekende uitkomst van een verbindingstest. Alleen metadata; nooit
/// een token of response-body.
enum OpenKatInstallationStatus {
  /// Nog nooit succesvol getest sinds opslaan/bewerken.
  unchecked,

  /// Laatste test lukte (org-lijst bereikbaar).
  connected,

  /// Geen token in de sleutelhanger voor deze installatie.
  tokenMissing,

  /// Laatste test faalde (auth, netwerk, hostweigering, …).
  failed,
}

/// Onveranderlijke metadata van één OpenKAT-server. Round-trip via
/// [toJson] / [fromJson] naar prefs; token apart via SecretStore.
class OpenKatInstallation {
  /// Stabiele id; keychain-sleutel hangt hieraan, dus hernoemen mag nooit.
  final String id;

  /// Door de gebruiker gekozen weergavenaam (bijv. "Productie").
  final String name;

  /// Basis-URL van Rocky, zonder trailing slash (genormaliseerd bij opslaan).
  final String baseUrl;

  /// Eigen netwerk (LAN): plain HTTP + privé-IP via NetGuard alleen als dit
  /// expliciet aan staat. Spiegelt `LibreplanSettings.trustedInternal`.
  final bool trustedInternal;

  /// Moment van de laatste verbindingstest, of null als nooit getest.
  final DateTime? lastCheckedAt;

  /// Uitkomst van die test (of [OpenKatInstallationStatus.unchecked]).
  final OpenKatInstallationStatus lastStatus;

  const OpenKatInstallation({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.trustedInternal = false,
    this.lastCheckedAt,
    this.lastStatus = OpenKatInstallationStatus.unchecked,
  });

  /// Nieuwe installatie met verse id.
  factory OpenKatInstallation.create({
    required String name,
    required String baseUrl,
    bool trustedInternal = false,
  }) {
    return OpenKatInstallation(
      id: const Uuid().v4(),
      name: name.trim(),
      baseUrl: normalizeOpenKatBaseUrl(baseUrl),
      trustedInternal: trustedInternal,
    );
  }

  /// Of er een bruikbaar adres én een weergavenaam staan (token apart).
  bool get isConfigured =>
      name.trim().isNotEmpty && baseUrl.trim().isNotEmpty;

  /// Host uit [baseUrl], of leeg wanneer onparseerbaar.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  /// Of de URL HTTPS gebruikt.
  bool get isHttps => Uri.tryParse(baseUrl.trim())?.scheme == 'https';

  OpenKatInstallation copyWith({
    String? name,
    String? baseUrl,
    bool? trustedInternal,
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    OpenKatInstallationStatus? lastStatus,
  }) {
    return OpenKatInstallation(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl != null ? normalizeOpenKatBaseUrl(baseUrl) : this.baseUrl,
      trustedInternal: trustedInternal ?? this.trustedInternal,
      lastCheckedAt: clearLastCheckedAt
          ? null
          : (lastCheckedAt ?? this.lastCheckedAt),
      lastStatus: lastStatus ?? this.lastStatus,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'trustedInternal': trustedInternal,
    if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt!.toIso8601String(),
    'lastStatus': lastStatus.name,
  };

  factory OpenKatInstallation.fromJson(Map<String, Object?> json) {
    final statusName = json['lastStatus'] as String?;
    final status = OpenKatInstallationStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => OpenKatInstallationStatus.unchecked,
    );
    final checkedRaw = json['lastCheckedAt'] as String?;
    return OpenKatInstallation(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      name: (json['name'] as String?) ?? '',
      baseUrl: normalizeOpenKatBaseUrl((json['baseUrl'] as String?) ?? ''),
      trustedInternal: (json['trustedInternal'] as bool?) ?? false,
      lastCheckedAt: checkedRaw == null ? null : DateTime.tryParse(checkedRaw),
      lastStatus: status,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OpenKatInstallation &&
      other.id == id &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      other.trustedInternal == trustedInternal &&
      other.lastCheckedAt == lastCheckedAt &&
      other.lastStatus == lastStatus;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    baseUrl,
    trustedInternal,
    lastCheckedAt,
    lastStatus,
  );
}

/// Strip trailing slashes zodat `https://a/` en `https://a` dezelfde
/// keychain-/vergelijkingswaarde krijgen.
String normalizeOpenKatBaseUrl(String raw) {
  var s = raw.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Vroege URL-validatie voor de wizard. Retourneert een l10n-bronzin bij fout,
/// of null wanneer bruikbaar. [trustedInternal] bepaalt of HTTP mag.
String? validateOpenKatBaseUrl(String raw, {required bool trustedInternal}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'Vul een adres in, bijvoorbeeld https://openkat.voorbeeld.nl';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
    return 'Dit adres is niet geldig. Controleer of u een volledige URL heeft ingevuld.';
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    return 'Dit adres is niet geldig. Controleer of u een volledige URL heeft ingevuld.';
  }
  if (scheme == 'http' && !trustedInternal) {
    return 'Het adres moet met https:// beginnen, of zet Eigen netwerk aan voor HTTP op het eigen netwerk.';
  }
  return null;
}
