import 'package:flutter/foundation.dart';

const kOciServeSettingsKey = 'ociserveSettingsV1';

/// Supported OciServe ports. The development stack uses 8443, 1428 and 8080;
/// production HTTPS commonly uses the scheme-default port 443.
const kKnownOciServePorts = [8443, 1428, 8080, 443];

/// Non-secret configuration for the optional OciServe learning connector.
/// OAuth credentials belong in [SecretStore], never in preferences or decks.
@immutable
class OciServeSettings {
  const OciServeSettings({
    this.enabled = false,
    this.baseUrl = '',
    this.trustedInternal = false,
    bool? rememberLogin,
    this.acceptedIdentityProviderHost = '',
  }) : rememberLoginChoice = rememberLogin;

  final bool enabled;
  final String baseUrl;
  final bool trustedInternal;

  /// Wat de gebruiker bij "Ingelogd blijven op dit apparaat" koos, of null
  /// zolang er nooit gekozen is. Alleen een uitdrukkelijke keuze wordt
  /// bewaard: zo blijft een latere wijziging van de standaard mogelijk
  /// zonder iemands "nee" om te draaien.
  final bool? rememberLoginChoice;
  final String acceptedIdentityProviderHost;

  /// Of het vernieuwtoken in de sleutelbos blijft, zodat een volgende start
  /// zonder browser aanmeldt. Standaard aan: bij een cursist die elke keer
  /// opnieuw moet inloggen valt het gemak weg waar deze koppeling voor is, en
  /// het token staat alleen in de sleutelbos van dit apparaat.
  bool get rememberLogin => rememberLoginChoice ?? true;

  String get normalizedBaseUrl => normalizeOciServeBaseUrl(baseUrl);

  bool get isConfigured => validateOciServeBaseUrl(baseUrl) == null;

  OciServeSettings copyWith({
    bool? enabled,
    String? baseUrl,
    bool? trustedInternal,
    bool? rememberLogin,
    String? acceptedIdentityProviderHost,
  }) => OciServeSettings(
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl == null ? this.baseUrl : normalizeOciServeBaseUrl(baseUrl),
    trustedInternal: trustedInternal ?? this.trustedInternal,
    rememberLogin: rememberLogin ?? rememberLoginChoice,
    acceptedIdentityProviderHost:
        acceptedIdentityProviderHost ?? this.acceptedIdentityProviderHost,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'baseUrl': normalizedBaseUrl,
    'trustedInternal': trustedInternal,
    'rememberLoginChoice': ?rememberLoginChoice,
    'acceptedIdentityProviderHost': acceptedIdentityProviderHost,
  };

  factory OciServeSettings.fromJson(Map<String, Object?> json) =>
      OciServeSettings(
        enabled: json['enabled'] as bool? ?? false,
        baseUrl: normalizeOciServeBaseUrl(json['baseUrl'] as String? ?? ''),
        trustedInternal: json['trustedInternal'] as bool? ?? false,
        rememberLogin: _storedRememberChoice(json),
        acceptedIdentityProviderHost:
            (json['acceptedIdentityProviderHost'] as String? ?? '')
                .trim()
                .toLowerCase(),
      );

  /// Oudere versies bewaarden `rememberLogin` altijd, ook als niemand het
  /// vinkje aanraakte; daar was `false` de standaard. Een oud `false` zegt dus
  /// niets over een keuze en telt als "nooit gekozen". Een oud `true` kon alleen
  /// door aanvinken ontstaan en blijft een keuze.
  static bool? _storedRememberChoice(Map<String, Object?> json) {
    final choice = json['rememberLoginChoice'];
    if (choice is bool) return choice;
    return json['rememberLogin'] == true ? true : null;
  }
}

String normalizeOciServeBaseUrl(String raw) {
  var value = raw.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// Returns the entered address first, followed by the same host on known
/// OciServe ports. Authentication remains HTTPS-only on every candidate.
List<OciServeSettings> ociServeConnectionCandidates(OciServeSettings settings) {
  final baseUrl = settings.normalizedBaseUrl;
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !uri.hasAuthority) return [settings];

  final urls = <String>[baseUrl];
  for (final port in kKnownOciServePorts) {
    final candidate = normalizeOciServeBaseUrl(
      uri.replace(port: port).toString(),
    );
    if (!urls.contains(candidate)) urls.add(candidate);
  }
  return [for (final url in urls) settings.copyWith(baseUrl: url)];
}

/// Returns a stable machine-readable refusal reason, or null when usable.
/// Authenticated OciServe traffic always carries a reusable bearer credential,
/// so even a trusted internal server must use HTTPS.
String? validateOciServeBaseUrl(String raw) {
  final uri = Uri.tryParse(normalizeOciServeBaseUrl(raw));
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    return 'invalid_url';
  }
  if (uri.scheme.toLowerCase() != 'https') return 'https_required';
  if (uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasQuery) {
    return 'invalid_url';
  }
  return null;
}
