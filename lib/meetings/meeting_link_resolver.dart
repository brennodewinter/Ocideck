// Meeting-link recognition and normalization (`docs/design/COLLABORATION.md`
// §7.1.6). PURE: parsing, normalizing and provider lookup happen fully local —
// recognition performs ZERO network I/O. The three hard rules from the design:
//
//   1. No probing of a URL or `.well-known` — recognition never touches the
//      network, DNS, or the filesystem.
//   2. No blanket claim — not every HTTPS URL is a meeting; only a provider's
//      trusted hosts or a user-approved [MeetingProviderProfile] recognize.
//   3. No shape-based auto-decision — a link that merely LOOKS like a meeting
//      produces [MeetingLinkVerdict.unrecognized] + [looksLikeMeeting], a hint
//      the UI may use to ask the provider question. A hint changes the
//      QUESTION, never the answer.
//
// Normalization is the security boundary every meeting link passes:
//   * scheme allowlist (http/https) — `javascript:`, `intent:` and friends are
//     refused outright;
//   * embedded URL credentials are refused (a link carrying a password in the
//     authority is a red flag, not an invitation);
//   * the FRAGMENT is dropped wholesale — Jitsi links carry `#config.*`
//     overrides there, which is exactly how an invitation sender would pick
//     YOUR mic/camera defaults. OciDeck owns join defaults, not the sender;
//   * credential-shaped and tracking query parameters are stripped before the
//     link may reach a document, log or adapter ([carriedCredential] reports
//     whether a credential was dropped, for honest UI messaging);
//   * host lowercased, trailing slashes removed — casing/spelling differences
//     must not bypass (or double) recognition.
//
// What this layer does NOT do: choose defaults, start media, or open a join.
// It answers one question — "does any registered provider claim this link?".

import 'meeting_provider.dart';
import 'meeting_provider_profile.dart';

/// Why a link was refused during normalization.
enum MeetingLinkInvalidReason {
  /// Not parseable as an http(s) URL with a host.
  notAUrl,

  /// A scheme outside http/https (`javascript:`, `intent:`, `file:`, …).
  unsupportedScheme,

  /// `user:pass@host` — credentials embedded in the authority.
  containsCredentials,
}

enum MeetingLinkVerdict { invalid, unrecognized, recognized }

/// The outcome of [MeetingLinkResolver.resolve].
class MeetingLinkResolution {
  const MeetingLinkResolution._({
    required this.verdict,
    this.normalized,
    this.match,
    this.viaProfile,
    this.invalidReason,
    this.looksLikeMeeting = false,
    this.carriedCredential = false,
  });

  final MeetingLinkVerdict verdict;

  /// The cleaned link — fragment and credential/tracking params removed.
  /// Null when [verdict] is [MeetingLinkVerdict.invalid].
  final Uri? normalized;

  /// Set when [verdict] is [MeetingLinkVerdict.recognized].
  final MeetingLinkMatch? match;

  /// Set when the match came from a user-approved profile rather than a
  /// provider's built-in trusted hosts — the UI may surface "via your
  /// approved deployment" so the two trust levels stay distinguishable.
  final MeetingProviderProfile? viaProfile;

  final MeetingLinkInvalidReason? invalidReason;

  /// Hint for unrecognized links: the URL shape COULD be a meeting
  /// (http(s) with a non-root path). May steer which question the UI asks —
  /// per §7.1.6 it never selects an adapter by itself.
  final bool looksLikeMeeting;

  /// A credential-shaped parameter (jwt/token/…) was stripped from the link.
  /// The UI should tell the user: the credential is NOT stored or forwarded.
  final bool carriedCredential;
}

/// Recognizes meeting links locally. Constructed with the registered
/// providers plus the user's approved profiles; both lists may change between
/// resolves (profiles arrive from the store asynchronously).
class MeetingLinkResolver {
  const MeetingLinkResolver({
    required this.providers,
    this.profiles = const <MeetingProviderProfile>[],
  });

  final List<MeetingProvider> providers;
  final List<MeetingProviderProfile> profiles;

  /// Credential-shaped parameters dropped during normalization — carrying
  /// these into storage, logs or an adapter would leak the invitation's
  /// secret. (`?jwt=` is how Jitsi links smuggle a token.)
  static const _credentialParams = {
    'jwt',
    'token',
    'access_token',
    'id_token',
    'refresh_token',
    'password',
    'passwd',
    'pwd',
    'secret',
    'auth',
    'sig',
    'signature',
  };

