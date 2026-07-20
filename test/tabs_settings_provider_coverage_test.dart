import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Coverage for the two open-tab / settings state notifiers. The tab side
/// exercises the tab-management surface (open/switch/close/restore) that is not
/// reached by the import- and webdav-focused tests; the settings side fills the
/// gaps around webdav/AI secrets, the cockpit colour schemes, CVE lookup and the
/// remaining selectors, using an injected in-memory [SecretStore] so nothing
/// touches the real keychain.

/// An in-memory [SecretStore] so the notifier's keychain round-trips can be
/// asserted without a real secure-storage backend.
class _MemorySecretStore extends SecretStore {
  final Map<String, String> _store = {};

  @override
  Future<void> writeWebdavPassword(String b, String u, String p) async {
    _store[SecretStore.webdavKey(b, u)] = p;
  }

  @override
  Future<String?> readWebdavPassword(String b, String u) async =>
      _store[SecretStore.webdavKey(b, u)];

  @override
  Future<void> deleteWebdavPassword(String b, String u) async {
    _store.remove(SecretStore.webdavKey(b, u));
  }

  @override
  Future<void> writeAiApiKey(String b, String k) async {
    _store[SecretStore.aiApiKeyKey(b)] = k;
  }

  @override
  Future<String?> readAiApiKey(String b) async =>
      _store[SecretStore.aiApiKeyKey(b)];

  @override
  Future<void> deleteAiApiKey(String b) async {
    _store.remove(SecretStore.aiApiKeyKey(b));
  }
}

const _validDeck = '''
---
marp: true
theme: ocideck
---

# Eerste slide

---

## Tweede slide

- punt één
- punt twee
''';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// Een parser die omvalt — zoals `parseDeck` in de praktijk kan doen, en waarom
/// hij zijn eigen fouten afvangt.
class _FailingMarkdown extends MarkdownService {
  @override
  Deck? parseDeck(String markdown, {String? filePath}) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── TabsNotifier ────────────────────────────────────────────────────────────

  group('TabsNotifier', () {
    (ProviderContainer, TabsNotifier) build({
      RecoveryService? recovery,
      MarkdownService? md,
    }) {
      final container = ProviderContainer(
        overrides: [
          // No real recovery folder in tests (path_provider is unavailable on
          // the VM); a temp base dir keeps the notifier from reaching the disk.
          recoveryServiceProvider.overrideWithValue(
            recovery ?? RecoveryService(baseDir: Directory.systemTemp),
          ),
          if (md != null) markdownServiceProvider.overrideWithValue(md),
        ],
      );
      addTearDown(container.dispose);
      return (container, container.read(tabsProvider.notifier));
    }

    test('starts with a single empty tab selected', () {
      final (container, _) = build();
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(1));
      expect(state.selectedIndex, 0);
      expect(state.current, isNotNull);
      expect(state.current!.isOpen, isFalse);
      expect(state.anyDirty, isFalse);
    });

    test('newEmptyTab appends a tab and selects it', () {
      final (container, tabs) = build();
      tabs.newEmptyTab();
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.selectedIndex, 1);
      expect(state.current!.isOpen, isFalse);
    });

