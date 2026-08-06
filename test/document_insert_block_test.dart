import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

/// Het invoeg-palet in de documentmodus (DOCUMENT_MODE.md §4) schrijft een verse
/// Markdown-constructie op de cursorpositie in de bron. De omhulling met lege
/// regels — zodat het blok een eigen alinea wordt zonder ooit méér dan één
/// dubbele witregel te maken — is puur in [insertBlockIntoSource] en wordt hier
/// los, uitputtend getoetst; de widgetbedrading leunt daarop.
void main() {
  group('insertBlockIntoSource', () {
    test('leeg document: geen leidende witregels, sluit af met een newline', () {
      final (next, cursor) = insertBlockIntoSource('', 0, 0, 'BLOK');
      expect(next, 'BLOK\n');
      // Cursor staat ná het ingevoegde blok (inclusief de afsluitende newline).
      expect(cursor, next.length);
    });

    test('geen selectie (-1): voegt achteraan in', () {
      final (next, _) = insertBlockIntoSource('# Kop\n', -1, -1, 'BLOK');
      expect(next, '# Kop\n\nBLOK\n');
    });

    test('cursor midden in de tekst: dubbele witregel ervoor en erna', () {
      const source = 'Alfa\n\nBeta';
      // Cursor tussen de twee alinea's, direct ná de dubbele newline.
      final (next, cursor) = insertBlockIntoSource(source, 6, 6, 'BLOK');
      expect(next, 'Alfa\n\nBLOK\n\nBeta');
      // Cursor staat op de lege regel ná het blok, klaar om verder te typen.
      expect(next.substring(0, cursor), 'Alfa\n\nBLOK\n\n');
    });

    test('cursor direct na tekst zonder newline: vult aan tot dubbele witregel', () {
      final (next, _) = insertBlockIntoSource('Alfa', 4, 4, 'BLOK');
      expect(next, 'Alfa\n\nBLOK\n');
    });

    test('bestaande dubbele witregel wordt niet verdubbeld', () {
      // Ervoor staat al `\n\n`; erna begint al met `\n` → geen extra witregels.
      final (next, _) = insertBlockIntoSource('Alfa\n\n', 6, 6, 'BLOK');
      expect(next, 'Alfa\n\nBLOK\n');
    });

    test('een selectie wordt vervangen door het blok', () {
      const source = 'Alfa OUD Beta';
      // Selecteer "OUD" (index 5..8).
      final (next, _) = insertBlockIntoSource(source, 5, 8, 'BLOK');
      expect(next, contains('BLOK'));
      expect(next, isNot(contains('OUD')));
    });

    test('omgekeerde selectie (start > end) wordt genormaliseerd', () {
      const source = 'Alfa OUD Beta';
      final (a, _) = insertBlockIntoSource(source, 8, 5, 'BLOK');
      final (b, _) = insertBlockIntoSource(source, 5, 8, 'BLOK');
      expect(a, b);
    });
  });
}
