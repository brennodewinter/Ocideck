import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(DocumentNotifier notifier) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => notifier)],
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
  );

  /// Wissel naar bron-modus (standaard is Visueel).
  Future<void> openSource(WidgetTester tester) async {
    await tester.tap(find.text('Bron'));
    await tester.pump();
  }

  testWidgets('standaard Visueel: bewerkbaar oppervlak + moduskeuze', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Visueel | Bron staat in de werkbalk.
    expect(find.text('Visueel'), findsOneWidget);
    expect(find.text('Bron'), findsOneWidget);
    // Standaard visueel: de gedeelde notes-editor, geen read-only preview.
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(find.byType(DocumentMarkdownView), findsNothing);
    // Eenvoudige markdown → Quill-WYSIWYG (bewerkbaar).
    expect(find.byType(QuillEditor), findsOneWidget);
  });

  testWidgets('Visueel: een tabel valt niet terug op ruwe markdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n'
          '| Team | Omzet |\n| --- | ---: |\n| Ontwerp | 120 |\n',
        ),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // De regressie (#1328): een tabel dwong Visueel naar de ruwe-markdown-
    // terugval. Nu blijft het de bewerkbare WYSIWYG — de tabel is een embed.
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(find.byType(QuillEditor), findsOneWidget);
    // De tabel wordt als gerenderde embed getekend (DocumentMarkdownView), niet
    // als de letterlijke tekst `| Team | Omzet |` in een tekstveld.
    expect(find.byType(DocumentMarkdownView), findsWidgets);
    expect(find.text('| Team | Omzet |'), findsNothing);
  });

  testWidgets('Visueel: rauwe HTML toont de leesweergave, geen broncode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Kop\n\n<div>rauwe html</div>\n\nTekst.'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Een constructie die de brug niet verliesvrij aankan → nette leesweergave,
    // geen ruwe markdown en geen bewerkbare Quill.
    expect(find.byType(MarkdownNotesEditor), findsNothing);
    expect(find.byType(QuillEditor), findsNothing);
    expect(find.byType(DocumentMarkdownView), findsOneWidget);
    expect(find.textContaining('Bronmodus beschermt opmaak'), findsOneWidget);
  });

  testWidgets('Bron toont rauwe bron én live weergave', (tester) async {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();
    await openSource(tester);

    expect(find.widgetWithText(TextField, '# Kop\n\nTekst.'), findsOneWidget);
    final view = tester.widget<DocumentMarkdownView>(
      find.byType(DocumentMarkdownView),
    );
    expect(view.markdown, '# Kop\n\nTekst.');
  });

  testWidgets('typen in bron stroomt live naar de notifier', (tester) async {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'Hallo wereld');
    await tester.pump();

    expect(n.currentState.document!.source, 'Hallo wereld');
    expect(n.currentState.isDirty, isTrue);
  });

  testWidgets('ongedaan maken werkt de editortekst bij', (tester) async {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();
    n.undo();
    await tester.pump();

    expect(find.widgetWithText(TextField, 'a'), findsOneWidget);
  });

  testWidgets('de Overzicht-rail toont de koppen zonder crash', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Een\n\n## Twee\n\ntekst\n\n# Drie\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    expect(find.text('Een'), findsWidgets);
    expect(find.text('Twee'), findsWidgets);
    expect(find.text('Drie'), findsWidgets);

    await tester.tap(find.text('Twee').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cmd+S slaat op naar het pad en maakt het document schoon', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('doc_save');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync('oud\n');

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('oud\n'), filePath: path);
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'nieuw\n');
    await tester.pump();
    expect(n.currentState.isDirty, isTrue);

    const saveActivator = SingleActivator(LogicalKeyboardKey.keyS, meta: true);
    final shortcuts = tester
        .widgetList<CallbackShortcuts>(find.byType(CallbackShortcuts))
        .firstWhere((w) => w.bindings.containsKey(saveActivator));
    await tester.runAsync(() async {
      shortcuts.bindings[saveActivator]!();
      // isDirty clear't pas ná de awaited atomic write (document_editor_screen
      // roept markSaved aan ná `await saveDocument`), dus dit is het juiste
      // wachtsignaal. Het budget moet wel ruim: op de Forgejo linux-gate draaien
      // vier job-containers parallel op één dind, en onder die I/O-contentie
      // haalde de write de oude 500ms niet → de lus las nog 'oud'. 5s vangt de
      // last-piek af zonder een echte hang te verbergen (bounded).
      for (var i = 0; i < 500 && n.currentState.isDirty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(File(path).readAsStringSync(), 'nieuw\n');
    expect(n.currentState.isDirty, isFalse);
  });

  testWidgets('het invoeg-palet schrijft een mermaid-blok in de bron', (
    tester,
  ) async {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Tekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mermaid'));
    await tester.pump();

    final source = n.currentState.document!.source;
    expect(source, contains('```mermaid'));
    expect(source, startsWith('Tekst.'));
  });

  testWidgets(
    'Invoegen → Afbeelding opent de carrousel, niet alleen Bladeren',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse('Tekst.'));
      await tester.pumpWidget(harness(n));
      await tester.pump();

      await tester.tap(find.text('Invoegen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Afbeelding'));
      await tester.pump();
      // De scan/I/O van de carrousel; font-overflow in tests is cosmetisch.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      while (tester.takeException() != null) {}

      expect(find.byType(ImageCarouselPicker), findsOneWidget);
      expect(find.text('Afbeelding kiezen'), findsOneWidget);
    },
  );

  testWidgets(
    'opmaakknop Afbeelding opent de carrousel, dumpt geen placeholder',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse('video en meer tekst'));
      await tester.pumpWidget(harness(n));
      await openSource(tester);

      await tester.tap(find.byTooltip('Afbeelding'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      while (tester.takeException() != null) {}

      expect(find.byType(ImageCarouselPicker), findsOneWidget);
      expect(n.currentState.document!.source, 'video en meer tekst');
      expect(n.currentState.document!.source, isNot(contains('pad-of-url')));
    },
  );

  testWidgets('Overzicht: klik springt in Visueel; inklappen werkt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Een\n\ntekst\n\n# Twee\n\nmeer\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    expect(find.text('OVERZICHT'), findsOneWidget);
    final outlineTwee = find.descendant(
      of: find.byKey(const Key('document-outline-rail')),
      matching: find.text('Twee'),
    );
    await tester.tap(outlineTwee);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Overzicht inklappen'));
    await tester.pump();
    expect(find.text('OVERZICHT'), findsNothing);
    expect(find.byTooltip('Overzicht uitklappen'), findsOneWidget);
  });

  testWidgets('undo/redo-knoppen volgen canUndo/canRedo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    await tester.pumpWidget(harness(n));
    await openSource(tester);
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();

    expect(n.currentState.canUndo, isTrue);
    await tester.tap(find.byTooltip('Ongedaan maken'));
    await tester.pump();
    expect(n.currentState.document!.source, 'a');
    expect(n.currentState.canRedo, isTrue);

    await tester.tap(find.byTooltip('Opnieuw'));
    await tester.pump();
    expect(n.currentState.document!.source, 'ab');
  });

  testWidgets('⋮-menu in documentmodus biedt Instellingen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('x'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.byTooltip('Meer'));
    await tester.pumpAndSettle();
    expect(find.text('Instellingen'), findsOneWidget);
  });

  testWidgets(
    'de opmaak-knoppenbalk in bron muteert de bron en stroomt naar de notifier',
    (tester) async {
      final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
      await tester.pumpWidget(harness(n));
      await openSource(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      await tester.tap(find.byTooltip('Vet'));
      await tester.pump();

      expect(n.currentState.document!.source, contains('**'));
      expect(n.currentState.isDirty, isTrue);
    },
  );
}
