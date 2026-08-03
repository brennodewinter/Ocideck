import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/editors/markdown_editor_field.dart';
import 'package:ocideck/widgets/editors/expanded_markdown_dialog.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget host(
    TextEditingController controller, {
    ThemeData? theme,
    double textScale = 1,
  }) => MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 700,
        child: MarkdownEditorField(
          label: 'Beschrijving',
          controller: controller,
        ),
      ),
    ),
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Bewerken'));
    await tester.pumpAndSettle();
  }

  test('complex Markdown is kept in source mode', () {
    expect(markdownNeedsSourceMode('| A | B |\n|---|---|'), isTrue);
    expect(markdownNeedsSourceMode('Gewone **tekst**'), isFalse);
  });

  testWidgets('the inline field stays quiet — no floating toolbar on focus', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'tekst');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    expect(find.byTooltip('Vet'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    // Formatting lives in the expand editor now, not in a strip over the field.
    expect(find.byTooltip('Vet'), findsNothing);
  });

  testWidgets('expand opens a WYSIWYG word-processor, no preview pane', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'begin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await openDialog(tester);

    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    // Default is the friendly visual editor.
    expect(find.byType(QuillEditor), findsOneWidget);
    // The mode switch is visible for those who prefer raw Markdown.
    expect(find.text('Visuele modus'), findsOneWidget);
    expect(find.text('Markdown modus'), findsOneWidget);
    // No separate preview surface remains.
    expect(find.text('Preview'), findsNothing);
  });

  testWidgets('switching to Markdown mode writes through, flushes on close', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'begin');
    addTearDown(controller.dispose);
    var updates = 0;
    controller.addListener(() => updates++);
    await tester.pumpWidget(host(controller));

    await openDialog(tester);
    await tester.tap(find.text('Markdown modus'));
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);

    await tester.enterText(field, '## Uitgebreid');
    // Below the debounce the source is untouched.
    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.text, 'begin');
    // After the debounce it commits.
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.text, '## Uitgebreid');

    await tester.tap(find.text('Klaar'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(updates, greaterThan(0));
  });

  testWidgets('closing flushes a pending debounce without losing input', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'begin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await openDialog(tester);
    await tester.tap(find.text('Markdown modus'));
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'drie');
    // Close before the debounce fires; disposing must still flush.
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Klaar'));
    await tester.pumpAndSettle();
    expect(controller.text, 'drie');
  });

  testWidgets('table content opens in source mode with the protective hint', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: '| A | B |\n|---|---|');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await openDialog(tester);
    // No lossy visual editor for a table; raw source instead.
    expect(find.byType(QuillEditor), findsNothing);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
  });

  testWidgets('last chosen Markdown mode is restored for compatible text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'markdownFieldEditorMode': NotesEditorMode.markdown.name,
    });
    final controller = TextEditingController(text: 'gewone tekst');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await openDialog(tester);
    expect(find.byType(QuillEditor), findsNothing);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dark theme and 200 percent text remain usable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'toegankelijk');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(controller, theme: ThemeData.dark(), textScale: 2),
    );
    expect(tester.takeException(), isNull);

    await openDialog(tester);
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
