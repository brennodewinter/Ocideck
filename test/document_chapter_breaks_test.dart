import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

/// "Hoofdstukafbrekingen toepassen" is een eenmalige bewerking van de body: hij
/// zet een `---` vóór elke `H1` behalve de eerste, zodat het pagina-einde in het
/// bestand staat (FILE_FORMAT.md §14.6) en niet in een app-instelling. De hele
/// logica is puur in [applyChapterPageBreaks] en wordt hier los getoetst; de
/// knop in het invoeg-palet leunt daarop.
void main() {
  group('applyChapterPageBreaks', () {
    test('zet een breuk vóór elke H1 behalve de eerste', () {
      const body = '# Een\n\nAlfa\n\n# Twee\n\nBeta\n\n# Drie\n';
      expect(
        applyChapterPageBreaks(body),
        '# Een\n\nAlfa\n\n---\n\n# Twee\n\nBeta\n\n---\n\n# Drie\n',
      );
    });

    test('idempotent: twee keer toepassen geeft geen dubbele breuk', () {
      const body = '# Een\n\nAlfa\n\n# Twee\n';
      final once = applyChapterPageBreaks(body);
      expect(applyChapterPageBreaks(once), once);
    });

    test('een bestaande `---` vóór de kop laat de body byte-getrouw', () {
      const body = '# Een\n\nAlfa\n\n---\n\n# Twee\n';
      expect(applyChapterPageBreaks(body), body);
    });

    test('een bestaande `***`-breuk telt óók als pagina-einde', () {
      const body = '# Een\n\nAlfa\n\n***\n\n# Twee\n';
      expect(applyChapterPageBreaks(body), body);
    });

    test('document zonder koppen blijft ongemoeid', () {
      const body = 'Alfa\n\nBeta\n';
      expect(applyChapterPageBreaks(body), body);
    });

    test('document met één kop blijft ongemoeid — geen leeg eerste vel', () {
      const body = '# Een\n\nAlfa\n';
      expect(applyChapterPageBreaks(body), body);
    });

    test('leeg document blijft leeg', () {
      expect(applyChapterPageBreaks(''), '');
    });

    test('diepere koppen (H2/H3) krijgen geen breuk', () {
      const body = '# Een\n\n## Twee\n\n### Drie\n';
      expect(applyChapterPageBreaks(body), body);
    });

    test('een `#` binnen een codeblok is geen hoofdstukkop', () {
      const body = '# Een\n\n```sh\n# dit is een commentaarregel\n```\n';
      expect(applyChapterPageBreaks(body), body);
    });

    test('een `---` binnen een codeblok is geen bestaande breuk', () {
      const body = '# Een\n\n```yaml\n---\nkey: waarde\n```\n\n# Twee\n';
      final next = applyChapterPageBreaks(body);
      // De fence blijft heel; de breuk komt eronder, vóór de tweede kop.
      expect(
        next,
        '# Een\n\n```yaml\n---\nkey: waarde\n```\n\n---\n\n# Twee\n',
      );
      expect(applyChapterPageBreaks(next), next);
    });

    test('een `---` binnen een codeblok vlak vóór de kop telt niet mee', () {
      // De laatste niet-lege regel vóór de kop is de sluit-fence, niet de `---`.
      const body = '# Een\n\n~~~\n---\n~~~\n# Twee\n';
      final next = applyChapterPageBreaks(body);
      expect(next, '# Een\n\n~~~\n---\n~~~\n\n---\n\n# Twee\n');
    });

    test('een kop zonder lege regel ervoor krijgt er één, geen setext-H2', () {
      const body = '# Een\nAlfa\n# Twee\n';
      // Zonder de lege regel zou `Alfa\n---` een setext-kop worden in plaats
      // van een breuk.
      expect(applyChapterPageBreaks(body), '# Een\nAlfa\n\n---\n\n# Twee\n');
    });

    test('de frontmatter blijft buiten schot', () {
      const source = '---\ntheme: Zakelijk\n---\n\n# Een\n\nAlfa\n\n# Twee\n';
      final doc = MarkdownDocument.parse(source);
      final next = doc.frontMatter + applyChapterPageBreaks(doc.body);
      expect(next.startsWith('---\ntheme: Zakelijk\n---\n'), isTrue);
      expect(next, contains('Alfa\n\n---\n\n# Twee'));
      // Precies twee `---`-regels van de frontmatter plus de ene nieuwe breuk.
      expect(next.split('\n').where((l) => l.trim() == '---').length, 3);
    });
  });
}
