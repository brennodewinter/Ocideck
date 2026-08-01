// The "Realtime samenwerken" module state: off by default, a separate Matrix
// toggle under it, and the reveal gate (on, or an account already configured).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/state/collaboration_provider.dart';
import 'package:ocideck/state/matrix_client_provider.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Fresh container + a couple of microtask turns for the notifier's async
  // _initialize to read prefs — the same shape as procesverbetering_module_test.
  Future<ProviderContainer> vers({MatrixServer? account}) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(
      overrides: [matrixAccountProvider.overrideWithValue(account)],
    );
    addTearDown(c.dispose);
    c.read(collaborationProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('is off by default, with Matrix on under it', () async {
    final c = await vers();
    expect(c.read(collaborationEnabledProvider), isFalse);
    expect(c.read(matrixCollabEnabledProvider), isTrue);
    expect(c.read(matrixCollabActiveProvider), isFalse);
  });

  test('enabling the module makes Matrix active', () async {
    final c = await vers();
    await c.read(collaborationProvider.notifier).setEnabled(true);
    expect(c.read(matrixCollabActiveProvider), isTrue);
    // Turning Matrix off leaves the module on but Matrix inactive.
    await c.read(collaborationProvider.notifier).setMatrixEnabled(false);
    expect(c.read(collaborationEnabledProvider), isTrue);
    expect(c.read(matrixCollabActiveProvider), isFalse);
  });

  test('choices persist across a reload', () async {
    final c = await vers();
    await c.read(collaborationProvider.notifier).setEnabled(true);
    await c.read(collaborationProvider.notifier).setMatrixEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('collaborationModuleEnabled'), isTrue);
    expect(prefs.getBool('matrixCollabEnabled'), isFalse);
  });

  test('the registry contains the collaboration module', () {
    expect(moduleRegistry.map((m) => m.id), contains(ModuleId.collaboration));
  });

  group('reveal gate', () {
    test('hidden when off and no account is configured', () async {
      final c = await vers();
      expect(c.read(collaborationRevealProvider), isFalse);
    });

    test('shown when the module (with Matrix) is on', () async {
      final c = await vers();
      await c.read(collaborationProvider.notifier).setEnabled(true);
      expect(c.read(collaborationRevealProvider), isTrue);
    });

    test('shown when off but an account is already configured', () async {
      final c = await vers(
        account: const MatrixServer(
          homeserverUrl: 'https://hs.example',
          userId: '@u:hs.example',
          deviceId: 'd',
        ),
      );
      expect(c.read(collaborationEnabledProvider), isFalse);
      expect(c.read(collaborationRevealProvider), isTrue);
    });
  });
}
