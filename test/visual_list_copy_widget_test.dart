import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

/// Regressie #2439 door het echte veld: Cmd/Ctrl+C én het contextmenu zetten
/// bij een selectie die midden in een regel begint de Markdown met de lijsten
/// op het klembord, niet de platte tekst.
void main() {
  late QuillController controller;
  String? clipboard;

  setUp(() {
    clipboard = null;
    controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(
        '- eerste\n- tweede\n- derde\n',
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String?;
            case 'Clipboard.getData':
              return <String, Object?>{'text': clipboard ?? 'geplakt'};
            case 'Clipboard.hasStrings':
              return <String, Object?>{'value': true};
          }
          return null;
        });
  });

  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpField(WidgetTester tester) async {
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: WysiwygNotesField(
            controller: controller,
            scrollController: scroll,
            focusNode: focus,
            editorTheme: MarkdownEditorTheme.documentSurface(
              scheme: const ColorScheme.light(),
            ),
            hintText: '',
            expand: true,
          ),
        ),
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
  }

  void selectFromSecondCharacter() => controller.updateSelection(
    TextSelection(baseOffset: 1, extentOffset: controller.document.length - 1),
    ChangeSource.local,
  );

  testWidgets('Ctrl+C houdt de bullets van de volgende items', (tester) async {
    await pumpField(tester);
    selectFromSecondCharacter();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(clipboard, 'erste\n\n- tweede\n- derde');
  });

  testWidgets('het contextmenu kopieert langs dezelfde route', (tester) async {
    await pumpField(tester);
    selectFromSecondCharacter();
    await tester.pump();
    final field = find.byType(QuillEditor);
    await tester.tapAt(tester.getCenter(field), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final copy = find.text('Copy');
    expect(copy, findsOneWidget, reason: 'het contextmenu moet openen');
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard, 'erste\n\n- tweede\n- derde');
  });

  testWidgets(
    'knippen via het contextmenu wist de selectie en houdt de lijst',
    (tester) async {
      await pumpField(tester);
      selectFromSecondCharacter();
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.byType(QuillEditor)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();
      expect(clipboard, 'erste\n\n- tweede\n- derde');
      expect(controller.document.toPlainText(), 'e\n');
    },
  );

  testWidgets('plakken via het contextmenu gaat door onze plakroute', (
    tester,
  ) async {
    await pumpField(tester);
    var consumed = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    // Eigen veld met een plak-afvanger, om te zien dat het menu hem aanroept.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: WysiwygNotesField(
            controller: controller,
            scrollController: ScrollController(),
            focusNode: focus,
            editorTheme: MarkdownEditorTheme.documentSurface(
              scheme: const ColorScheme.light(),
            ),
            hintText: '',
            expand: true,
            tryConsumePaste: () async {
              consumed++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    selectFromSecondCharacter();
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byType(QuillEditor)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final paste = find.text('Paste');
    expect(
      paste,
      findsOneWidget,
      reason: 'met klembordtekst toont het menu Plakken',
    );
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(consumed, 1);
  });
}
