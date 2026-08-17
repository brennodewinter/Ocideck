import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

/// Het formaat kent twee geforceerde pagina-einden en de export honoreert ze
/// allebei (FILE_FORMAT.md §14.6). De pagina-weergave verdeelde puur op hoogte
/// en zei daarmee iets anders dan de druk.
void main() {
  group('welke blokken een vers vel beginnen', () {
    test('een --- in de body is er een', () {
      const markdown = 'Eerste alinea.\n\n---\n\nTweede alinea.';
      expect(DocumentMarkdownView.forcedPageBreaks(markdown), contains(1));
    });

    test('een hoofdstuk alleen als de instelling aanstaat', () {
      const markdown = '# Een\n\nTekst.\n\n# Twee\n\nTekst.';
      expect(DocumentMarkdownView.forcedPageBreaks(markdown), isEmpty);
      final withSetting = DocumentMarkdownView.forcedPageBreaks(
        markdown,
        chapterBreak: true,
      );
      expect(withSetting, hasLength(1), reason: 'alleen het tweede hoofdstuk');
    });

    test('het eerste blok telt nooit mee', () {
      // Anders opent het document met een leeg vel.
      const markdown = '# Een hoofdstuk\n\nTekst.';
      expect(
        DocumentMarkdownView.forcedPageBreaks(markdown, chapterBreak: true),
        isEmpty,
      );
    });

    test('een tussenkop is geen hoofdstuk', () {
      const markdown = '# Een\n\nTekst.\n\n## Tussenkop\n\nTekst.';
      expect(
        DocumentMarkdownView.forcedPageBreaks(markdown, chapterBreak: true),
        isEmpty,
      );
    });
  });

  // De beeldkeuring vond deze twee: een document dat mét een `---` begon
  // opende met een leeg vel (alleen de streep), en op elk vers vel stond de
  // streep bovenaan afgedrukt.
  group('een pagina-einde laat geen leeg vel en geen inkt achter', () {
    test('een --- aan het begin levert geen leeg eerste vel op', () {
      const markdown = '---\n\n# Hoofdstuk\n\nTekst.\n';
      expect(
        DocumentMarkdownView.forcedPageBreaks(markdown, chapterBreak: true),
        isEmpty,
        reason: 'er staat vóór die kop niets dat een vel vult',
      );
    });

    test('twee streepjes achter elkaar leveren één einde op', () {
      const markdown = 'Tekst.\n\n---\n\n---\n\nMeer tekst.\n';
      expect(
        DocumentMarkdownView.forcedPageBreaks(markdown),
        hasLength(1),
        reason: 'de tweede streep breekt een vel af dat nog leeg is',
      );
    });

    test('een --- vlak vóór een hoofdstuk breekt maar één keer', () {
      const markdown = 'Tekst.\n\n---\n\n# Hoofdstuk\n\nMeer.\n';
      expect(
        DocumentMarkdownView.forcedPageBreaks(markdown, chapterBreak: true),
        hasLength(1),
      );
    });

    testWidgets('in de lezer blijft een --- gewoon een streep', (tester) async {
      // De keerzijde van `hideRules`, en die stond nergens vastgelegd: zet
      // iemand die vlag ooit standaard aan, dan verdwijnt de horizontale lijn
      // stil uit de documentatielezer zonder dat één test omvalt.
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: DocumentMarkdownView('Eerste.\n\n---\n\nTweede.\n'),
            ),
          ),
        ),
      );
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('de streep zelf wordt in de pagina-weergave niet getekend', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PagedDocumentView(
              markdown: 'Eerste.\n\n---\n\nTweede.\n',
              pageSize: PageSizeSpec.a4,
              margins: PageMargins(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Twee vellen, en geen Divider: het einde is het einde, niet ook een lijn.
      expect(find.byKey(const Key('document-sheet')).evaluate().length, 2);
      expect(find.byType(Divider), findsNothing);
    });
  });

  testWidgets('een --- levert een tweede vel op, hoe kort de tekst ook is', (
    tester,
  ) async {
    const markdown = 'Kort.\n\n---\n\nOok kort.';
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: markdown,
            pageSize: PageSizeSpec.a4,
            margins: PageMargins(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sheets = find.byKey(const Key('document-sheet')).evaluate().length;
    expect(
      sheets,
      2,
      reason: 'twee alinea\'s met een pagina-einde ertussen zijn twee vellen',
    );
  });
}
