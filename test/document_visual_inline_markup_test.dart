import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/utils/inline_markdown.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';

/// Opmaak in de **visuele** stand ziet eruit zoals in het voorbeeld bij de bron
/// (#1567): een tabelcel waar je niet in staat toont `**vet**` als vet, en
/// `` `code` `` staat op hetzelfde vlakje als in het schrijfvlak.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

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

  /// Alle tekststukken met hun opmaak uit de opgemaakte tekst onder [of].
  List<TextSpan> stukken(WidgetTester tester, Finder of) {
    final spans = <TextSpan>[];
    for (final rich in tester.widgetList<RichText>(
      find.descendant(of: of, matching: find.byType(RichText)),
    )) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').isNotEmpty) spans.add(span);
        return true;
      });
    }
    return spans;
  }

  testWidgets('Markdown in een tabelcel wordt in de visuele stand opgemaakt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n'
          '| Naam | Waarde |\n| --- | --- |\n| **Alfa** | `code` |\n',
        ),
      );
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final inTabel = stukken(tester, find.byType(Table));
    // De sterretjes staan niet meer als tekens in de cel...
    expect(
      inTabel.map((s) => s.text).where((t) => t!.contains('**')),
      isEmpty,
      reason: 'de opmaaktekens horen opmaak te zijn, geen tekst',
    );
    // ...maar het woord staat er wél, en het is vet.
    final vet = inTabel.firstWhere((s) => s.text == 'Alfa');
    expect(vet.style?.fontWeight, FontWeight.bold);
    // En de codecel staat op het codevlakje, net als in het schrijfvlak.
    final code = inTabel.firstWhere((s) => s.text == 'code');
    expect(code.style?.fontFamily, 'monospace');
    expect(code.style?.backgroundColor, isNotNull);
  });

  testWidgets('de cel waar je in klikt toont zijn Markdown om te bewerken', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n| Naam |\n| --- |\n| **Alfa** |\n',
        ),
      );
    await tester.pumpWidget(editorApp(n));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Het veld draagt de bron van de cel: wat je bewerkt is Markdown.
    final veld = find.widgetWithText(TextField, '**Alfa**');
    expect(veld, findsOneWidget);
    await tester.showKeyboard(veld);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Nu je erin staat, ligt de opgemaakte lezing van díe cel er niet meer
    // overheen — je ziet en bewerkt de tekens zelf.
    expect(
      stukken(tester, find.byType(Table)).map((s) => s.text),
      isNot(contains('Alfa')),
      reason: 'de opgemaakte laag hoort weg te zijn in de cel die je bewerkt',
    );
  });

  group('inline code', () {
    test('krijgt een achtergrond wanneer het oppervlak er een geeft', () {
      final runs = parseInlineRuns('een `stukje tekst` erin');
      final code = runs.firstWhere((r) => r.code);
      const basis = TextStyle(fontSize: 14);
      expect(
        inlineRunStyle(code, basis, null).backgroundColor,
        isNull,
        reason: 'een dia houdt zijn kale monospace',
      );
      expect(
        inlineRunStyle(
          code,
          basis,
          null,
          codeBackground: const Color(0xFFEEEEEE),
        ).backgroundColor,
        const Color(0xFFEEEEEE),
      );
    });

    testWidgets('de documentweergave geeft hem mee', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DocumentMarkdownView('Een `stukje tekst` in een zin.\n'),
          ),
        ),
      );
      await tester.pump();
      final tekst = tester.widget<InlineMarkdownText>(
        find.byType(InlineMarkdownText).first,
      );
      expect(tekst.codeBackground, isNotNull);
    });
  });
}
