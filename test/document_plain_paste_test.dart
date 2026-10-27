import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show ChangeSource, FlutterQuillLocalizations, QuillEditor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/platform/clipboard_html.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart' show imageServiceProvider;
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// Shift+Ctrl/Cmd+V is "plakken zonder opmaak" (#2608): alleen de
/// `text/plain`-variant van het klembord — geen afbeeldingsimport, geen
/// tabelherkenning uit TSV, geen HTML→Markdown, en in de visuele stand geen
/// Markdown-lezing van de geplakte letters.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Future<DocumentNotifier> pumpEditor(
    WidgetTester tester, {
    required String clipboardText,
    String? clipboardHtml,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': clipboardText}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    debugClipboardHtmlReader = () async => clipboardHtml;
    addTearDown(() => debugClipboardHtmlReader = null);

    final notifier = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Eerste zin.\n\nTweede zin.\n'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentProvider.overrideWith((_) => notifier),
          // Geen afbeelding op het testklembord — de tekstroutes tellen.
          imageServiceProvider.overrideWithValue(_NoClipboardImage()),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byType(QuillEditor),
      findsOneWidget,
      reason: 'begint in de visuele stand',
    );
    return notifier;
  }

  Future<void> sendPlainPasteChord(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> sendPasteChord(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> focusSourceAt(WidgetTester tester, int offset) async {
    await tester.tap(find.text('Bron'));
    await tester.pump();
    tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!
        .selection = TextSelection.collapsed(
      offset: offset,
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
  }

  testWidgets(
    'slimme plak zet klembord-HTML om naar Markdown (contrastroute)',
    (tester) async {
      final notifier = await pumpEditor(
        tester,
        clipboardText: 'alleen tekst',
        clipboardHtml: '<h2>AndereKop</h2>',
      );
      // Caret vooraan in de visuele stand.
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      tester
          .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
          .controller
          .updateSelection(
            const TextSelection.collapsed(offset: 0),
            ChangeSource.local,
          );
      await tester.pump();
      await sendPasteChord(tester);
      await pumpUntil(
        tester,
        () => (notifier.currentState.document?.body ?? '').contains(
          '## AndereKop',
        ),
        reason: 'de HTML-variant werd geen kop',
      );
    },
  );

  testWidgets(
    'Shift+Ctrl+V in Visueel plakt alleen de platte tekst, geen HTML-Markdown',
    (tester) async {
      final notifier = await pumpEditor(
        tester,
        clipboardText: 'alleen tekst',
        clipboardHtml: '<h2>AndereKop</h2>',
      );
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      tester
          .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
          .controller
          .updateSelection(
            const TextSelection.collapsed(offset: 0),
            ChangeSource.local,
          );
      await tester.pump();
      await sendPlainPasteChord(tester);
      await pumpUntil(
        tester,
        () => (notifier.currentState.document?.body ?? '').contains(
          'alleen tekst',
        ),
        reason: 'de platte tekst kwam niet in het document terecht',
      );
      final body = notifier.currentState.document!.body;
      expect(body, isNot(contains('AndereKop')));
      expect(body, isNot(contains('## ')));
    },
  );

  testWidgets('Shift+Ctrl+V in Bron plakt TSV letterlijk, geen GFM-tabel', (
    tester,
  ) async {
    final notifier = await pumpEditor(tester, clipboardText: 'a\tb\nc\td');
    await focusSourceAt(tester, 0);
    await sendPlainPasteChord(tester);
    await pumpUntil(
      tester,
      () => (notifier.currentState.document?.body ?? '').contains('a\tb'),
      reason: 'de letterlijke TSV kwam niet in de bron terecht',
    );
    final body = notifier.currentState.document!.body;
    expect(body, contains('a\tb\nc\td'));
    expect(body, isNot(contains('| a | b |')));
  });

  testWidgets('Shift+Ctrl+V in Visueel leest de letters niet als Markdown', (
    tester,
  ) async {
    await pumpEditor(tester, clipboardText: '**dik**');
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    final quill = tester
        .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
        .controller;
    quill.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await tester.pump();
    await sendPlainPasteChord(tester);
    await pumpUntil(
      tester,
      () => quill.document.toPlainText().contains('**dik**'),
      reason: 'de plak kwam niet in het schrijfvlak terecht',
    );
    // De sterretjes staan letterlijk in de tekst en dragen géén bold-attribuut
    // — de slimme route had ze als opmaak geïnterpreteerd.
    final ops = quill.document.toDelta().toList();
    final pasted = ops.where(
      (op) => op.data is String && (op.data! as String).contains('**dik**'),
    );
    expect(pasted, isNotEmpty);
    for (final op in pasted) {
      expect(op.attributes?['bold'], isNot(isTrue));
    }
  });
}

/// Geen afbeelding op het testklembord.
class _NoClipboardImage extends ImageService {
  @override
  Future<ImageImportOutcome> pasteImageDetailed({String? projectPath}) async =>
      const ImageImportOutcome.failed(ImageImportFailure.noClipboardImage);
}