  /// Tracking parameters dropped during normalization — a meeting link is a
  /// destination, not a marketing channel.
  static const _trackingParams = {
    'fbclid',
    'gclid',
    'dclid',
    'yclid',
    'msclkid',
    'mc_cid',
    'mc_eid',
    'igshid',
    'si',
    'spm',
    'scm',
    '_hsenc',
    '_hsmi',
    'ref',
    'ref_src',
    'source',
  };

  static bool _shouldDrop(String name) {
    final n = name.toLowerCase();
    return _credentialParams.contains(n) ||
        _trackingParams.contains(n) ||
        n.startsWith('utm_');
  }

  /// Resolve [raw] (a pasted link, document target, or deep link) into a
  /// verdict. Pure: no network, no async.
  MeetingLinkResolution resolve(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const MeetingLinkResolution._(
        verdict: MeetingLinkVerdict.invalid,
        invalidReason: MeetingLinkInvalidReason.notAUrl,
      );
    }

    var uri = Uri.tryParse(text);
    // A pasted 'meet.jit.si/room' has no scheme; assume https (the meeting
    // world is https-first, and 'http://host' written down keeps its scheme).
    if (uri == null || (!uri.hasScheme && uri.host.isEmpty)) {
      uri = Uri.tryParse('https://$text');
      if (uri == null || uri.host.isEmpty) {
        return const MeetingLinkResolution._(
          verdict: MeetingLinkVerdict.invalid,
          invalidReason: MeetingLinkInvalidReason.notAUrl,
        );
      }
    }
    // Eerst de scheme: `javascript:alert(1)` heeft géén host — als de
    // host-check voor zou gaan viel hij onder 'notAUrl' en gingen we het
    // gevaarlijke deel (een verboden scheme) mistten.
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      return const MeetingLinkResolution._(
        verdict: MeetingLinkVerdict.invalid,
        invalidReason: MeetingLinkInvalidReason.unsupportedScheme,
      );
    }
    if (uri.host.isEmpty) {
      return const MeetingLinkResolution._(
        verdict: MeetingLinkVerdict.invalid,
        invalidReason: MeetingLinkInvalidReason.notAUrl,
      );
    }
    if (uri.userInfo.isNotEmpty) {
      return const MeetingLinkResolution._(
        verdict: MeetingLinkVerdict.invalid,
        invalidReason: MeetingLinkInvalidReason.containsCredentials,
        carriedCredential: true,
      );
    }

    // Strip fragment (Jitsi #config.* overrides), credential/tracking params,
    // and trailing slashes. The host is lowercased so casing cannot bypass
    // recognition.
    var carriedCredential = false;
    final keptParams = <String, List<String>>{};
    uri.queryParametersAll.forEach((key, values) {
      if (_shouldDrop(key)) {
        if (_credentialParams.contains(key.toLowerCase())) {
          carriedCredential = true;
        }
        return;
      }
      keptParams[key] = values;
    });
    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final normalized = Uri(
      scheme: scheme,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: path.isEmpty ? null : path,
      queryParameters: keptParams.isEmpty ? null : keptParams,
    );

    // 1) A provider's own trusted hosts (suffix-safe matching is the
    //    provider's job inside match()).
    for (final provider in providers) {
      final match = provider.match(normalized);
      if (match != null) {
        return MeetingLinkResolution._(
          verdict: MeetingLinkVerdict.recognized,
          normalized: normalized,
          match: match,
          carriedCredential: carriedCredential,
        );
      }
    }

    // 2) A user-approved profile — but only when a registered provider owns
    //    profile.providerId: a profile for an uninstalled provider must not
    //    fabricate a match.
    for (final profile in profiles) {
      if (!providers.any((p) => p.id == profile.providerId)) continue;
      if (!profile.allows(normalized)) continue;
      return MeetingLinkResolution._(
        verdict: MeetingLinkVerdict.recognized,
        normalized: normalized,
        match: MeetingLinkMatch(
          providerId: profile.providerId,
          invitation: normalized,
          viaProfile: profile,
        ),
        viaProfile: profile,
        carriedCredential: carriedCredential,
      );
    }

    return MeetingLinkResolution._(
      verdict: MeetingLinkVerdict.unrecognized,
      normalized: normalized,
      looksLikeMeeting: normalized.path.isNotEmpty && normalized.path != '/',
      carriedCredential: carriedCredential,
    );
  }
}
