import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bouw een container met een wegwerp-herstelmap zodat de autosave-leidingen
/// van [TabsNotifier] nooit het echte app-support-pad raken.
ProviderContainer _container() {
  final tempDir = Directory.systemTemp.createTempSync('ocideck_bug1660_');
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
  final container = ProviderContainer(
    overrides: [
      recoveryServiceProvider.overrideWithValue(
        RecoveryService(baseDir: tempDir),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('#1661 — Duplicaten opruimen met documenttabblad', () {
    test('_openPaths-pattern: openFilePath gooit niet op documenttabblad', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      tabs.newDocument();

      final state = container.read(tabsProvider);
      // Het patroon dat _openPaths gebruikt: itereren over alle tabs en
      // openFilePath uitlezen. Voor de fix gooide deckNotifier hier een
      // StateError.
      for (final tab in state.tabs) {
        expect(() => tab.openFilePath, returnsNormally);
      }
      // Het documenttabblad heeft geen pad (nieuw document) → null.
      final docTab = state.tabs.last;
      expect(docTab.openFilePath, isNull);
    });
  });

  group('#1660 — Afbeelding slepen op documenttabblad', () {
    test('deckNotifierOrNull is null voor documenttabblad (geen crash)', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      tabs.newDocument();

      final state = container.read(tabsProvider);
      final docTab = state.tabs.last;
      // _adoptDroppedImage en _addImagesToActiveDeck lezen nu
      // deckNotifierOrNull in plaats van deckNotifier.
      expect(docTab.deckNotifierOrNull, isNull);
      // deckNotifier zelf gooit nog steeds — dat is bewust.
      expect(() => docTab.deckNotifier, throwsStateError);
    });
  });
}
