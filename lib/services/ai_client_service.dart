import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/ai_settings.dart';
import '../platform/platform_features.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';
import 'ai_request.dart';
import 'ai_security_gate.dart';

/// One HTTP exchange result across the transport seam.
class AiHttpResult {
  final int statusCode;
  final String body;
  const AiHttpResult(this.statusCode, this.body);
}

/// Injectable network seam. Tests provide a fake so no test touches the
/// network; the default implementation ([PinnedAiHttpTransport]) resolves and
/// pins the socket according to the gate's [AiResolveStrategy].
abstract class AiHttpTransport {
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers,
    String? body,
    Duration timeout,
  });
}

/// A network or protocol failure talking to the backend (distinct from a
/// [AiGateException], which is a refusal to even send).
class AiRequestException implements Exception {
  final String message;
  AiRequestException(this.message);
  @override
  String toString() => 'AiRequestException: $message';
}

/// The default transport: resolves the endpoint host per [AiResolveStrategy],
/// pins the socket to the validated address (so a DNS rebind between check and
/// connect can't move it internally), refuses redirects, and caps the response.
/// This is the ONLY place in the AI backend that opens a raw `HttpClient`; it
/// is listed in `network_sink_guard_test.dart`.
class PinnedAiHttpTransport implements AiHttpTransport {
  const PinnedAiHttpTransport();

  /// Cap on the response body a hostile/misconfigured endpoint may return.
  static const int maxResponseBytes = 8 * 1024 * 1024;

  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final pinned = await _resolvePinned(url.host, strategy);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (u, proxyHost, proxyPort) =>
          NetGuard.connectPinned(pinned, u);
    try {
      final request = await client.openUrl(method, url);
      request.followRedirects = false; // a 3xx must not bypass the host check
      headers.forEach(request.headers.set);
      if (body != null) request.add(utf8.encode(body));
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) {
          throw AiRequestException('response too large');
        }
      }
      return AiHttpResult(
        response.statusCode,
        utf8.decode(builder.takeBytes(), allowMalformed: true),
      );
    } on AiRequestException {
      rethrow;
    } on TimeoutException {
      throw AiRequestException('timeout');
    } catch (e) {
      // Host omitted from the log: it is user-configured but may be sensitive.
      logError('PinnedAiHttpTransport.send: request failed', e);
      throw AiRequestException('network');
    } finally {
      client.close(force: true);
    }
  }

  /// Resolve [host] to the single address the socket is pinned to, applying the
  /// tier's network regime. Throws [AiRequestException] when refused.
  Future<InternetAddress> _resolvePinned(
    String host,
    AiResolveStrategy strategy,
  ) async {
    switch (strategy) {
      case AiResolveStrategy.loopbackDirect:
        // Local IPC: the gate already verified the host is loopback, so pin
        // straight to the literal (NetGuard would otherwise block loopback).
        final addr =
            InternetAddress.tryParse(host) ?? InternetAddress.loopbackIPv4;
        if (!addr.isLoopback) {
          throw AiRequestException('local endpoint not loopback');
        }
        return addr;
      case AiResolveStrategy.trustedPrivate:
        final addrs = await NetGuard.safeResolveTrusted(
          host,
          allowPrivate: true,
        );
        if (addrs == null || addrs.isEmpty) {
          throw AiRequestException('host refused or unreachable');
        }
        return addrs.first;
      case AiResolveStrategy.publicGuarded:
        final addrs = await NetGuard.safeResolve(host);
        if (addrs == null || addrs.isEmpty) {
          throw AiRequestException('host refused or unreachable');
        }
        return addrs.first;
    }
  }
}

/// The shared AI client. Given [settings], the consent facts, and an optional
/// API key, it gates every request through [AiSecurityGate] and only then hands
/// it to the (injectable) transport. Consumers call [suggest]; the settings UI
/// calls [testConnection].
class AiClientService {
  AiClientService({
    required this.settings,
    required this.hasOutboundConsent,
    this.apiKey,
    AiHttpTransport? transport,
    bool? isWeb,
  }) : _transport = transport ?? const PinnedAiHttpTransport(),
       _isWeb = isWeb ?? isWebPlatform;

  final AiSettings settings;
  final bool hasOutboundConsent;
  final String? apiKey;
  final AiHttpTransport _transport;
  final bool _isWeb;

  /// The gate decision for the current settings/consent — exposed so the UI can
  /// explain why a test is unavailable without sending anything.
  AiGateDecision gate() => AiSecurityGate.evaluate(
    settings,
    hasOutboundConsent: hasOutboundConsent,
    cloudConfirmed: settings.cloudConfirmed,
    isWeb: _isWeb,
  );

  /// POST a chat completion. Throws [AiGateException] when the gate refuses
  /// (never touching the network) or [AiRequestException] on a transport error.
  Future<AiChatResponse> chat(AiChatRequest request) async {
    final allow = _allowOrThrow();
    final result = await _transport.send(
      method: 'POST',
      url: _endpoint(allow.uri, 'chat/completions'),
      strategy: allow.strategy,
      headers: _headers(),
      body: jsonEncode(request.toJson()),
    );
    if (result.statusCode != 200) {
      throw AiRequestException('HTTP ${result.statusCode}');
    }
    final decoded = jsonDecode(result.body);
    if (decoded is! Map) throw AiRequestException('unexpected response');
    return AiChatResponse.fromJson(Map<String, Object?>.from(decoded));
  }

  /// Grounded, per-field suggestion scaffolding (AI_ASSIST §4). A consumer
  /// passes its own [context] (its user's facts) and a per-field [instruction];
  /// this frames both with the shared guardrails at low temperature and returns
  /// the draft text (possibly empty — meaning "no suggestion").
  Future<String> suggest({
    required String context,
    required String instruction,
    int maxTokens = 400,
  }) async {
    final request = AiChatRequest(
      model: settings.model,
      maxTokens: maxTokens,
      messages: [
        AiMessage.text(AiRole.system, AiPrompts.systemGuardrail),
        AiMessage.text(
          AiRole.user,
          '${AiPrompts.groundedContext(context)}\n\n$instruction\n\n'
          '${AiPrompts.blankIfUnknown}',
        ),
      ],
    );
    return (await chat(request)).text;
  }

  /// Lightweight connection test: GET `<base>/models`. Exercises the full
  /// gate + resolve + pin path without generating tokens.
  Future<void> testConnection() async {
    final allow = _allowOrThrow();
    final result = await _transport.send(
      method: 'GET',
      url: _endpoint(allow.uri, 'models'),
      strategy: allow.strategy,
      headers: _headers(),
      timeout: const Duration(seconds: 20),
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw AiRequestException('HTTP ${result.statusCode}');
    }
  }

  AiGateAllow _allowOrThrow() {
    final decision = gate();
    if (decision is AiGateDeny) throw AiGateException(decision.reason);
    return decision as AiGateAllow;
  }

  Map<String, String> _headers() {
    final key = apiKey?.trim() ?? '';
    return {
      'content-type': 'application/json',
      if (key.isNotEmpty) 'authorization': 'Bearer $key',
    };
  }

  /// Join [path] onto the configured base (which normally already ends in
  /// `/v1`), collapsing any trailing slash so `…/v1` + `chat/completions`
  /// becomes `…/v1/chat/completions`.
  Uri _endpoint(Uri base, String path) {
    final trimmed = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$trimmed/$path');
  }
}
