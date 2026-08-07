import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart' show fileServiceProvider;
import 'package:ocideck/state/document_provider.dart';
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

  test('newDocument opent een leeg documenttabblad, geselecteerd', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(tabsProvider.notifier).newDocument();

    final current = container.read(tabsProvider).current!;
    expect(current.kind, MarkdownKind.document);
    expect(current.documentNotifier!.currentState.isOpen, isTrue);
    expect(current.documentNotifier!.currentState.document!.toMarkdown(), '');
    expect(current.documentNotifier!.currentState.filePath, isNull);
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
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
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
      for (var i = 0; i < 50 && n.currentState.filePath == null; i++) {
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
