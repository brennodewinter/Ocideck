import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';

void main() {
  group('withBody (#1682)', () {
    test('behoudt frontmatter bij normale body', () {
      final doc = MarkdownDocument.parse(
        '---\ntlp: red\n---\n\n# Oorspronkelijk\n',
      );
      final next = doc.withBody('# Vervangen\n');
      expect(next.frontMatter, '---\ntlp: red\n---\n\n');
      expect(next.body, '# Vervangen\n');
      expect(next.source, '---\ntlp: red\n---\n\n# Vervangen\n');
    });

    test('body die opent met --- wordt niet als frontmatter gelezen', () {
      // Een document mét frontmatter: de --- in de body is een pagina-einde,
      // geen nieuw frontmatter-blok.
      final doc = MarkdownDocument.parse(
        '---\ntlp: red\n---\n\n# Oorspronkelijk\n',
      );
      final next = doc.withBody('---\n\n# Nieuwe pagina\n');
      expect(next.frontMatter, '---\ntlp: red\n---\n\n');
      // De body begint met --- (pagina-einde), niet met frontmatter.
      expect(next.body, '---\n\n# Nieuwe pagina\n');
    });

    test('document zonder frontmatter: body met --- krijgt juiste metadata', () {
      // Een document zónder frontmatter. De body opent met een --- blok.
      // Vóór de fix werd de oude (lege) metadata hergebruikt, zodat body
      // het hele source terug gaf (inclusief het --- blok) en frontMatter
      // leeg bleef — terwijl splitDocumentFrontMatter het --- blok als
      // frontmatter leest (#1682).
      final doc = MarkdownDocument.parse('# Oorspronkelijk\n');
      expect(doc.frontMatter, '');

      // Vervang de body door een tekst die met --- opent.
      final next = doc.withBody('---\ntitle: Test\n---\n\nContent\n');
      // De metadata wordt nu opnieuw geparseerd: het --- blok is frontmatter.
      expect(next.frontMatter, '---\ntitle: Test\n---\n\n');
      expect(next.body, 'Content\n');
    });

    test('document zonder frontmatter: normale body blijft zonder frontmatter', () {
      final doc = MarkdownDocument.parse('# Oorspronkelijk\n');
      final next = doc.withBody('# Vervangen\n');
      expect(next.frontMatter, '');
      expect(next.body, '# Vervangen\n');
      expect(next.source, '# Vervangen\n');
    });
  });
}
