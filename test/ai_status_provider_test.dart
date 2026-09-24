import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/state/ai_status_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nep-transport zoals in ai_backend_test: nooit netwerk, alleen een
/// programmeerbare uitkomst voor `GET /models`.
class _FakeTransport implements AiHttpTransport {
  _FakeTransport({this.error});

  final Object? error;
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
    final e = error;
    if (e != null) throw e;
    return const AiHttpResult(200, '{}');
  }
}

const _local = AiSettings(
  enabled: true,
  mode: AiBackendMode.local,
  baseUrl: 'http://127.0.0.1:11434/v1',
  model: 'testmodel',
);

/// Container met een levende subscription op [aiStatusProvider] — autoDispose
/// zou hem na een kale `read` meteen afbreken, en dan landen de async
/// consent-/status-updates op een disposed ref.
Future<ProviderContainer> _container({_FakeTransport? transport}) async {
  SharedPreferences.setMockInitialValues({});
  final c = ProviderContainer(
    overrides: [
      aiHttpTransportProvider.overrideWithValue(transport ?? _FakeTransport()),
    ],
  );
  addTearDown(c.dispose);
  final sub = c.listen(aiStatusProvider, (_, _) {});
  addTearDown(sub.close);
  await Future<void>.delayed(Duration.zero);
  return c;
}

/// Laat de asynchrone consent-init én de endpoint-ping landen.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  group('aiStatusProvider', () {
    test('AI uit → verborgen, geen netwerk', () async {
      final transport = _FakeTransport();
      final c = await _container(transport: transport);
      await _settle();
      expect(c.read(aiStatusProvider).availability, AiAvailability.hidden);
      expect(transport.calls, 0);
    });

    test('lokale backend die antwoordt → bereikbaar', () async {
      final transport = _FakeTransport();
      final c = await _container(transport: transport);
      await c.read(settingsProvider.notifier).setAiSettings(_local);
      await _settle();
      expect(c.read(aiStatusProvider).availability, AiAvailability.reachable);
      expect(transport.calls, 1);
    });

    test('endpoint geeft fout → niet bereikbaar', () async {
      final transport = _FakeTransport(error: AiRequestException('network'));
      final c = await _container(transport: transport);
      await c.read(settingsProvider.notifier).setAiSettings(_local);
      await _settle();
      expect(c.read(aiStatusProvider).availability, AiAvailability.unreachable);
    });

    test('aan maar niets ingesteld → geweigerd, geen netwerk', () async {
      final transport = _FakeTransport();
      final c = await _container(transport: transport);
      await c
          .read(settingsProvider.notifier)
          .setAiSettings(const AiSettings(enabled: true));
      await _settle();
      expect(c.read(aiStatusProvider).availability, AiAvailability.denied);
      expect(transport.calls, 0);
    });

    test('cloud zonder toestemming → geweigerd vóór het netwerk', () async {
      final transport = _FakeTransport();
      final c = await _container(transport: transport);
      await c
          .read(settingsProvider.notifier)
          .setAiSettings(
            const AiSettings(
              enabled: true,
              mode: AiBackendMode.cloud,
              baseUrl: 'https://api.example.com/v1',
              model: 'm',
            ),
          );
      await _settle();
      final status = c.read(aiStatusProvider);
      expect(status.availability, AiAvailability.denied);
      expect(status.denial, AiGateDenial.cloudNeedsConsent);
      expect(transport.calls, 0);
    });
  });
}
