// De uitgangspoort voor de ASR-serverroute (docs/design/TRANSCRIPTION.md
// §4.3, #2524). Puur en I/O-vrij: beslist óf en hóe een verzoek mag
// vertrekken, nooit wat erin staat.
//
// Dit is — bewust — een eigen poort naast `AiEgressGate` en geen modus van
// de AI-backend. De beslisregels lijken, maar drie punten verschillen:
//  * op web is `cloud` hier juist toegestaan (de browser+CORS is daar de
//    grens; een eigen ASR-server is de bedoelde route wanneer de WASM-
//    engine niet kan);
//  * op web kan `lan` met `http://` nooit werken vanaf een https-pagina
//    (mixed content) — eerlijk weigeren is beter dan een kapotte proef;
//  * de redenen zijn eigen enumwaarden, zodat de UI ze per ASR-route kan
//    benoemen in plaats van een AI-verhaal over te nemen.
//
// De strategie die een toestemming meegeeft komt uit `network_guard`
// (`AiResolveStrategy`) — het transport verzint nooit een eigen route.

import 'package:network_guard/network_guard.dart';

import '../../models/asr_server_profile.dart';
import '../../utils/literal_loopback.dart'
    show isLiteralInternalHost, isLiteralLoopbackHost;

export 'package:network_guard/network_guard.dart' show AiResolveStrategy;

/// Eén van de weinige geldige redenen waarom een serververzoek niet
/// vertrekt. De UI vertaalt ze naar een benoemde herstelstap.
enum AsrGateDenial {
  /// Het serverprofiel staat uit.
  disabled,

  /// Er is geen serverklasse gekozen.
  modeNone,

  /// Endpoint ontbreekt of is geen valide http(s)-URL — inclusief een URL
  /// met ingebedde credentials (`user:pass@`), die zijn hier per
  /// definitie ongeldig (de sleutel hoort in de sleutelbos).
  notConfigured,

  /// `loopback` mag alleen een loopback-literal bereiken.
  loopbackRequired,

  /// `lan` zonder de expliciete interne-opt-in.
  lanNotTrusted,

  /// `cloud` vraagt HTTPS — `http://` naar een externe host is onacceptabel.
  cloudNeedsTls,

  /// Deze specifieke externe bestemming is niet bevestigd.
  cloudNotConfirmed,

  /// Op web vereist een niet-loopback `http://`-endpoint mixed content vanaf
  /// een https-pagina — de browser blokkeert dat gegarandeerd, dus wij
  /// weigeren eerder en eerlijker.
  insecureHttpOnWeb,
}

/// Besluit van de poort.
sealed class AsrGateDecision {
  const AsrGateDecision._();
}

/// Het verzoek mag vertrekken, via de aangegeven resolve-strategie.
final class AsrGateAllow extends AsrGateDecision {
  const AsrGateAllow(this.uri, this.strategy) : super._();

  final Uri uri;
  final AiResolveStrategy strategy;
}

/// Het verzoek mag niet vertrekken.
final class AsrGateDeny extends AsrGateDecision {
  const AsrGateDeny(this.reason) : super._();

  final AsrGateDenial reason;
}

/// De egresspoort voor ASR-serververzoeken.
final class AsrServerGate {
  AsrServerGate._();

  /// Beslist of een verzoek naar `profile.baseUrl` mag vertrekken en hoe.
  static AsrGateDecision evaluate(
    AsrServerProfile profile, {
    bool isWeb = false,
  }) {
    if (!profile.enabled) return const AsrGateDeny(AsrGateDenial.disabled);
    final uri = _parseEndpoint(profile.baseUrl);
    if (profile.mode == AsrServerMode.none) {
      return const AsrGateDeny(AsrGateDenial.modeNone);
    }
    if (uri == null || uri.userInfo.isNotEmpty) {
      return const AsrGateDeny(AsrGateDenial.notConfigured);
    }
    switch (profile.mode) {
      case AsrServerMode.none:
        return const AsrGateDeny(AsrGateDenial.modeNone);
      case AsrServerMode.loopback:
        // `localhost` als naam telt ook — het transport resolveert zelf
        // en weigert elke treffer die geen loopback is.
        if (!AiEgressGate.isLoopbackHost(uri.host)) {
          return const AsrGateDeny(AsrGateDenial.loopbackRequired);
        }
        return AsrGateAllow(uri, AiResolveStrategy.loopbackDirect);
      case AsrServerMode.lan:
        if (!profile.trustedInternal) {
          return const AsrGateDeny(AsrGateDenial.lanNotTrusted);
        }
        if (isWeb && uri.scheme == 'http' && !_isLoopback(uri.host)) {
          return const AsrGateDeny(AsrGateDenial.insecureHttpOnWeb);
        }
        return AsrGateAllow(uri, AiResolveStrategy.trustedPrivate);
      case AsrServerMode.cloud:
        if (uri.scheme != 'https') {
          return const AsrGateDeny(AsrGateDenial.cloudNeedsTls);
        }
        if (isWeb && _isInternalHost(uri.host)) {
          return const AsrGateDeny(AsrGateDenial.insecureHttpOnWeb);
        }
        if (!profile.cloudConfirmed) {
          return const AsrGateDeny(AsrGateDenial.cloudNotConfirmed);
        }
        return AsrGateAllow(uri, AiResolveStrategy.publicGuarded);
    }
  }

