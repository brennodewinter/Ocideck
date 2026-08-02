import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    Widget Function(BuildContext, String)? previewBuilder,
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
          previewBuilder: previewBuilder,
        ),
      ),
    ),
  );

  test('complex Markdown is kept in source mode', () {
    expect(markdownNeedsSourceMode('| A | B |\n|---|---|'), isTrue);
    expect(markdownNeedsSourceMode('Gewone **tekst**'), isFalse);
  });

  testWidgets('compact toolbar appears on focus and edits Markdown', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'tekst');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    expect(find.byTooltip('Vet'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Vet'), findsOneWidget);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.tap(find.byTooltip('Vet'));
    await tester.pumpAndSettle();
    expect(controller.text, '**tekst**');
  });

  testWidgets('expanded editor writes through to the field controller', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'begin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await tester.tap(find.text('Bewerken'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);

    final expandedField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(expandedField, '## Uitgebreid');
    await tester.pump(const Duration(milliseconds: 130));
    expect(controller.text, '## Uitgebreid');

    await tester.tap(find.text('Klaar'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('expanded editor debounces updates and flushes when closed', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'begin');
    addTearDown(controller.dispose);
    var updates = 0;
    controller.addListener(() => updates++);
    await tester.pumpWidget(host(controller));

    await tester.tap(find.text('Bewerken'));
    await tester.pumpAndSettle();
    final expandedField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    final draft = tester.widget<TextField>(expandedField).controller!;
    draft.text = 'een';
    await tester.pump(const Duration(milliseconds: 40));
    draft.text = 'twee';
    await tester.pump(const Duration(milliseconds: 40));
    draft.text = 'drie';
    await tester.pump(const Duration(milliseconds: 40));

    expect(controller.text, 'begin');
    expect(updates, 0);
    await tester.tap(find.text('Klaar'));
    await tester.pumpAndSettle();
    expect(controller.text, 'drie');
    expect(updates, 1);
  });

  testWidgets('shortcut opens expanded editor with a live preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'begin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        controller,
        previewBuilder: (_, markdown) => Text('PREVIEW:$markdown'),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('PREVIEW:begin'), findsOneWidget);

    final expandedField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(expandedField, '**nieuw**');
    await tester.pump(const Duration(milliseconds: 130));
    expect(find.text('PREVIEW:**nieuw**'), findsOneWidget);
  });

  testWidgets('small layouts expose writing and preview as tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'smal');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        controller,
        previewBuilder: (_, markdown) => Text('PREVIEW:$markdown'),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Bewerken'));
    await tester.pumpAndSettle();
    expect(find.text('Bewerken'), findsWidgets);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('PREVIEW:smal'), findsNothing);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('PREVIEW:smal'), findsOneWidget);
  });

  testWidgets('dark theme and 200 percent text remain usable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: 'toegankelijk');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        controller,
        theme: ThemeData.dark(),
        textScale: 2,
        previewBuilder: (_, markdown) => Text(markdown),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Bewerken'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last visual mode is restored for compatible Markdown', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'markdownFieldEditorMode': NotesEditorMode.visual.name,
    });
    final controller = TextEditingController(text: 'gewone tekst');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await tester.tap(find.text('Bewerken'));
    await tester.pumpAndSettle();
    expect(find.byType(QuillEditor), findsOneWidget);
  });
}
