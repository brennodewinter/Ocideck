import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

/// Wisselen tussen Visueel en Bron brengt je plek ook *in beeld* (#2322).
///
/// `document_caret_across_modes_test.dart` bewijst de logische cursorpositie;
/// deze toets bewijst de viewport: de doelstand mag niet bovenaan openen als
/// de caret of het eerste zichtbare blok diep in het document zit.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  // Lang genoeg dat elke stand ruim buiten beeld kan scrollen. De diepe
  // markering staat ver onder de eerste viewport.
  final bron =
      '${'# Kop\n\n'}${List.generate(60, (i) => 'Alinea ${i + 1} met wat tekst eromheen.').join('\n\n')}\n\nSlot van het stuk.\n';

  Widget editorApp(DocumentNotifier n) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => n)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  Future<DocumentNotifier> openEditor(
    WidgetTester tester, {
    String body = '',
  }) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse(body.isEmpty ? bron : body));
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return n;
  }

  /// Het bron-tekstveld: het enige TextField met de hele body erin.
  TextField bronVeld(WidgetTester tester) => tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere(
        (v) => (v.controller?.text ?? '').contains('Slot van het stuk'),
      );

  testWidgets('van Bron naar Visueel toont de caretregel, niet de top', (
    tester,
  ) async {
    final n = await openEditor(tester);
    final source = n.state.document!.source;

    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final veld = bronVeld(tester);
    veld.controller!.selection = TextSelection.collapsed(
      offset: veld.controller!.text.indexOf('Alinea 45'),
    );
    await tester.pump();

    await tester.tap(find.text('Visueel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final quill = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final plat = quill.controller.document.toPlainText();
    expect(
      quill.controller.selection.baseOffset,
      plat.indexOf('Alinea 45'),
      reason: 'de caret hoort bij dezelfde alinea',
    );
    expect(
      quill.scrollController.offset,
      greaterThan(0),
      reason: 'de visuele stand opent op de caret, niet bovenaan',
    );
    // Wisselen is geen bewerking: de bron blijft byte-getrouw gelijk.
    expect(n.state.document!.source, source);
  });

  testWidgets('van Visueel naar Bron toont de caretregel, niet de top', (
    tester,
  ) async {
    final n = await openEditor(tester);
    final source = n.state.document!.source;

    final quill = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final plat = quill.controller.document.toPlainText();
    quill.controller.updateSelection(
      TextSelection.collapsed(offset: plat.indexOf('Alinea 45')),
      ChangeSource.local,
    );
    await tester.pump();

    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final veld = bronVeld(tester);
    expect(
      veld.controller!.selection.baseOffset,
      veld.controller!.text.indexOf('Alinea 45'),
      reason: 'de caret hoort bij dezelfde alinea',
    );
    expect(
      veld.scrollController!.offset,
      greaterThan(0),
      reason: 'de bronstand opent op de caretregel, niet bovenaan',
    );
    expect(n.state.document!.source, source);
  });

  testWidgets('alleen scrollen in Bron houdt het zichtbare blok bij Visueel', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Cursor blijft bovenaan staan; de gebruiker scrollt naar het midden.
    final veld = bronVeld(tester);
    veld.controller!.selection = const TextSelection.collapsed(offset: 0);
    veld.scrollController!.jumpTo(
      veld.scrollController!.position.maxScrollExtent / 2,
    );
    await tester.pump();

    await tester.tap(find.text('Visueel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final quill = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(
      quill.scrollController.offset,
      greaterThan(0),
      reason:
          'zonder verplaatste caret geldt het eerste zichtbare blok als anker',
    );
  });

  testWidgets('alleen scrollen in Visueel houdt het zichtbare blok bij Bron', (
    tester,
  ) async {
    await openEditor(tester);

    // Cursor bovenaan, scroll naar het midden van de visuele stand.
    final quill = tester.widget<QuillEditor>(find.byType(QuillEditor));
    quill.scrollController.jumpTo(
      quill.scrollController.position.maxScrollExtent / 2,
    );
    await tester.pump();

    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final veld = bronVeld(tester);
    expect(
      veld.scrollController!.offset,
      greaterThan(0),
      reason:
          'zonder verplaatste caret geldt het eerste zichtbare blok als anker',
    );
  });

  testWidgets('de Bron-fallback brengt de probleemregel in beeld', (
    tester,
  ) async {
    // Een niet-verliesvrije constructie diep in het document: bij het openen
    // staat de stand al op Bron, de knop Visueel triggert de fallback die de
    // probleemregel aanwijst.
    final fout =
        '${'# Kop\n\n'}${List.generate(50, (i) => 'Alinea ${i + 1} met wat tekst eromheen.').join('\n\n')}\n\n<!-- verborgen -->\n\nSlot van het stuk.\n';
    await openEditor(tester, body: fout);

    await tester.tap(find.text('Visueel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // De stand blijft Bron en de probleemregel is in beeld gescrold.
    final veld = bronVeld(tester);
    expect(
      veld.controller!.selection.baseOffset,
      veld.controller!.text.indexOf('<!-- verborgen -->'),
      reason: 'de caret wijst de probleemregel aan',
    );
    expect(
      veld.scrollController!.offset,
      greaterThan(0),
      reason: 'de probleemregel ligt in de viewport, niet bovenaan',
    );
  });
}
