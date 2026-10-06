import 'package:network_guard/network_guard.dart';

import '../models/ai_settings.dart';

export 'package:network_guard/network_guard.dart'
    show
        AiGateAllow,
        AiGateDecision,
        AiGateDenial,
        AiGateDeny,
        AiGateException,
        AiResolveStrategy;

/// The single, pure, egress-gating decision for the AI backend. No I/O, no
/// network, no globals — everything it needs is an argument, so it is trivially
/// unit-testable and the same rules apply everywhere a request is built.
///
/// This is the SSRF/egress choke point. It never lets a private/LAN host reach
/// the default `safeResolve` path (that would be an SSRF regression): a private
/// host is only reachable via the explicit `self-hosted` + trusted opt-in, and
/// loopback only via the explicit `local` tier pointed at a loopback literal.
///
/// The decision rules themselves live in AppFoundation `network_guard`
/// ([AiEgressGate]); this adapter maps the product [AiSettings] onto the
/// product-neutral [AiEgressPolicy].
final class AiSecurityGate {
  AiSecurityGate._();

  static AiGateDecision evaluate(
    AiSettings settings, {
    required bool hasOutboundConsent,
    required bool cloudConfirmed,
    required bool isWeb,
  }) => AiEgressGate.evaluate(
    AiEgressPolicy(
      enabled: settings.enabled,
      mode: settings.mode,
      endpoint: settings.baseUrl,
      trustedInternal: settings.trustedInternal,
    ),
    hasOutboundConsent: hasOutboundConsent,
    cloudConfirmed: cloudConfirmed,
    isWeb: isWeb,
  );

  /// Whether [host] denotes the loopback interface: `localhost`, `*.localhost`,
  /// or a loopback IP literal (`127.0.0.0/8`, `::1`).
  static bool isLoopbackHost(String host) => AiEgressGate.isLoopbackHost(host);
}
