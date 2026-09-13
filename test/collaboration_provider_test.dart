// The "Realtime samenwerken" module state: off by default, and the reveal
// gate (on when the module is enabled).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/collaboration_provider.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Fresh container + a couple of microtask turns for the notifier's async
  // _initialize to read prefs — the same shape as procesverbetering_module_test.
  Future<ProviderContainer> vers() async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(collaborationProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('is off by default', () async {
    final c = await vers();
    expect(c.read(collaborationEnabledProvider), isFalse);
  });

  test('enabling the module makes it active', () async {
    final c = await vers();
    await c.read(collaborationProvider.notifier).setEnabled(true);
    expect(c.read(collaborationEnabledProvider), isTrue);
  });

  test('choices persist across a reload', () async {
    final c = await vers();
    await c.read(collaborationProvider.notifier).setEnabled(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('collaborationModuleEnabled'), isTrue);
  });

  test('the registry contains the collaboration module', () {
    expect(moduleRegistry.map((m) => m.id), contains(ModuleId.collaboration));
  });

  group('reveal gate', () {
    test('hidden when off', () async {
      final c = await vers();
      expect(c.read(collaborationRevealProvider), isFalse);
    });

    test('shown when the module is on', () async {
      final c = await vers();
      await c.read(collaborationProvider.notifier).setEnabled(true);
      expect(c.read(collaborationRevealProvider), isTrue);
    });
  });
}
