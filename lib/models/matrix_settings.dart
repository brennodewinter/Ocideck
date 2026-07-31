// The non-secret configuration of a Matrix account used for real-time
// collaboration (`docs/design/SELF_ENCRYPTED_RELAY.md` §8, phase P-D). It is the
// collaboration counterpart of `WebdavServer`: the homeserver origin, the user id
// and the device id live here (persisted in the preferences domain), while the
// access token and the device key material go to the keychain via `SecretStore`.
//
// Deliberately not a `StorageConnection`: a homeserver is a collaboration
// rendez-vous, not a place decks are stored (the file stays on the user's own
// storage — P2). It carries the same `trustedInternal` / `pinnedCertSha256`
// posture as WebDAV so a private/self-hosted homeserver can pass the SSRF guard
// only on an explicit opt-in.

/// One configured Matrix account. Bevat bewust geen access-token: dat staat
/// versleuteld in de keychain (`SecretStore`), gekeyd op [homeserverUrl] +
/// [userId]. Deze waarden mogen wél in het prefs-domein.
class MatrixServer {
  /// Homeserver origin without a path, e.g. `https://matrix.example.org`.
  /// Trailing slashes are ignored when building URLs.
  final String homeserverUrl;

  /// The full Matrix user id, e.g. `@alice:example.org`.
  final String userId;

  /// The Matrix device id assigned at login; empty until a session is
  /// established. Part of the collaboration participant id (see [participantId]).
  final String deviceId;

  /// The user has explicitly confirmed this is a trusted internal homeserver;
  /// only then may a private/LAN host pass the SSRF block (mirrors WebDAV).
  final bool trustedInternal;

  /// SHA-256 of a certificate the user explicitly trusts, or empty when only the
  /// ordinary chain of recognised issuers counts (mirrors WebDAV; see NetGuard).
  final String pinnedCertSha256;

  const MatrixServer({
    required this.homeserverUrl,
    required this.userId,
    this.deviceId = '',
    this.trustedInternal = false,
    this.pinnedCertSha256 = '',
  });

  /// Ready to use once a homeserver and a user id are set.
  bool get isConfigured =>
      homeserverUrl.trim().isNotEmpty && userId.trim().isNotEmpty;

  /// The parsed homeserver origin, or null when [homeserverUrl] is unparseable.
  Uri? get origin {
    final uri = Uri.tryParse(homeserverUrl.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  /// The host of [homeserverUrl], or empty when unparseable.
  String get host => origin?.host ?? '';

  /// The collaboration participant id: `<userId>:<deviceId>` (the value the
  /// crypto stamps into sealed envelopes as `sender_device`). Empty [deviceId]
  /// yields a trailing colon — a not-yet-logged-in placeholder.
  String get participantId => '$userId:$deviceId';

  MatrixServer copyWith({
    String? homeserverUrl,
    String? userId,
    String? deviceId,
    bool? trustedInternal,
    String? pinnedCertSha256,
  }) => MatrixServer(
    homeserverUrl: homeserverUrl ?? this.homeserverUrl,
    userId: userId ?? this.userId,
    deviceId: deviceId ?? this.deviceId,
    trustedInternal: trustedInternal ?? this.trustedInternal,
    pinnedCertSha256: pinnedCertSha256 ?? this.pinnedCertSha256,
  );

  Map<String, Object?> toJson() => {
    'homeserverUrl': homeserverUrl,
    'userId': userId,
    'deviceId': deviceId,
    'trustedInternal': trustedInternal,
    'pinnedCertSha256': pinnedCertSha256,
  };

  /// Decode a server written by [toJson]. Tolerant of missing optional fields so
  /// a record stored by an older build still loads.
  factory MatrixServer.fromJson(Map<String, Object?> json) => MatrixServer(
    homeserverUrl: (json['homeserverUrl'] as String?) ?? '',
    userId: (json['userId'] as String?) ?? '',
    deviceId: (json['deviceId'] as String?) ?? '',
    trustedInternal: (json['trustedInternal'] as bool?) ?? false,
    pinnedCertSha256: (json['pinnedCertSha256'] as String?) ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is MatrixServer &&
      other.homeserverUrl == homeserverUrl &&
      other.userId == userId &&
      other.deviceId == deviceId &&
      other.trustedInternal == trustedInternal &&
      other.pinnedCertSha256 == pinnedCertSha256;

  @override
  int get hashCode => Object.hash(
    homeserverUrl,
    userId,
    deviceId,
    trustedInternal,
    pinnedCertSha256,
  );
}
