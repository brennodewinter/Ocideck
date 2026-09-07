import 'package:flutter/foundation.dart';

const kOciServeSettingsKey = 'ociserveSettingsV1';

/// Non-secret configuration for the optional OciServe learning connector.
/// OAuth credentials belong in [SecretStore], never in preferences or decks.
@immutable
class OciServeSettings {
  const OciServeSettings({
    this.enabled = false,
    this.baseUrl = '',
    this.trustedInternal = false,
    this.rememberLogin = false,
    this.acceptedIdentityProviderHost = '',
  });

  final bool enabled;
  final String baseUrl;
  final bool trustedInternal;
  final bool rememberLogin;
  final String acceptedIdentityProviderHost;

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
    rememberLogin: rememberLogin ?? this.rememberLogin,
    acceptedIdentityProviderHost:
        acceptedIdentityProviderHost ?? this.acceptedIdentityProviderHost,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'baseUrl': normalizedBaseUrl,
    'trustedInternal': trustedInternal,
    'rememberLogin': rememberLogin,
    'acceptedIdentityProviderHost': acceptedIdentityProviderHost,
  };

  factory OciServeSettings.fromJson(Map<String, Object?> json) =>
      OciServeSettings(
        enabled: json['enabled'] as bool? ?? false,
        baseUrl: normalizeOciServeBaseUrl(json['baseUrl'] as String? ?? ''),
        trustedInternal: json['trustedInternal'] as bool? ?? false,
        rememberLogin: json['rememberLogin'] as bool? ?? false,
        acceptedIdentityProviderHost:
            (json['acceptedIdentityProviderHost'] as String? ?? '')
                .trim()
                .toLowerCase(),
      );
}

String normalizeOciServeBaseUrl(String raw) {
  var value = raw.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
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
