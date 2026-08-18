import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_paste_cleanup.dart';

/// Leidende witruimte van een regel, in tekens.
int _indentOf(String line) => line.length - line.trimLeft().length;

void main() {
  group('sanitizeMarkdownPaste houdt de structuur van een geplakte lijst', () {
    // #1556/#1560: een geneste opsomming die met dunne spaties was ingesprongen
    // kwam volledig plat binnen — alle items op het eerste niveau. Van alle
    // spatiesoorten was U+2009 de enige die sneuvelde, omdat hij op de lijst
    // "onzichtbare ruis van nieuwssites" stond. In de inspringing is hij geen
    // ruis maar de structuur.
    const spaceKinds = {
      'spatie U+0020': ' ',
      'NBSP U+00A0': ' ',
      'en space U+2002': ' ',
      'em space U+2003': ' ',
      'figure space U+2007': ' ',
      'dunne spatie U+2009': ' ',
      'narrow nbsp U+202F': ' ',
      'ideographic U+3000': '　',
    };

    for (final kind in spaceKinds.entries) {
      test('inspringing met ${kind.key} blijft staan', () {
        final pad = kind.value * 4;
        final out = sanitizeMarkdownPaste(
          '- Primary bullet level.\n'
          '$pad- Secondary bullet level.\n'
          '$pad$pad- A third bullet level.',
        );
        final lines = out.split('\n');
        expect(lines, hasLength(3));
        expect(_indentOf(lines[0]), 0);
        expect(_indentOf(lines[1]), 4, reason: '${kind.key}: niveau 2 kwijt');
        expect(_indentOf(lines[2]), 8, reason: '${kind.key}: niveau 3 kwijt');
      });
    }

    test('U+2028 en U+2029 gelden als regeleinde, niet als ruis', () {
      for (final sep in const [' ', ' ']) {
        final out = sanitizeMarkdownPaste(
          '- een$sep    - twee$sep        - drie',
        );
        expect(out.split('\n'), hasLength(3), reason: 'scheider $sep');
        expect(_indentOf(out.split('\n')[1]), 4);
      }
    });

    test('een dunne spatie midden in de regel verdwijnt nog steeds', () {
      expect(sanitizeMarkdownPaste('tien duizend'), 'tienduizend');
    });

    // #1561: trim() nam ook de inspringing van de eerste regel mee, dus een
    // selectie die midden in een geneste lijst begon kwam scheef binnen.
    test('een fragment dat ingesprongen begint houdt zijn inspringing', () {
      const src =
          '    - Secondary bullet level.\n'
          '    - Another secondary bullet level.\n'
          '        - A third bullet level.';
      expect(sanitizeMarkdownPaste(src), src);
    });

    test('lege regels aan begin en eind gaan er wel af', () {
      expect(sanitizeMarkdownPaste('\n\n  - een\n\n'), '  - een');
    });
  });
}
