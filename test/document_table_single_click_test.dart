import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_l10n;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

// Eén klik tussen een tabelcel en de aangrenzende tekst moet volstaan.
// De muisklik wordt als echte down/up gesplitst met frames ertussen: het
// verdwijnen of verschijnen van de tabelwerkbalk verschuift dan zichtbaar
// wat er onder de aanwijzer ligt — precies waar de gemelde dubbelklik uit
// voortkwam.

void main() {
  const document = '''
# Rapport

Boven de tabel.

| Naam | Waarde |
| --- | --- |
| Appel | Banaan |

Onder de tabel.
''';

  Future<QuillEditor> pumpEditor(
    WidgetTester tester, [
    String source = document,
  ]) async {
    final notifier = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse(source));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentProvider.overrideWith((_) => notifier)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            flutter_l10n.GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DocumentEditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return tester.widget<QuillEditor>(find.byType(QuillEditor));
  }

  // Een echte klik: de werkbalk kan tussen down en up van plek wisselen.
  Future<void> realClick(WidgetTester tester, Offset where) async {
    final gesture = await tester.startGesture(
      where,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();
    // Ruim langer dan Quills dubbeltik-timer (300 ms), anders blijft die
    // aan het einde van de test als loslopende timer achter.
    await tester.pump(const Duration(milliseconds: 400));
  }

  // De schermpositie van een documentpositie in de Quill-tekst.
  Offset globalOffsetOf(WidgetTester tester, int documentOffset) {
    final editor = tester.state<EditorState>(find.byType(QuillRawEditor));
    final points = editor.renderEditor.getEndpointsForSelection(
      TextSelection(baseOffset: documentOffset, extentOffset: documentOffset),
    );
    return editor.renderEditor.localToGlobal(points.first.point);
  }

  testWidgets('cel naar tekst eronder: één klik plaatst de caret', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1300, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AppLocalizations.setActiveLanguageCode('nl');
    final quill = await pumpEditor(tester);

    // Eerst de cel activeren: de werkbalk staat er dan boven.
    final cell = find.widgetWithText(TextField, 'Appel');
    await realClick(tester, tester.getCenter(cell));
    expect(
      tester.widget<TextField>(cell).focusNode!.hasPrimaryFocus,
      isTrue,
      reason: 'de eerste klik op de cel moet hem al focussen',
    );
    // De werkbalk staat er zichtbaar bij.
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(QuillRawEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final scrolled = scrollable.position.pixels;

    // Nu één klik op de tekst eronder.
    final docText = quill.controller.document.toPlainText();
    final belowStart = docText.indexOf('Onder de tabel.');
    expect(belowStart, isNonNegative);
    await realClick(
      tester,
      globalOffsetOf(tester, belowStart + 'Onder de tabel.'.length),
    );

    expect(quill.focusNode.hasFocus, isTrue);
    expect(
      quill.controller.selection.extentOffset,
      inInclusiveRange(belowStart, belowStart + 'Onder de tabel.'.length),
    );
    // De werkbalk is weg zodra de cel geen focus meer heeft.
    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
    // De zichtbare scrollpositie sprong niet weg.
    expect(scrollable.position.pixels, closeTo(scrolled, 2));
    // Direct typen moet daar landen: de IME-waarde met het teken op de
    // caretpositie is wat het toetsenbord bij een echte aanslag stuurt.
    final caret = quill.controller.selection.extentOffset;
    final typed = docText.replaceRange(caret, caret, '!');
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
    await tester.pump();
    expect(
      quill.controller.document.toPlainText(),
      contains('Onder de tabel.!'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tekst erboven naar cel: één klik focust de cel', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1300, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AppLocalizations.setActiveLanguageCode('nl');
    final quill = await pumpEditor(tester);

    // Eerst de caret in de tekst boven de tabel.
    final docText = quill.controller.document.toPlainText();
    final aboveStart = docText.indexOf('Boven de tabel.');
    expect(aboveStart, isNonNegative);
    await realClick(tester, globalOffsetOf(tester, aboveStart + 4));
    expect(quill.focusNode.hasFocus, isTrue);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);

    // Nu één klik op de cel. In bewerkbare toestand is het veld geen
    // `widgetWithText`-match meer, dus focus en controller gaan vooraf mee.
    final cell = find.widgetWithText(TextField, 'Appel');
    final cellFocus = tester.widget<TextField>(cell).focusNode!;
    final cellController = tester.widget<TextField>(cell).controller!;
    await realClick(tester, tester.getCenter(cell));
    expect(cellFocus.hasPrimaryFocus, isTrue);
    // De werkbalk verschijnt bij de actieve cel.
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    tester.testTextInput.enterText('X');
    await tester.pump();
    expect(cellController.text, 'X');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tabel aan het documenteinde: één klik heen en terug', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1300, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AppLocalizations.setActiveLanguageCode('nl');
    final quill = await pumpEditor(tester, '''
| Naam | Waarde |
| --- | --- |
| Appel | Banaan |

Slotregel.
''');

    // Tabel aan het documentbegin: eerst de cel, dan de slotregel.
    final cell = find.widgetWithText(TextField, 'Appel');
    await realClick(tester, tester.getCenter(cell));
    expect(tester.widget<TextField>(cell).focusNode!.hasPrimaryFocus, isTrue);

    final docText = quill.controller.document.toPlainText();
    final endStart = docText.indexOf('Slotregel.');
    expect(endStart, isNonNegative);
    await realClick(
      tester,
      globalOffsetOf(tester, endStart + 'Slotregel.'.length),
    );
    expect(quill.focusNode.hasFocus, isTrue);
    expect(
      quill.controller.selection.extentOffset,
      inInclusiveRange(endStart, endStart + 'Slotregel.'.length),
    );
    final caret = quill.controller.selection.extentOffset;
    final typed = docText.replaceRange(caret, caret, '!');
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
    await tester.pump();
    expect(quill.controller.document.toPlainText(), contains('Slotregel.!'));
    debugDefaultTargetPlatformOverride = null;
  });
}
