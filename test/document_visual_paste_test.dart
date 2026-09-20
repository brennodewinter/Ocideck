import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show ChangeSource, FlutterQuillLocalizations, QuillEditor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart' show imageServiceProvider;
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plakken in de visuele stand landt op de cursor, niet als eigen blok eronder
/// of onderaan het document (#2138).
///
/// De plakroute stuurde élke geplakte tekst door het blok-invoegpad, dat bewust
/// het einde van de regel zoekt — goed voor een tabel, fout voor een zin. Tekst
/// hoort op de caret en vervangt een actieve selectie.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Future<DocumentNotifier> pumpEditor(
    WidgetTester tester, {
    required String clipboardText,
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

    final notifier = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Eerste zin.\n\nTweede zin.\n'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentProvider.overrideWith((_) => notifier),
          // Geen afbeelding op het testklembord — de teksttak is de bedoeling.
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

  /// Klik in het schrijfvlak (focus) en zet de Quill-caret op [offset] in de
  /// platte tekst van het document.
  Future<void> placeCaret(WidgetTester tester, int offset) async {
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    tester
        .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
        .controller
        .updateSelection(
          TextSelection.collapsed(offset: offset),
          ChangeSource.local,
        );
    await tester.pump();
  }

  Future<void> paste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    // De plakroute leest het klembord asynchroon — laat die keten aflopen.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  testWidgets('tekst plakken landt inline op de cursor (#2138)', (
    tester,
  ) async {
    final notifier = await pumpEditor(tester, clipboardText: 'plak');
    // Caret midden in "zin" (offset 8, tussen z en i) → "Eerste zplakin.":
    // letterlijk óp de caret, niet als eigen regel eronder.
    await placeCaret(tester, 8);
    await paste(tester);
    expect(
      notifier.currentState.document!.body,
      'Eerste zplakin.\n\nTweede zin.',
    );
  });

  testWidgets('plakken vervangt de actieve selectie (#2138)', (tester) async {
    final notifier = await pumpEditor(tester, clipboardText: 'alinea');
    // Selecteer het woord "zin" (offset 7 t/m 10) in "Eerste zin."
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    tester
        .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
        .controller
        .updateSelection(
          const TextSelection(baseOffset: 7, extentOffset: 10),
          ChangeSource.local,
        );
    await tester.pump();
    await paste(tester);
    expect(
      notifier.currentState.document!.body,
      'Eerste alinea.\n\nTweede zin.',
    );
  });
}

class _NoClipboardImage extends ImageService {
  @override
  Future<ImageImportOutcome> pasteImageDetailed({String? projectPath}) async =>
      const ImageImportOutcome.failed(ImageImportFailure.noClipboardImage);
}
