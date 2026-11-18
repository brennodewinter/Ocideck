@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_request.dart';
import 'package:ocideck/services/ai_security_gate.dart';

class _NoTransport implements AiHttpTransport {
  int calls = 0;

  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    throw StateError('The browser must never reach network AI transport.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in [
    AiBackendMode.local,
    AiBackendMode.selfHosted,
    AiBackendMode.cloud,
  ]) {
    test(
      '$mode refuses stored desktop settings before native IP parsing or transport',
      () async {
        final transport = _NoTransport();
        final client = AiClientService(
          settings: AiSettings(
            enabled: true,
            mode: mode,
            baseUrl: mode == AiBackendMode.cloud
                ? 'https://example.invalid/v1'
                : 'http://127.0.0.1:11434/v1',
            model: 'fixture',
            trustedInternal: true,
            cloudConfirmed: true,
          ),
          hasOutboundConsent: true,
          transport: transport,
        );
        final decision = client.gate() as AiGateDeny;
        expect(decision.reason, AiGateDenial.cloudBlockedOnWeb);
        await expectLater(
          client.chat(const AiChatRequest(model: 'fixture', messages: [])),
          throwsA(isA<AiGateException>()),
        );
        await expectLater(
          client.testConnection(),
          throwsA(isA<AiGateException>()),
        );
        expect(transport.calls, 0);
      },
    );
  }

  test('disabled and unconfigured states keep their existing decisions', () {
    for (final settings in [
      const AiSettings(),
      const AiSettings(enabled: true),
    ]) {
      final decision =
          AiSecurityGate.evaluate(
                settings,
                hasOutboundConsent: false,
                cloudConfirmed: false,
                isWeb: true,
              )
              as AiGateDeny;
      expect(
        decision.reason,
        settings.enabled ? AiGateDenial.modeNone : AiGateDenial.disabled,
      );
    }
  });
}
