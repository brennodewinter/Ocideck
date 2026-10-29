import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/ai_status_provider.dart';
import 'package:ocideck/state/secret_store_provider.dart';
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

class _FakeSecretStore extends SecretStore {
  _FakeSecretStore() : super(canStore: false);

  @override
  Future<String?> readAiApiKey(String baseUrl) async => null;
}

class _DelayedSecretStore extends SecretStore {
  _DelayedSecretStore() : super(canStore: false);

  final started = Completer<void>();
  final result = Completer<String?>();

  @override
  Future<String?> readAiApiKey(String baseUrl) {
    if (!started.isCompleted) started.complete();
    return result.future;
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
      secretStoreProvider.overrideWithValue(_FakeSecretStore()),
    ],
  );
  addTearDown(c.dispose);
  final sub = c.listen(aiStatusProvider, (_, _) {});
  addTearDown(sub.close);
  await Future<void>.delayed(Duration.zero);
  return c;
}

/// Wacht op de echte endpoint-uitkomst, ook onder een drukke testsuite.
Future<void> _settle(ProviderContainer c) async {
  final done = Completer<void>();
  final sub = c.listen(aiStatusProvider, (_, status) {
    if (status.availability != AiAvailability.checking && !done.isCompleted) {
      done.complete();
    }
  });
  try {
    if (c.read(aiStatusProvider).availability == AiAvailability.checking) {
      await done.future.timeout(const Duration(seconds: 5));
    }
  } finally {
    sub.close();
  }
}

void main() {
  group('aiStatusProvider', () {
    test('AI uit → verborgen, geen netwerk', () async {
      final transport = _FakeTransport();
      final c = await _container(transport: transport);
      await _settle(c);
      expect(c.read(aiStatusProvider).availability, AiAvailability.hidden);
      expect(transport.calls, 0);
    });

    test('lokale backend die antwoordt → bereikbaar', () async {
      final transport = _FakeTransport();
      final c = await _container(transport: transport);
      await c.read(settingsProvider.notifier).setAiSettings(_local);
      await _settle(c);
      expect(c.read(aiStatusProvider).availability, AiAvailability.reachable);
      expect(transport.calls, 1);
    });

    testWidgets('uitgeschakelde AI stopt periodieke statuscontrole', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final transport = _FakeTransport();
      final c = ProviderContainer(
        overrides: [
          aiHttpTransportProvider.overrideWithValue(transport),
          secretStoreProvider.overrideWithValue(_FakeSecretStore()),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(aiStatusProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.pump();
      await c.read(settingsProvider.notifier).setAiSettings(_local);
      await tester.pump();
      expect(c.read(aiStatusProvider).availability, AiAvailability.checking);
      await tester.pump(kAiStatusRefreshInterval);
      await tester.pump();
      expect(transport.calls, greaterThan(1));

      await c
          .read(settingsProvider.notifier)
          .setAiSettings(const AiSettings(enabled: false));
      await tester.pump();
      expect(c.read(aiStatusProvider).availability, AiAvailability.hidden);
      final callsWhenDisabled = transport.calls;
      await tester.pump(kAiStatusRefreshInterval * 2);
      await tester.pump();
      expect(transport.calls, callsWhenDisabled);
    });

    testWidgets(
      'een instellingswijziging laat de periodieke controle niet dood (#2635)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final transport = _FakeTransport();
        final c = ProviderContainer(
          overrides: [
            aiHttpTransportProvider.overrideWithValue(transport),
            secretStoreProvider.overrideWithValue(_FakeSecretStore()),
          ],
        );
        addTearDown(c.dispose);
        final sub = c.listen(aiStatusProvider, (_, _) {});
        addTearDown(sub.close);
        await tester.pump();

        await c.read(settingsProvider.notifier).setAiSettings(_local);
        await tester.pump();
        // Eerste interval-tik: de periodieke controle loopt (de eerste
        // asynchrone check kan dan nog onderweg zijn).
        await tester.pump(kAiStatusRefreshInterval);
        await tester.pump();
        expect(transport.calls, greaterThanOrEqualTo(1));

        // Herbouw de provider met een gewijzigde instelling — vóór de fix
        // bleef de geannuleerde timer in `_timer` staan en kwam er nooit een
        // nieuwe.
        await c
            .read(settingsProvider.notifier)
            .setAiSettings(_local.copyWith(model: 'ander-model'));
        await tester.pump();
        final callsAfterEdit = transport.calls;

        await tester.pump(kAiStatusRefreshInterval);
        await tester.pump();
        expect(
          transport.calls,
          greaterThan(callsAfterEdit),
          reason: 'het interval loopt ook na de wijziging gewoon door',
        );

        // De levende periodieke timer achterlaten breekt de test-hygiëne.
        await c
            .read(settingsProvider.notifier)
            .setAiSettings(const AiSettings(enabled: false));
        // Riverpod's geplande herbouw draait op eigen 0-seconden-timers die
        // elkaar weer aanmaken; pumpAndSettle spoelt de hele ketting leeg.
        await tester.pumpAndSettle();
      },
    );

    test('endpoint geeft fout → niet bereikbaar', () async {
      final transport = _FakeTransport(error: AiRequestException('network'));
      final c = await _container(transport: transport);
      await c.read(settingsProvider.notifier).setAiSettings(_local);
      await _settle(c);
      expect(c.read(aiStatusProvider).availability, AiAvailability.unreachable);
    });

    test(
      'een opgeruimde provider leest niets na een vertraagde sleutel',
      () async {
        SharedPreferences.setMockInitialValues({});
        final secrets = _DelayedSecretStore();
        final c = ProviderContainer(
          overrides: [secretStoreProvider.overrideWithValue(secrets)],
        );
        final sub = c.listen(aiStatusProvider, (_, _) {});
        await c.read(settingsProvider.notifier).setAiSettings(_local);
        await secrets.started.future;
        sub.close();
        c.dispose();
        secrets.result.complete(null);
        await Future<void>.delayed(Duration.zero);
      },
    );

    test('aan maar niets ingesteld → geweigerd, geen netwerk', () async {
      final transport = _FakeTransport();
      final c = await _container(transport: transport);
      await c
          .read(settingsProvider.notifier)
          .setAiSettings(const AiSettings(enabled: true));
      await _settle(c);
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
      await _settle(c);
      final status = c.read(aiStatusProvider);
      expect(status.availability, AiAvailability.denied);
      expect(status.denial, AiGateDenial.cloudNeedsConsent);
      expect(transport.calls, 0);
    });
  });
}
