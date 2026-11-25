import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/docx/markdown_to_docx.dart';
import 'package:ocideck/services/epub/markdown_to_xhtml.dart';
import 'package:ocideck/services/latex/markdown_to_latex.dart';
import 'package:ocideck/services/odt/markdown_to_odt.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/markdown_to_pdf_blocks.dart';
import 'package:ocideck/services/plain_document_table.dart';

void main() {
  const source =
      '''
$plainDocumentTableMarker
| Naam | Functie |
| --- | ---: |
| Ada | Voorzitter |

| Onderwerp | Status |
| --- | --- |
| Plan | Gereed |
''';

  test(
    'PDF bewaart uitlijning en geeft alleen de gewone tabel een kopstijl',
    () {
      final tables = markdownToPdfBlocks(
        source,
      ).whereType<PdfTableBlock>().toList();
      expect(tables.map((table) => table.plain), [true, false]);
      expect(tables.first.alignments!.last, PdfColumnAlignment.right);
      expect(tables.first.rows.first.first.single.bold, isFalse);
      expect(tables.last.rows.first.first.single.bold, isTrue);
    },
  );

  test('LaTeX laat het blanco raster de tekststijl erven', () {
    final latex = markdownToLatex(
      source,
      tableTheme: const ThemeProfile(tableAccentHeaderBorder: true),
    );
    final plain = latex.substring(0, latex.indexOf(r'\end{tabularx}'));
    expect(
      plain,
      contains(
        r'\begin{tabularx}{\linewidth}{@{}>{\raggedright\arraybackslash}X>{\raggedleft\arraybackslash}X@{}}',
      ),
    );
    expect(plain, contains('Naam & Functie'));
    expect(plain, isNot(contains(r'\textbf')));
    expect(plain, isNot(contains(r'\hline')));
    expect(plain, isNot(contains(r'\cellcolor')));
    expect(latex.substring(plain.length), contains(r'\cellcolor'));
  });

  test(
    'Word, LibreOffice en EPUB krijgen een blanco tabel naast een gewone',
    () {
      final docx = markdownToDocxBody(source, tableHeaderFill: '0000FF').body;
      final wordTables = docx.split('</w:tbl>');
      expect(wordTables.first, contains('<w:top w:val="nil"/>'));
      expect(wordTables.first, contains('<w:pStyle w:val="Normal"/>'));
      expect(wordTables.first, isNot(contains('<w:shd')));
      expect(wordTables[1], contains('<w:shd'));
      final odt = markdownToOdtBody(source).body.split('</table:table>');
      expect(odt.first, isNot(contains('Table_Header_Cell')));
      expect(odt[1], contains('Table_Header_Cell'));
      final epub = markdownToXhtml(source);
      expect(epub, contains('<table class="ocideck-plain-table">'));
      expect(epub, contains('<table>'));
    },
  );
}
