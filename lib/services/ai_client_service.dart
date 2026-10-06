import 'dart:async';
import 'dart:convert';

import 'package:network_guard/network_guard.dart';

import '../models/ai_settings.dart';
import '../platform/platform_features.dart';
import 'ai_request.dart';
import 'ai_security_gate.dart';

export 'package:network_guard/network_guard.dart'
    show
        AiHttpResult,
        AiHttpTransport,
        AiRequestException,
        PinnedAiHttpTransport;

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
