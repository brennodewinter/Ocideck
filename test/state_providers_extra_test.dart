import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/image_contrast_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build a container with a throwaway recovery directory so the [TabsNotifier]
/// autosave plumbing never reaches the real app-support path (a platform
/// channel that isn't wired up in a unit test).
ProviderContainer _container() {
  final tempDir = Directory.systemTemp.createTempSync('ocideck_tabs_test_');
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

  // ── tabs_provider ──────────────────────────────────────────────────────────

  group('TabsNotifier', () {
    test('starts with a single empty tab selected', () {
      final container = _container();
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(1));
      expect(state.selectedIndex, 0);
      expect(state.current, isNotNull);
      expect(state.current!.isOpen, isFalse);
      expect(state.anyDirty, isFalse);
    });

    test('newEmptyTab appends a tab and selects it', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);

      tabs.newEmptyTab();

      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.selectedIndex, 1);
      expect(state.current!.isOpen, isFalse);
    });

    test('newDeckInNewTab opens a dirty deck in a fresh selected tab', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);

      tabs.newDeckInNewTab('Mijn deck');

      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.selectedIndex, 1);
      final current = state.current!;
      expect(current.isOpen, isTrue);
      expect(current.isDirty, isTrue);
      expect(current.label, 'Mijn deck');
      expect(state.anyDirty, isTrue);
    });

    test('newDeckInCurrentTab fills the current empty tab in place', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);

      tabs.newDeckInCurrentTab('In huidige');

      final state = container.read(tabsProvider);
      // No new tab is created — the starting tab is reused.
      expect(state.tabs, hasLength(1));
      expect(state.current!.isOpen, isTrue);
      expect(state.current!.label, 'In huidige');
    });

    test('selectTab switches the active index and ignores out-of-range', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      tabs.newEmptyTab();
      tabs.newEmptyTab();
      expect(container.read(tabsProvider).tabs, hasLength(3));

      tabs.selectTab(0);
      expect(container.read(tabsProvider).selectedIndex, 0);

      // Out-of-range selections are guarded and leave the index untouched.
      tabs.selectTab(99);
      expect(container.read(tabsProvider).selectedIndex, 0);
      tabs.selectTab(-1);
      expect(container.read(tabsProvider).selectedIndex, 0);
    });

    test('closeTab removes a tab and re-clamps the selected index', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      tabs.newDeckInNewTab('A'); // index 1
      tabs.newDeckInNewTab('B'); // index 2, selected
      expect(container.read(tabsProvider).tabs, hasLength(3));
      expect(container.read(tabsProvider).selectedIndex, 2);

      tabs.closeTab(2);

      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      // Selection clamps back to the last remaining tab.
      expect(state.selectedIndex, 1);
    });

    test('closing the only tab clears its deck instead of removing it', () {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      tabs.newDeckInCurrentTab('Solo');
      expect(container.read(tabsProvider).current!.isOpen, isTrue);

      tabs.closeTab(0);

      final state = container.read(tabsProvider);
      // The last tab is never removed; it just returns to the welcome state.
      expect(state.tabs, hasLength(1));
      expect(state.current!.isOpen, isFalse);
    });

    test('label falls back to "Nieuw" for an untitled empty tab', () {
      final container = _container();
      expect(container.read(tabsProvider).current!.label, 'Nieuw');
    });
  });

  // ── image_contrast_provider ──────────────────────────────────────────────────

  group('imageContrastIssuesProvider', () {
    test('yields no issues when no deck is open', () async {
      final container = _container();
      final issues = await container.read(imageContrastIssuesProvider.future);
      expect(issues, isEmpty);
    });

    test('yields no issues for a deck without title-image slides', () async {
      final container = _container();
      // A plain title slide (no background image) is not a contrast candidate.
      container
          .read(deckProvider.notifier)
          .loadDeck(
            Deck(
              title: 'Geen beeld',
              slides: <Slide>[
                Slide.create(SlideType.title).copyWith(title: 'Hallo'),
                Slide.create(
                  SlideType.bullets,
                ).copyWith(title: 'Punten', bullets: <String>['een', 'twee']),
              ],
            ),
          );

      final issues = await container.read(imageContrastIssuesProvider.future);
      expect(issues, isEmpty);
    });

    test(
      'flags an unverified issue when a title-image cannot be decoded',
      () async {
        final container = _container();
        // A title slide with text over a background image whose asset cannot be
        // resolved/decoded falls back to the informational "verify visually"
        // issue rather than a confident pass.
        container
            .read(deckProvider.notifier)
            .loadDeck(
              Deck(
                title: 'Met beeld',
                slides: <Slide>[
                  Slide.create(SlideType.title).copyWith(
                    title: 'Op de foto',
                    imagePath: 'images/does-not-exist.png',
                  ),
                ],
              ),
            );

        final issues = await container.read(imageContrastIssuesProvider.future);
        expect(issues, hasLength(1));
        expect(issues.single.slideIndex, 0);
      },
    );
  });
}
