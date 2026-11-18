import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bouw een container met een wegwerp-herstelmap zodat de autosave-leidingen
/// van [TabsNotifier] nooit het echte app-support-pad raken — zelfde patroon
/// als bug_1660_1661_document_tab_crash_test.
ProviderContainer _container() {
  final tempDir = Directory.systemTemp.createTempSync('ocideck_bug3000_');
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

/// Regressie voor #3000: vanaf het Nieuw-scherm opende een document een
/// tweede tabblad terwijl een presentatie het Nieuw-tabblad zélf werd.
/// [_placeDeckInTab] hergebruikt een ongeopend deck-tabblad al;
/// [_placeDocumentTab] voegde altijd toe. Nu spiegelen ze elkaar: een
/// ongeopend Nieuw-tabblad wordt in plaats vervangen, een open tabblad nooit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('#3000 — document vanaf het Nieuw-scherm', () {
    test('newDocument vervangt het ongeopende Nieuw-tabblad', () async {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      expect(container.read(tabsProvider).tabs, hasLength(1));

      await tabs.newDocument();

      final state = container.read(tabsProvider);
      expect(
        state.tabs,
        hasLength(1),
        reason: 'het Nieuw-tabblad wordt het documenttabblad',
      );
      expect(state.current?.kind, MarkdownKind.document);
      expect(state.current?.isOpen, isTrue);
      expect(state.selectedIndex, 0);
    });

    test(
      'newDocumentFromMarkdown vervangt het ongeopende Nieuw-tabblad',
      () async {
        final container = _container();
        container
            .read(tabsProvider.notifier)
            .newDocumentFromMarkdown('# Tekst\n', suggestedName: 'Memo');

        final state = container.read(tabsProvider);
        expect(state.tabs, hasLength(1));
        expect(state.current?.kind, MarkdownKind.document);
      },
    );

    test(
      'een open tabblad wordt nooit vervangen: document komt ernaast',
      () async {
        final container = _container();
        final tabs = container.read(tabsProvider.notifier);
        // Open een deck in het eerste tabblad — nu is 'current' open.
        container
            .read(tabsProvider)
            .current!
            .deckNotifier
            .loadDeck(
              Deck(title: 'Deck', slides: [Slide.create(SlideType.title)]),
            );

        await tabs.newDocument();

        final state = container.read(tabsProvider);
        expect(state.tabs, hasLength(2));
        expect(state.current?.kind, MarkdownKind.document);
        expect(state.selectedIndex, 1);
      },
    );

    test(
      'een tweede document vanaf een documenttabblad komt ernaast',
      () async {
        final container = _container();
        final tabs = container.read(tabsProvider.notifier);
        await tabs.newDocument();
        expect(container.read(tabsProvider).tabs, hasLength(1));

        await tabs.newDocument();

        final state = container.read(tabsProvider);
        expect(
          state.tabs,
          hasLength(2),
          reason: 'een open document is geen Nieuw-scherm meer',
        );
        expect(state.current?.kind, MarkdownKind.document);
        expect(state.selectedIndex, 1);
      },
    );
  });
}
