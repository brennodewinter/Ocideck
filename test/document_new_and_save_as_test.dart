import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart' show fileServiceProvider;
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Nieuw document maken + 'Opslaan als…' (DOCUMENT_MODE.md §3): een nieuw leeg
/// document opent in een eigen tabblad, en het eerste opslaan (nog geen pad)
/// kiest een pad en schrijft het byte-getrouw weg — de maak→bewaar-cyclus rond.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  /// Een FileService waarvan het bewaar-venster [dest] teruggeeft (of null bij
  /// wegklikken), zodat het opslag-pad onder `flutter test` te toetsen is.
  FileService fileServiceReturning(String? dest) => FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
    saveDestination: ({dialogTitle, fileName, initialDirectory}) async => dest,
  );

  group('FileService.saveDocumentAs', () {
    test('vult .md aan en schrijft de bron byte-getrouw', () async {
      final temp = Directory.systemTemp.createTempSync('saveas');
      addTearDown(() => temp.deleteSync(recursive: true));
      final target = p.join(temp.path, 'memo'); // zonder .md
      final doc = MarkdownDocument.parse('# Memo\n\ninhoud\n');

      final path = await fileServiceReturning(target).saveDocumentAs(doc);

      expect(path, '$target.md');
      expect(File('$target.md').readAsStringSync(), '# Memo\n\ninhoud\n');
    });

    test('wegklikken schrijft niets en geeft null', () async {
      final path = await fileServiceReturning(
        null,
      ).saveDocumentAs(MarkdownDocument.parse('x'));
      expect(path, isNull);
    });
  });

  // Een nieuwe container waarvan de instellingen al asynchroon uit prefs
  // geladen zijn — de bibliotheek staat erin voor we newDocument aanroepen,
  // dat de thuismap leest. Pollen in plaats van een vaste vertraging: de
  // SettingsNotifier laadt op eigen snelheid, en een vaste wait is juist de
  // vorm die op een trage gate willekeurig faalt.
  Future<ProviderContainer> containerWithLibrary(Directory home) async {
    SharedPreferences.setMockInitialValues({
      'storageConnections': StorageConnection.encodeList([
        LocalConnection(id: 'lok', name: 'Werkmap', path: home.path),
      ]),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (
      var i = 0;
      i < 500 && container.read(settingsProvider).libraries.isEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      container.read(settingsProvider).libraries,
      isNotEmpty,
      reason: 'bibliotheek uit prefs niet geladen',
    );
    return container;
  }

  group('newDocument op schijf', () {
    late Directory home;

    setUp(() {
      AppLocalizations.setActiveLanguageCode('nl');
      home = Directory.systemTemp.createTempSync('newdoc_on_disk');
    });

    tearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    test(
      'maakt meteen een bestand op schijf en opent het met een pad',
      () async {
        final container = await containerWithLibrary(home);
        await container.read(tabsProvider.notifier).newDocument();

        final tabs = container.read(tabsProvider).tabs;
        expect(container.read(tabsProvider).selectedIndex, tabs.length - 1);
        final current = container.read(tabsProvider).current!;
        expect(current.kind, MarkdownKind.document);
        expect(current.isOpen, isTrue);
        expect(
          current.documentNotifier!.currentState.document!.toMarkdown(),
          '',
        );
        final path = current.documentNotifier!.currentState.filePath!;
        expect(p.isWithin(home.path, path), isTrue);
        expect(File(path).existsSync(), isTrue);
        expect(File(path).readAsStringSync(), '');
        // Schoon: het bestand staat op schijf, dus de tab is niet vuil en de
        // eerste Cmd/Ctrl+S slaat in-place op in plaats van 'Opslaan als…'.
        expect(current.documentNotifier!.currentState.isDirty, isFalse);
      },
    );

    test('twee nieuwe documenten krijgen elk een eigen bestandsnaam', () async {
      final container = await containerWithLibrary(home);
      await container.read(tabsProvider.notifier).newDocument();
      await container.read(tabsProvider.notifier).newDocument();

      final tabs = container.read(tabsProvider).tabs;
      final path1 =
          tabs[tabs.length - 2].documentNotifier!.currentState.filePath!;
      final path2 = tabs.last.documentNotifier!.currentState.filePath!;
      expect(path1, isNot(path2));
      expect(p.basename(path1), 'document.md');
      expect(p.basename(path2), 'document 2.md');
      expect(File(path1).existsSync(), isTrue);
      expect(File(path2).existsSync(), isTrue);
    });

    test('het nieuwe bestand komt bovenaan de recente lijst', () async {
      final container = await containerWithLibrary(home);
      await container.read(tabsProvider.notifier).newDocument();
      final path = container
          .read(tabsProvider)
          .current!
          .documentNotifier!
          .currentState
          .filePath!;

      final recents = container.read(settingsProvider).recentFiles;
      expect(recents.first.path, path);
      expect(recents.first.kind, MarkdownKind.document);
    });
  });

  testWidgets('Cmd+S op een document zonder pad valt terug op Opslaan als…', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('saveas_widget');
    addTearDown(() => temp.deleteSync(recursive: true));
    final target = p.join(temp.path, 'nieuw.md');

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Nieuw document\n'));
    expect(n.currentState.filePath, isNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentProvider.overrideWith((ref) => n),
          fileServiceProvider.overrideWithValue(fileServiceReturning(target)),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DocumentEditorScreen(),
        ),
      ),
    );

    // Roep de opslag-binding rechtstreeks aan (Flutters eigen toets→binding is
    // al gedekt); in runAsync, want het wegschrijven is echte schijf-IO.
    const saveActivator = SingleActivator(LogicalKeyboardKey.keyS, meta: true);
    final shortcuts = tester
        .widgetList<CallbackShortcuts>(find.byType(CallbackShortcuts))
        .firstWhere((w) => w.bindings.containsKey(saveActivator));
    await tester.runAsync(() async {
      shortcuts.bindings[saveActivator]!();
      // filePath staat pas ná de awaited atomic write + markSaved
      // (document_editor_screen._save roept markSaved aan ná `await
      // saveDocumentAs`), dus dit is het juiste wachtsignaal. Het budget moet
      // ruim: op de Forgejo linux-gate draaien vier job-containers parallel op
      // één dind, en onder die I/O-contentie haalde de write de oude 500ms niet
      // → filePath bleef null (#1363). 5s vangt de last-piek af zonder een
      // echte hang te verbergen (bounded) — zelfde budget als de zuster-test in
      // document_editor_screen_test.dart.
      for (var i = 0; i < 500 && n.currentState.filePath == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    // Het gekozen pad is nu het pad van het document, byte-getrouw geschreven.
    expect(n.currentState.filePath, target);
    expect(n.currentState.isDirty, isFalse);
    expect(File(target).readAsStringSync(), '# Nieuw document\n');
  });
}
