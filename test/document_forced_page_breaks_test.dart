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