    test('newDeckInNewTab opens a titled deck in a fresh selected tab', () {
      final (container, tabs) = build();
      tabs.newDeckInNewTab('Titel');
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.selectedIndex, 1);
      expect(state.current!.isOpen, isTrue);
      expect(state.current!.deckNotifier.currentState.deck!.title, 'Titel');
      expect(
        state.current!.deckNotifier.currentState.deck!.slides,
        hasLength(1),
      );
    });

    test('newDeckInNewTab with a template opens its example slides', () {
      final (container, tabs) = build();
      tabs.newDeckInNewTab('Briefing', template: deckTemplateById('briefing'));
      final deck = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      expect(deck.slides, hasLength(6));
      expect(deck.slides.first.type, SlideType.title);
    });

    test('newDeckInCurrentTab replaces the empty starter tab in place', () {
      final (container, tabs) = build();
      tabs.newDeckInCurrentTab('In situ');
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(1), reason: 'no extra tab is opened');
      expect(state.current!.isOpen, isTrue);
      expect(state.current!.deckNotifier.currentState.deck!.title, 'In situ');
    });

    test('selectTab moves the selection and ignores out-of-range indices', () {
      final (container, tabs) = build();
      tabs.newEmptyTab();
      tabs.newEmptyTab(); // three tabs now, selected at index 2

      tabs.selectTab(0);
      expect(container.read(tabsProvider).selectedIndex, 0);

      tabs.selectTab(99); // beyond the end → no-op
      expect(container.read(tabsProvider).selectedIndex, 0);

      tabs.selectTab(-1); // below zero → no-op
      expect(container.read(tabsProvider).selectedIndex, 0);
    });

    test('closeTab on the only tab clears its deck, keeps the welcome tab', () {
      final (container, tabs) = build();
      tabs.newDeckInCurrentTab('Alleen');
      expect(container.read(tabsProvider).current!.isOpen, isTrue);

      tabs.closeTab(0);
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(1), reason: 'last tab is never removed');
      expect(state.current!.isOpen, isFalse, reason: 'the deck is cleared');
    });

    test('closing the active last tab reselects the previous one', () {
      final (container, tabs) = build();
      tabs.newDeckInCurrentTab('A');
      tabs.newDeckInNewTab('B');
      tabs.newDeckInNewTab('C'); // [A, B, C], active index 2

      tabs.closeTab(2);
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.selectedIndex, 1);
      expect(state.current!.deckNotifier.currentState.deck!.title, 'B');
    });

    test('closing a leading tab shifts the list and clamps the selection', () {
      final (container, tabs) = build();
      tabs.newDeckInCurrentTab('A');
      tabs.newDeckInNewTab('B');
      tabs.newDeckInNewTab('C');

      tabs.closeTab(0);
      final state = container.read(tabsProvider);
      expect(state.tabs, hasLength(2));
      expect(state.tabs[0].label, 'B');
      expect(state.tabs[1].label, 'C');
    });

    test(
      'restoreRecovered replaces the empty starter with recovered decks',
      () {
        final (container, tabs) = build();
        tabs.restoreRecovered([
          RecoverySnapshot(
            id: 'snap-1',
            savedAt: DateTime.now(),
            filePath: null,
            label: 'Hersteld',
            markdown: _validDeck,
          ),
        ]);
        final state = container.read(tabsProvider);
        expect(
          state.tabs,
          hasLength(1),
          reason: 'starter is reused, not appended',
        );
        expect(state.selectedIndex, 0);
        expect(state.current!.isOpen, isTrue);
        // Recovered content is unsaved, so the restored tab is marked dirty.
        expect(state.current!.isDirty, isTrue);
      },
    );

    test('een onleesbare momentopname wordt niet weggegooid', () async {
      // `parseDeck` vangt zijn eigen fouten af juist omdát hij struikelt, en een
      // crash ín de parser is een waarschijnlijke reden dat dit bestand er
      // überhaupt ligt. Eerst wissen en dan pas kijken of het lukte, betekende
      // dat één klik op "Herstellen" het enige exemplaar opruimde.
      final dir = Directory.systemTemp.createTempSync('ocideck_restore_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final recovery = RecoveryService(baseDir: dir);
      final kapot = RecoverySnapshot(
        id: 'stuk',
        savedAt: DateTime.now(),
        filePath: null,
        label: 'Stuk',
        markdown: _validDeck,
      );
      await recovery.save(kapot);

      // De parser struikelt: precies het geval waarvoor `parseDeck` zijn eigen
      // fouten afvangt, en een van de waarschijnlijkere redenen dat er
      // überhaupt een herstelbestand ligt.
      final (_, tabs) = build(recovery: recovery, md: _FailingMarkdown());
      final unreadable = tabs.restoreRecovered([kapot]);

      expect(unreadable, 1);
      expect(
        (await recovery.loadAll()).map((s) => s.id),
        contains('stuk'),
        reason: 'het enige exemplaar mag niet gewist zijn',
      );
    });

    test('een hersteld tabblad neemt de sleutel van de momentopname over', () {
      // Anders staat er tot de volgende autosave-tik niets op schijf — en juist
      // in die seconden crasht een app die zojuist dezelfde inhoud opende.
      final (container, tabs) = build();
      tabs.restoreRecovered([
        RecoverySnapshot(
          id: 'snap-hergebruik',
          savedAt: DateTime.now(),
          filePath: null,
          label: 'Hersteld',
          markdown: _validDeck,
        ),
      ]);
      expect(
        container.read(tabsProvider).current!.recoveryId,
        'snap-hergebruik',
      );
    });

    test(
      'restoreRecovered appends when the current tab already has a deck',
      () {
        final (container, tabs) = build();
        tabs.newDeckInCurrentTab('Bezig'); // starter is now open

        tabs.restoreRecovered([
          RecoverySnapshot(
            id: 'snap-2',
            savedAt: DateTime.now(),
            filePath: null,
            label: 'Hersteld',
            markdown: _validDeck,
          ),
        ]);
        final state = container.read(tabsProvider);
        expect(state.tabs, hasLength(2));
        expect(state.selectedIndex, 1);
        expect(state.current!.isOpen, isTrue);
      },
    );

    test('restoreRecovered with no valid snapshots leaves the state alone', () {
      final (container, tabs) = build();
      tabs.restoreRecovered(const []);
      expect(container.read(tabsProvider).tabs, hasLength(1));
    });

    test(
      'openDeckFromBytes opens a second tab beside an already-open one',
      () async {
        final (container, tabs) = build();
        tabs.newDeckInCurrentTab('Eerste'); // starter is open

        final result = await tabs.openDeckFromBytes(
          _bytes(_validDeck),
          'tweede.md',
        );
        expect(result, OpenResult.opened);

        final state = container.read(tabsProvider);
        expect(state.tabs, hasLength(2));
        expect(state.selectedIndex, 1);
        // In-memory bytes carry no path: saving becomes a download.
        expect(state.current!.deckNotifier.currentState.filePath, isNull);
        expect(
          state.current!.deckNotifier.currentState.deck!.slides,
          hasLength(2),
        );
      },
    );

    test(
      'opening a deck with security slides raises the module prompt',
      () async {
        final (container, tabs) = build();

        // A plain deck never raises the prompt.
        await tabs.openDeckFromBytes(_bytes(_validDeck), 'gewoon.md');
        expect(container.read(securityModulePromptProvider), isNull);

        // Build a deck carrying an Informatieveiligheid slide and re-open it.
        final dn = DeckNotifier(
          container.read(markdownServiceProvider),
          container.read(fileServiceProvider),
        );
        dn.newDeck('Sec');
        dn.addSlide(SlideType.finding);
        final secMarkdown = dn.generateMarkdown();
        dn.dispose();

        final result = await tabs.openDeckFromBytes(
          _bytes(secMarkdown),
          'sec.md',
        );
        expect(result, OpenResult.opened);
        expect(
          container
              .read(tabsProvider)
              .current!
              .deckNotifier
              .currentState
              .deck!
              .hasSecuritySlides,
          isTrue,
          reason: 'the finding slide round-trips as a security slide',
        );
        final prompt = container.read(securityModulePromptProvider);
        expect(prompt, isNotNull);
        // De melding hangt aan het tabblad waarin dit deck landde; daarop leunt
        // het opruimen zodra dat tabblad niet meer vóór staat.
        expect(prompt!.tabId, container.read(tabsProvider).current!.id);
      },
    );
  });

  // ── TabsState (pure) ────────────────────────────────────────────────────────

  group('TabsState', () {
    test('current is null and clampedIndex is zero when there are no tabs', () {
      const state = TabsState(tabs: [], selectedIndex: 5);
      expect(state.current, isNull);
      expect(state.clampedIndex, 0);
      expect(state.anyDirty, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      const state = TabsState(tabs: [], selectedIndex: 2);
      final copy = state.copyWith(selectedIndex: 7);
      expect(copy.selectedIndex, 7);
      expect(copy.tabs, isEmpty);
      // Omitting a field keeps the original value.
      expect(state.copyWith().selectedIndex, 2);
    });
  });

  // ── SettingsNotifier ────────────────────────────────────────────────────────

  group('SettingsNotifier', () {
    Future<SettingsNotifier> loaded({SecretStore? store}) async {
      final n = SettingsNotifier(secretStore: store);
      // The constructor kicks off an async load; let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return n;
    }

    test('exposes the documented defaults on a fresh install', () async {
      final n = await loaded();
      expect(n.state.webdavServer, isNull);
      expect(n.state.allowCveLookup, isFalse);
      expect(n.state.cveApiBaseUrl, AppSettings.defaultCveApiBaseUrl);
      expect(n.state.aiSettings.enabled, isFalse);
      expect(n.state.selectedCockpitColorSchemeName, 'Standaard');
      expect(
        n.state.cockpitColorSchemes.map((s) => s.name),
        contains('Standaard'),
      );
    });

    test('a webdav connection stores, reloads and clears', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await loaded();
      const server = WebdavServer(
        baseUrl: 'https://cloud.example.com',
        username: 'alice',
        rootPath: '/Presentaties',
      );
      final connection = WebdavConnection(
        id: StorageConnection.newId(),
        name: 'Klant A',
        server: server,
      );
      await n.addConnection(connection);
      expect(n.state.webdavServer, isNotNull);
      expect(n.state.webdavServer!.username, 'alice');

      // A fresh notifier on the same mock store reads it back.
      final reloaded = await loaded();
      expect(reloaded.state.webdavServer?.baseUrl, 'https://cloud.example.com');
      expect(reloaded.state.webdavServer?.rootPath, '/Presentaties');

      await n.removeConnection(connection.id);
      expect(n.state.webdavServer, isNull);
    });

    test(
      'webdav password round-trips through the injected secret store',
      () async {
        final store = _MemorySecretStore();
        final n = await loaded(store: store);
        expect(
          await n.setWebdavPassword('https://c.example.com', 'alice', 'geheim'),
          isTrue,
        );
        expect(
          await n.readWebdavPassword('https://c.example.com', 'alice'),
          'geheim',
        );
        // An empty password deletes the entry.
        expect(
          await n.setWebdavPassword('https://c.example.com', 'alice', ''),
          isTrue,
        );
        expect(
          await n.readWebdavPassword('https://c.example.com', 'alice'),
          isNull,
        );
      },
    );

    test(
      'AI settings persist and the API key round-trips via the keychain',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = _MemorySecretStore();
        final n = await loaded(store: store);
        const settings = AiSettings(
          enabled: true,
          mode: AiBackendMode.local,
          baseUrl: 'http://127.0.0.1:11434/v1',
          model: 'gemma3:4b',
        );
        await n.setAiSettings(settings);
        expect(n.state.aiSettings.enabled, isTrue);
        expect(n.state.aiSettings.model, 'gemma3:4b');

        expect(
          await n.setAiApiKey('http://127.0.0.1:11434/v1', 'sk-1'),
          isTrue,
        );
        expect(await n.readAiApiKey('http://127.0.0.1:11434/v1'), 'sk-1');
        // Clearing the key removes it.
        expect(await n.setAiApiKey('http://127.0.0.1:11434/v1', ''), isTrue);
        expect(await n.readAiApiKey('http://127.0.0.1:11434/v1'), isNull);
      },
    );

    test('CVE lookup toggle and mirror URL fall back to the default', () async {
      final n = await loaded();
      await n.setAllowCveLookup(true);
      expect(n.state.allowCveLookup, isTrue);

      await n.setCveApiBaseUrl('https://mirror.example.nl');
      expect(n.state.cveApiBaseUrl, 'https://mirror.example.nl');

      // A blank URL resets to the built-in default rather than storing empty.
      await n.setCveApiBaseUrl('   ');
      expect(n.state.cveApiBaseUrl, AppSettings.defaultCveApiBaseUrl);
    });

    test('removeRecentFile drops a path and ignores unknown ones', () async {
      final n = await loaded();
      await n.addRecentFile('/a.md');
      await n.addRecentFile('/b.md');
      expect(n.state.recentFiles, hasLength(2));

      await n.removeRecentFile('/a.md');
      expect(n.state.recentFiles.map((f) => f.path), ['/b.md']);

      // Removing a path that is not listed is a no-op.
      await n.removeRecentFile('/onbekend.md');
      expect(n.state.recentFiles, hasLength(1));
    });

    test('selectThemeProfile changes the active profile', () async {
      final n = await loaded();
      await n.selectThemeProfile('Security');
      expect(n.state.selectedThemeProfileName, 'Security');
      expect(n.state.themeProfile.name, 'Security');
    });

    test(
      'selectAppAppearanceProfile switches valid, ignores unknown',
      () async {
        final n = await loaded();
        await n.selectAppAppearanceProfile('Donker');
        expect(n.state.selectedAppAppearanceProfileName, 'Donker');

        await n.selectAppAppearanceProfile('Bestaat niet');
        expect(n.state.selectedAppAppearanceProfileName, 'Donker');
      },
    );

    test('a custom app theme can be deleted, falling back to Europa', () async {
      final n = await loaded();
      final created = await n.createAppAppearanceProfile(
        base: AppAppearanceProfile.europa,
      );
      expect(n.state.selectedAppAppearanceProfileName, created.name);

      await n.deleteAppAppearanceProfile(created.name);
      expect(
        n.state.appAppearanceProfiles.map((p) => p.name),
        isNot(contains(created.name)),
      );
      expect(n.state.selectedAppAppearanceProfileName, 'Europa');
    });

    group('cockpit colour schemes', () {
      test('create, edit, select and delete round-trip', () async {
        final n = await loaded();
        expect(n.state.cockpitColorSchemes.map((s) => s.name), ['Standaard']);

        final created = await n.createCockpitColorScheme();
        expect(created.isBuiltIn, isFalse);
        expect(n.state.selectedCockpitColorSchemeName, created.name);

        await n.saveCockpitColorScheme(
          created.copyWith(name: 'Nacht', good: '#000000'),
          previousName: created.name,
        );
        expect(n.state.selectedCockpitColorSchemeName, 'Nacht');
        final saved = n.state.cockpitColorSchemes.firstWhere(
          (s) => s.name == 'Nacht',
        );
        expect(saved.good, '#000000');

        // Selecting an unknown scheme is a no-op; a known one switches.
        await n.selectCockpitColorScheme('Bestaat niet');
        expect(n.state.selectedCockpitColorSchemeName, 'Nacht');
        await n.selectCockpitColorScheme('Standaard');
        expect(n.state.selectedCockpitColorSchemeName, 'Standaard');

        await n.deleteCockpitColorScheme('Nacht');
        expect(
          n.state.cockpitColorSchemes.map((s) => s.name),
          isNot(contains('Nacht')),
        );
        expect(n.state.selectedCockpitColorSchemeName, 'Standaard');
      });

      test('the built-in scheme cannot be deleted', () async {
        final n = await loaded();
        await n.deleteCockpitColorScheme('Standaard');
        expect(n.state.cockpitColorSchemes.map((s) => s.name), ['Standaard']);
      });

      test('a custom scheme is read back by a fresh notifier', () async {
        SharedPreferences.setMockInitialValues({});
        final n = await loaded();
        final created = await n.createCockpitColorScheme();
        await n.saveCockpitColorScheme(
          created.copyWith(name: 'Amber', warning: '#FFAA00'),
          previousName: created.name,
        );

        final reloaded = await loaded();
        final amber = reloaded.state.cockpitColorSchemes.firstWhere(
          (s) => s.name == 'Amber',
        );
        expect(amber.warning, '#FFAA00');
        expect(reloaded.state.selectedCockpitColorSchemeName, 'Amber');
      });
    });
  });
}
