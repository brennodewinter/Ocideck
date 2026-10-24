// A user-approved meeting-deployment profile (`docs/design/COLLABORATION.md`
// §7.1.6, "self-hosted provider profiles"). A hard-coded host list can never
// name an organisation's own Jitsi — so the user (or an admin) approves an
// exact origin, and ONLY that origin wins: a profile never claims subdomains
// and never rewrites an opaque invitation token.
//
// The profile is the unit the resolver consults for self-hosted links, and it
// carries the two trust decisions the user made explicitly: [trustedInternal]
// (a LAN/private host may pass the SSRF block — the WebDAV posture) and
// [pinnedCertSha256] (an explicitly trusted certificate, desktop only).
//
// Persistence is non-secret profile metadata in preferences — credentials
// never live here (`SecretStore` is the place for those, when a later phase
// needs them). Export/import must not carry trust decisions silently:
// receiving a profile on another device requires re-approval.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A user-approved deployment of one meeting provider.
class MeetingProviderProfile {
  const MeetingProviderProfile({
    required this.id,
    required this.providerId,
    required this.origin,
    this.allowedJoinPathPrefixes = const <String>{},
    this.trustedInternal = false,
    this.pinnedCertSha256 = '',
  });

  /// Stable key for edits/deletes (any unique string; not shown to servers).
  final String id;

  /// The [MeetingProvider.id] this deployment belongs to (e.g. `jitsi`).
  final String providerId;

  /// The approved origin: scheme + host + port, no path/query/fragment.
  /// `https://meet.example.org` and `https://meet.example.org:4443` are
  /// DIFFERENT origins — a profile never widens to neighbouring ports.
  final Uri origin;

  /// Path prefixes a join link may start with on this origin. An empty set
  /// means "any non-root path is a meeting" — the shape of a root deployment
  /// (`https://meet.example.org/<room>`). `{'/meet/'}` limits the claim to
  /// `https://meet.example.org/meet/<room>` so a profile cannot absorb the
  /// whole site.
  final Set<String> allowedJoinPathPrefixes;

  /// The user confirmed this is a trusted internal deployment; only then may
  /// a private/LAN address pass NetGuard (mirrors WebDAV/Matrix).
  final bool trustedInternal;

  /// SHA-256 of a certificate the user explicitly trusts, or empty for the
  /// ordinary chain (desktop only — no pinning on web; mirrors XmppSettings).
  final String pinnedCertSha256;

  /// Whether [invitation] falls inside this profile: same scheme, same host
  /// (case-insensitive), same EFFECTIVE port (an implicit :443 equals the
  /// written one), a non-root path, and — when prefixes are configured — a
  /// path under one of them.
  bool allows(Uri invitation) {
    if (invitation.scheme.toLowerCase() != origin.scheme.toLowerCase()) {
      return false;
    }
    if (invitation.host.toLowerCase() != origin.host.toLowerCase()) {
      return false;
    }
    if (invitation.port != origin.port) return false;
    final path = invitation.path;
    if (path.isEmpty || path == '/') return false;
    if (allowedJoinPathPrefixes.isEmpty) return true;
    for (final raw in allowedJoinPathPrefixes) {
      final prefix = raw.endsWith('/') ? raw : '$raw/';
      // '…/meet' zelf is geen meetinglink; '…/meet/kamer' wel. Segmentveilig:
      // '/meet' claimt niet '/meeting'.
      if (path == raw.substring(0, raw.length - (raw.endsWith('/') ? 1 : 0)) ||
          path.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'providerId': providerId,
    'origin': origin.toString(),
    'allowedJoinPathPrefixes': allowedJoinPathPrefixes.toList()..sort(),
    'trustedInternal': trustedInternal,
    'pinnedCertSha256': pinnedCertSha256,
  };

  /// Parse a stored profile; returns null on anything malformed rather than
  /// half-recognising a trust decision (a broken record is refuse-to-match,
  /// never widen).
  static MeetingProviderProfile? fromJson(Map<String, Object?> json) {
    final origin = Uri.tryParse((json['origin'] as String? ?? '').trim());
    final id = (json['id'] as String? ?? '').trim();
    final providerId = (json['providerId'] as String? ?? '').trim();
    if (id.isEmpty || providerId.isEmpty || origin == null) return null;
    if (!origin.hasScheme || origin.host.isEmpty) return null;
    if (origin.path.isNotEmpty && origin.path != '/') return null;
    if (origin.hasQuery || origin.hasFragment) return null;
    final scheme = origin.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return null;
    final prefixes =
        (json['allowedJoinPathPrefixes'] as List?)
            ?.whereType<String>()
            .where((p) => p.startsWith('/'))
            .toSet() ??
        const <String>{};
    final pin = (json['pinnedCertSha256'] as String? ?? '').trim();
    if (pin.isNotEmpty && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(pin)) {
      return null;
    }
    return MeetingProviderProfile(
      id: id,
      providerId: providerId,
      origin: origin,
      allowedJoinPathPrefixes: prefixes,
      trustedInternal: json['trustedInternal'] == true,
      pinnedCertSha256: pin,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MeetingProviderProfile &&
      other.id == id &&
      other.providerId == providerId &&
      other.origin == origin &&
      other.trustedInternal == trustedInternal &&
      other.pinnedCertSha256 == pinnedCertSha256 &&
      _setEquals(other.allowedJoinPathPrefixes, allowedJoinPathPrefixes);

  @override
  int get hashCode => Object.hash(
    id,
    providerId,
    origin,
    trustedInternal,
    pinnedCertSha256,
    Object.hashAllUnordered(allowedJoinPathPrefixes),
  );
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Preferences-backed store for [MeetingProviderProfile]s — public metadata
/// only (no credentials). The list is small (hand-approved deployments), so a
/// whole-list rewrite per save is honest and atomic enough here.
class MeetingProfilesStore {
  MeetingProfilesStore({this.prefs, String? key}) : _key = key ?? _defaultKey;

  static const _defaultKey = 'meetingProviderProfiles';
  final SharedPreferences? prefs;
  final String _key;

  Future<SharedPreferences> get _prefsOrInstance async =>
      prefs ?? SharedPreferences.getInstance();

  Future<List<MeetingProviderProfile>> load() async {
    final prefs = await _prefsOrInstance;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map)
          ?MeetingProviderProfile.fromJson(e.cast<String, Object?>()),
    ];
  }

  Future<void> save(List<MeetingProviderProfile> profiles) async {
    final prefs = await _prefsOrInstance;
    await prefs.setString(
      _key,
      jsonEncode([for (final p in profiles) p.toJson()]),
    );
  }
}
