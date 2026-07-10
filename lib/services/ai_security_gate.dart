import 'dart:io';

import '../models/ai_settings.dart';

/// How the transport must resolve and pin the endpoint host for an *allowed*
/// AI request. This is the security-critical distinction between the three
/// tiers: each tier gets a different network regime.
enum AiResolveStrategy {
  /// Local IPC to a loopback endpoint the user configured. The transport pins
  /// directly to the loopback literal — it deliberately does NOT go through
  /// `NetGuard`, which blocks loopback by default. Permitted ONLY because the
  /// gate already verified the host is loopback, so this is not egress.
  loopbackDirect,

  /// A private/LAN host the user marked trusted. The transport resolves via
  /// `NetGuard.safeResolveTrusted(allowPrivate: true)` and pins the socket.
  trustedPrivate,

  /// A public host. The transport resolves via the default `NetGuard.safeResolve`
  /// — which rejects any private/loopback/link-local address, so an SSRF via a
  /// public name that resolves internally is refused. Socket pinned.
  publicGuarded,
}

/// Why the gate refused a request. The UI/tests switch on this; the client
/// turns it into a thrown [AiGateException].
enum AiGateDenial {
  /// The master toggle is off.
  disabled,

  /// A backend is enabled but no tier is chosen (`mode == none`).
  modeNone,

  /// The base URL is empty, unparseable, or not an http(s) URL.
  notConfigured,

  /// `local` mode but the configured host is not a loopback address. Refusing
  /// here is what keeps `local` from being a general egress channel.
  loopbackRequired,

  /// `self-hosted` mode without the "trusted internal server" opt-in.
  privateNotTrusted,

  /// `cloud` mode without the general outbound-privacy consent.
  cloudNeedsConsent,

  /// `cloud` mode without the distinct per-destination confirmation.
  cloudNotConfirmed,

  /// `cloud` mode on the web build (no external connect-src; fail-closed).
  cloudBlockedOnWeb,
}

/// Outcome of [AiSecurityGate.evaluate]: either an allow with the resolve
/// strategy the transport must use, or a typed denial.
sealed class AiGateDecision {
  const AiGateDecision();
}

/// The request may proceed: resolve [uri]'s host with [strategy] and pin.
class AiGateAllow extends AiGateDecision {
  final Uri uri;
  final AiResolveStrategy strategy;
  const AiGateAllow(this.uri, this.strategy);
}

/// The request must not proceed.
class AiGateDeny extends AiGateDecision {
  final AiGateDenial reason;
  const AiGateDeny(this.reason);
}

/// Thrown by the client when the gate denies (so callers get a typed failure).
class AiGateException implements Exception {
  final AiGateDenial reason;
  AiGateException(this.reason);
  @override
  String toString() => 'AiGateException($reason)';
}

/// The single, pure, egress-gating decision for the AI backend. No I/O, no
/// network, no globals — everything it needs is an argument, so it is trivially
/// unit-testable and the same rules apply everywhere a request is built.
///
/// This is the SSRF/egress choke point. It never lets a private/LAN host reach
/// the default `safeResolve` path (that would be an SSRF regression): a private
/// host is only reachable via the explicit `self-hosted` + trusted opt-in, and
/// loopback only via the explicit `local` tier pointed at a loopback literal.
class AiSecurityGate {
  AiSecurityGate._();

  static AiGateDecision evaluate(
    AiSettings settings, {
    required bool hasOutboundConsent,
    required bool cloudConfirmed,
    required bool isWeb,
  }) {
    if (!settings.enabled) return const AiGateDeny(AiGateDenial.disabled);
    if (settings.mode == AiBackendMode.none) {
      return const AiGateDeny(AiGateDenial.modeNone);
    }
    final uri = Uri.tryParse(settings.baseUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return const AiGateDeny(AiGateDenial.notConfigured);
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const AiGateDeny(AiGateDenial.notConfigured);
    }
    if (uri.host.isEmpty) {
      return const AiGateDeny(AiGateDenial.notConfigured);
    }

    switch (settings.mode) {
      case AiBackendMode.local:
        if (!isLoopbackHost(uri.host)) {
          return const AiGateDeny(AiGateDenial.loopbackRequired);
        }
        return AiGateAllow(uri, AiResolveStrategy.loopbackDirect);
      case AiBackendMode.selfHosted:
        if (!settings.trustedInternal) {
          return const AiGateDeny(AiGateDenial.privateNotTrusted);
        }
        return AiGateAllow(uri, AiResolveStrategy.trustedPrivate);
      case AiBackendMode.cloud:
        if (isWeb) return const AiGateDeny(AiGateDenial.cloudBlockedOnWeb);
        if (!hasOutboundConsent) {
          return const AiGateDeny(AiGateDenial.cloudNeedsConsent);
        }
        if (!cloudConfirmed) {
          return const AiGateDeny(AiGateDenial.cloudNotConfirmed);
        }
        return AiGateAllow(uri, AiResolveStrategy.publicGuarded);
      case AiBackendMode.none:
        return const AiGateDeny(AiGateDenial.modeNone);
    }
  }

  /// Whether [host] denotes the loopback interface: `localhost`, `*.localhost`,
  /// or a loopback IP literal (`127.0.0.0/8`, `::1`). Only such a host may be
  /// used with [AiResolveStrategy.loopbackDirect].
  static bool isLoopbackHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost')) return true;
    final addr = InternetAddress.tryParse(host);
    return addr != null && addr.isLoopback;
  }
}
