import 'dart:async';

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

/// Knippen en slim plakken zijn één atomaire handeling op de positie van het
/// moment van de opdracht (#2466). Tijdens trage klembord-I/O kan de
/// gebruiker verder typen, de caret verplaatsen of van stand wisselen — de
/// mutatie mag dan niet op een andere plek landen en niet een ander bereik
/// wissen.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  /// Klembord-mocks met een handrem: `setData` en `getData` wachten op hun
  /// completers, zodat de test beheerst wat er tussendoor gebeurt.
  var setDataGate = Completer<void>();
  var getDataGate = Completer<void>();
  String? clipboardWrite;

  void mockClipboard(WidgetTester tester, {String clipboardText = 'plak'}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardWrite = (call.arguments as Map)['text'] as String?;
            await setDataGate.future;
            return null;
          case 'Clipboard.getData':
            await getDataGate.future;
            return <String, dynamic>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<DocumentNotifier> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Geen HTML-variant op het testklembord — de platte tekst telt.
    debugClipboardHtmlReader = () async => null;
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
    expect(find.byType(QuillEditor), findsOneWidget);
    return notifier;
  }

  /// De Quill-controller van het gemonteerde schrijfvlak.
  dynamic quillOf(WidgetTester tester) => tester
      .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
      .controller;

  Future<void> focusVisual(WidgetTester tester) async {
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
  }

  Future<void> sendChord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets(
    'knip met trage setData + tussentijds typen wist geen ander bereik',
    (tester) async {
      setDataGate = Completer<void>();
      clipboardWrite = null;
      mockClipboard(tester);
      final notifier = await pumpEditor(tester);
      await focusVisual(tester);
      final quill = quillOf(tester);
      // "Tweede" selecteren (platte tekst: offset 13 t/m 19).
      quill.updateSelection(
        const TextSelection(baseOffset: 13, extentOffset: 19),
        ChangeSource.local,
      );
      await tester.pump();
      await sendChord(tester, LogicalKeyboardKey.keyX);

      // Tussentijds typen terwijl setData hangt: de inhoud verandert.
      quill.replaceText(0, 0, 'X', null);
      await tester.pump();

      setDataGate.complete();
      await pumpUntil(
        tester,
        () => clipboardWrite != null,
        reason: 'de knip kwam nooit terug van het klembord',
      );
      // De gekopieerde selectie staat op het klembord, maar "Tweede" is
      // NIET gewist: de revisie klopte niet meer. De write-back van de
      // getypte 'X' normaliseert de afsluitende newline weg.
      await pumpUntil(
        tester,
        () =>
            notifier.currentState.document?.body ==
            'XEerste zin.\n\nTweede zin.',
        reason: 'de typepauze schreef niet terug',
      );
      expect(clipboardWrite, isNotNull);
    },
  );

  testWidgets('knip met trage setData zónder tussentijdse wijziging wist wel', (
    tester,
  ) async {
    setDataGate = Completer<void>();
    mockClipboard(tester);
    final notifier = await pumpEditor(tester);
    await focusVisual(tester);
    final quill = quillOf(tester);
    quill.updateSelection(
      const TextSelection(baseOffset: 13, extentOffset: 19),
      ChangeSource.local,
    );
    await tester.pump();
    await sendChord(tester, LogicalKeyboardKey.keyX);

    setDataGate.complete();
    await pumpUntil(
      tester,
      () => !(notifier.currentState.document?.body ?? '').contains('Tweede'),
      reason: 'de knip wiste de selectie niet',
    );
  });

  testWidgets('plak met trage getData + alleen caret-verplaatsing landt op de '
      'oorspronkelijke positie', (tester) async {
    getDataGate = Completer<void>();
    mockClipboard(tester, clipboardText: 'plak');
    final notifier = await pumpEditor(tester);
    await focusVisual(tester);
    final quill = quillOf(tester);
    // Caret midden in "zin" (offset 8).
    quill.updateSelection(
      const TextSelection.collapsed(offset: 8),
      ChangeSource.local,
    );
    await tester.pump();
    await sendChord(tester, LogicalKeyboardKey.keyV);

    // Verplaats de caret tijdens de klembordlezing — geen inhoudswijziging,
    // dus de vastgelegde positie blijft geldig.
    quill.updateSelection(
      const TextSelection.collapsed(offset: 24),
      ChangeSource.local,
    );
    await tester.pump();

    getDataGate.complete();
    await pumpUntil(
      tester,
      () =>
          notifier.currentState.document?.body ==
          'Eerste zplakin.\n\nTweede zin.',
      reason: 'de plak kwam nooit in het document terecht',
    );
  });

  testWidgets(
    'plak met trage getData + tussentijds typen plakt niet en meldt het',
    (tester) async {
      getDataGate = Completer<void>();
      mockClipboard(tester, clipboardText: 'plak');
      final notifier = await pumpEditor(tester);
      await focusVisual(tester);
      final quill = quillOf(tester);
      quill.updateSelection(
        const TextSelection.collapsed(offset: 8),
        ChangeSource.local,
      );
      await tester.pump();
      await sendChord(tester, LogicalKeyboardKey.keyV);

      // Tussentijds typen: de bestemming is niet meer dezelfde.
      quill.replaceText(0, 0, 'X', null);
      await tester.pump();

      getDataGate.complete();
      await pumpUntil(
        tester,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        reason: 'de verplaatsingsmelding verscheen niet',
      );

      // Niets geplakt, wel de melding dat de plek veranderde — en de 'X'
      // die er zelf bij kwam staat er nog (genormaliseerde afsluiter).
      expect(
        notifier.currentState.document!.body,
        'XEerste zin.\n\nTweede zin.',
      );
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets('plak in Bron met trage getData + tussentijds typen plakt niet', (
    tester,
  ) async {
    getDataGate = Completer<void>();
    mockClipboard(tester, clipboardText: 'plak');
    final notifier = await pumpEditor(tester);
    // Naar de bronstand — daar plakt _smartPaste via de bron-caret.
    await tester.tap(find.text('Bron'));
    await tester.pump();
    final source = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    source.selection = const TextSelection.collapsed(offset: 8);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await sendChord(tester, LogicalKeyboardKey.keyV);

    // Tussentijds typen in de bron: de bestemming is veranderd.
    await tester.enterText(
      find.byType(TextField).first,
      'XEerste zin.\n\nTweede zin.\n',
    );
    await tester.pump();

    getDataGate.complete();
    await pumpUntil(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'de verplaatsingsmelding verscheen niet',
    );
    expect(
      notifier.currentState.document!.body,
      'XEerste zin.\n\nTweede zin.\n',
    );
  });
}

/// Geen afbeelding op het testklembord.
class _NoClipboardImage extends ImageService {
  @override
  Future<ImageImportOutcome> pasteImageDetailed({String? projectPath}) async =>
      const ImageImportOutcome.failed(ImageImportFailure.noClipboardImage);
}