  /// Beslist of een *live*-verbinding naar `profile.liveUrl` mag
  /// vertrekken (§4.3, #2525). Dezelfde tiers als [evaluate], maar de
  /// draad is WebSocket: `ws` mag alleen waar `http` mocht, `wss` alleen
  /// waar `https` moest. Extra eis boven de batch-URL: query en fragment
  /// zijn ongeldig — een token in een URL is een token in elke proxy- en
  /// serverlog, en de sleutel hoort in de handshake-header.
  static AsrGateDecision evaluateLive(
    AsrServerProfile profile, {
    bool isWeb = false,
  }) {
    if (!profile.enabled) return const AsrGateDeny(AsrGateDenial.disabled);
    final uri = _parseLiveEndpoint(profile.liveUrl);
    if (profile.mode == AsrServerMode.none) {
      return const AsrGateDeny(AsrGateDenial.modeNone);
    }
    if (uri == null || uri.userInfo.isNotEmpty) {
      return const AsrGateDeny(AsrGateDenial.notConfigured);
    }
    switch (profile.mode) {
      case AsrServerMode.none:
        return const AsrGateDeny(AsrGateDenial.modeNone);
      case AsrServerMode.loopback:
        if (!AiEgressGate.isLoopbackHost(uri.host)) {
          return const AsrGateDeny(AsrGateDenial.loopbackRequired);
        }
        return AsrGateAllow(uri, AiResolveStrategy.loopbackDirect);
      case AsrServerMode.lan:
        if (!profile.trustedInternal) {
          return const AsrGateDeny(AsrGateDenial.lanNotTrusted);
        }
        if (isWeb && uri.scheme == 'ws' && !_isLoopback(uri.host)) {
          return const AsrGateDeny(AsrGateDenial.insecureHttpOnWeb);
        }
        return AsrGateAllow(uri, AiResolveStrategy.trustedPrivate);
      case AsrServerMode.cloud:
        if (uri.scheme != 'wss') {
          return const AsrGateDeny(AsrGateDenial.cloudNeedsTls);
        }
        if (isWeb && _isInternalHost(uri.host)) {
          return const AsrGateDeny(AsrGateDenial.insecureHttpOnWeb);
        }
        if (!profile.cloudConfirmed) {
          return const AsrGateDeny(AsrGateDenial.cloudNotConfirmed);
        }
        return AsrGateAllow(uri, AiResolveStrategy.publicGuarded);
    }
  }

  static bool _isLoopback(String host) => isLiteralLoopbackHost(host);

  /// Op web kan `NetGuard.isBlockedHost` niet draaien (`dart:io`); de browser
  /// is daar de grens. Voor de cloud-modus volstaat de lexicale interne-adres
  /// check — een cloud-server op een privé-literal is per definitie geen cloud.
  static bool _isInternalHost(String host) => isLiteralInternalHost(host);

  /// Syntactische poort: geldige http(s)-URI met een host. `null` betekent:
  /// niet geconfigureerd, geen scherpe melding nodig.
  static Uri? _parseEndpoint(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// De live-variant: alleen `ws`/`wss`, met host, en zonder query of
  /// fragment — zie [evaluateLive] voor waarom die ongeldig zijn.
  static Uri? _parseLiveEndpoint(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'ws' && scheme != 'wss') return null;
    if (uri.host.isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    return uri;
  }
}
