import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/state/improvement_ai_provider.dart';
import 'package:ocideck/state/procesverbetering_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _fresh() async {
  SharedPreferences.setMockInitialValues({});
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(settingsProvider);
  c.read(procesverbeteringProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return c;
}

const _localAi = AiSettings(
  enabled: true,
  mode: AiBackendMode.local,
  baseUrl: 'http://127.0.0.1:11434/v1',
  model: 'gemma3:4b',
);

void main() {
  test('false when everything is off', () async {
    final c = await _fresh();
    expect(c.read(improvementAiAvailableProvider), isFalse);
  });

  test('false when only AI is configured', () async {
    final c = await _fresh();
    await c.read(settingsProvider.notifier).setAiSettings(_localAi);
    expect(c.read(improvementAiAvailableProvider), isFalse);
  });

  test('false when only Procesverbetering is on', () async {
    final c = await _fresh();
    await c.read(procesverbeteringProvider.notifier).setEnabled(true);
    expect(c.read(improvementAiAvailableProvider), isFalse);
  });

  test('true when both modules are on and AI is configured', () async {
    final c = await _fresh();
    await c.read(procesverbeteringProvider.notifier).setEnabled(true);
    await c.read(settingsProvider.notifier).setAiSettings(_localAi);
    expect(c.read(improvementAiAvailableProvider), isTrue);
  });

  test('default client factory builds an AiClientService', () async {
    final c = await _fresh();
    await c.read(settingsProvider.notifier).setAiSettings(_localAi);
    final factory = c.read(improvementAiClientFactoryProvider);
    final client = await factory();
    expect(client, isA<AiClientService>());
    expect(client.settings.model, 'gemma3:4b');
  });
}
