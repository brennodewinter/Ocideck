import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/utils/markdown_caret_map.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

/// Wisselen tussen Visueel en Bron laat je staan waar je stond (#1566).
///
/// De kaart wordt niet tegen zelfbedachte getallen getoetst maar tegen de
/// échte platte tekst van de visuele editor: wat de omzetting oplevert, is
/// waar de cursor heen moet.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const bron =
      '# Kop\n'
      '\n'
      'Alinea met **vet** en `code` erin.\n'
      '\n'
      '- een\n'
      '- twee\n'
      '\n'
      '| A | B |\n'
      '| --- | --- |\n'
      '| 1 | 2 |\n'
      '\n'
      'Slot van het stuk.\n';

  group('MarkdownCaretMap volgt de echte omzetting', () {
    final plat = MarkdownQuillCodec.documentFromMarkdown(bron).toPlainText();
    final kaart = MarkdownCaretMap.of(bron);

    for (final woord in [
      'Kop',
      'Alinea',
      'vet',
      'code',
      'een',
      'twee',
      'Slot',
    ]) {
      test('"$woord" staat aan beide kanten op dezelfde plek', () {
        final inBron = bron.indexOf(woord);
        final inPlat = plat.indexOf(woord);
        expect(inBron, isNonNegative);
        expect(inPlat, isNonNegative);
        expect(kaart.visualOffsetOf(inBron), inPlat);
        expect(kaart.sourceOffsetOf(inPlat), inBron);
      });
    }

    test('een tabel telt als één blok, geen zes regels', () {
      // De hele tabel is in de rijke-tekstlaag één embed; de tekst erna mag dus
      // niet vijf regels verschoven raken.
      expect(kaart.visualOffsetOf(bron.indexOf('Slot')), plat.indexOf('Slot'));
    });

    test('een positie voorbij het einde valt binnen de tekst', () {
      expect(
        kaart.visualOffsetOf(bron.length + 50),
        lessThanOrEqualTo(plat.length),
      );
      expect(
        kaart.sourceOffsetOf(plat.length + 50),
        lessThanOrEqualTo(bron.length),
      );
    });

    test('een leeg document geeft geen fout', () {
      final leeg = MarkdownCaretMap.of('');
      expect(leeg.visualOffsetOf(0), 0);
      expect(leeg.sourceOffsetOf(0), 0);
    });
  });

  Widget editorApp(DocumentNotifier n) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => n)],
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

  testWidgets('van Bron naar Visueel houdt de cursor zijn plek', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(bron));
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // De broneditor is het veld met de hele body erin.
    final veld = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere(
          (v) => (v.controller?.text ?? '').contains('Slot van het stuk'),
        );
    veld.controller!.selection = TextSelection.collapsed(
      offset: veld.controller!.text.indexOf('Slot'),
    );
    await tester.pump();

    await tester.tap(find.text('Visueel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final quill = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final plat = quill.controller.document.toPlainText();
    expect(quill.controller.selection.baseOffset, plat.indexOf('Slot'));
  });

  testWidgets('van Visueel naar Bron houdt de cursor zijn plek', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(bron));
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final quill = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final plat = quill.controller.document.toPlainText();
    quill.controller.updateSelection(
      TextSelection.collapsed(offset: plat.indexOf('Slot')),
      ChangeSource.local,
    );
    await tester.pump();

    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final veld = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere(
          (v) => (v.controller?.text ?? '').contains('Slot van het stuk'),
        );
    expect(
      veld.controller!.selection.baseOffset,
      veld.controller!.text.indexOf('Slot'),
    );
  });
}
