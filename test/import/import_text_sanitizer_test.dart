import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/utils/import_text_sanitizer.dart';
import 'package:ocideck/services/markdown_safety.dart';

/// De neutralisator aan de importgrens (#876). Het contract is toetsbaar tegen
/// de bestaande fail-closed poort: adversariële brontekst mag na sanitizing geen
/// uitvoerbare inhoud meer bevatten (`MarkdownSafetyScanner.isSafe`), en geen
/// Markdown-structuur meer kunnen vormen.
void main() {
  group('geen uitvoerbare inhoud meer (scanner als orakel)', () {
    // Precies de vectoren die MarkdownSafetyScanner afwijst.
    const dangerous = [
      '<script>alert(1)</script>',
      '<SCRIPT SRC=//evil>',
      '<foreignObject>',
      '<img src=x onerror=alert(1)>',
      '<iframe src="//evil"></iframe>',
      '<object data="x">',
      '<embed src="x">',
      '<applet code="x">',
      '<meta http-equiv="refresh">',
      '<base href="//evil">',
      '[klik](javascript:alert(1))',
      '[x](vbscript:msgbox)',
      '[x](data:text/html;base64,PHN2Zz4=)',
      '<javascript:alert(1)>',
      // entity- en zero-width-evasie
      '&#60;script&#62;alert(1)&#60;/script&#62;',
      'java​script:alert(1)',
    ];

    for (final input in dangerous) {
      test(
        'veilig na sanitizing: ${input.substring(0, input.length.clamp(0, 28))}',
        () {
          final out = sanitizeImportedText(input);
          expect(
            MarkdownSafetyScanner.scan(out),
            isEmpty,
            reason: 'gesanitiseerd "$out" mag de poort niet meer laten afgaan',
          );
        },
      );
    }
  });

  group('geen Markdown-structuur meer', () {
    test('regeleinden worden spaties (geen inbreken in een volgend blok)', () {
      expect(
        sanitizeImportedText('titel\n\n---\n\n# Ingebroken'),
        isNot(contains('\n')),
      );
    });

    test('een hele regel "---" wordt geen thematische breuk', () {
      final out = sanitizeImportedText('---');
      expect(out, r'\---');
    });

    test('een leidende kop wordt tekst', () {
      expect(sanitizeImportedText('# nep-kop'), r'\# nep-kop');
    });

    test('een leidende quote wordt tekst (via de HTML-escape)', () {
      // `>` wordt `&gt;`, wat als letterlijke `>` rendert — geen blockquote.
      expect(sanitizeImportedText('> citaat'), '&gt; citaat');
    });

    test('een leidende lijstmarkering wordt tekst', () {
      expect(sanitizeImportedText('- punt'), r'\- punt');
      expect(sanitizeImportedText('1. eerste'), r'1\. eerste');
    });

    test('afbeeldingssyntax vormt geen afbeelding', () {
      // `![alt](url)` -> het `[` is ontsnapt, dus geen afbeelding/link.
      final out = sanitizeImportedText('![alt](http://tracker/pixel.png)');
      expect(out, contains(r'\['));
      expect(out, isNot(contains('](')));
    });

    test('een tabel-pipe kan geen kolom openen midden in tekst', () {
      // Pipes blijven, maar de tekst is één regel en geen leidend blokteken —
      // binnen een bullet/quote is een pipe inert; alleen een leidende telt.
      expect(sanitizeImportedText('| a | b |'), r'\| a | b |');
    });
  });

  group('gewone tekst blijft leesbaar', () {
    test('proza met haakjes houdt zijn haakjes', () {
      expect(
        sanitizeImportedText('zie figuur (2) hiernaast'),
        'zie figuur (2) hiernaast',
      );
    });

    test('een gewone zin blijft ongewijzigd', () {
      expect(sanitizeImportedText('Kwartaalcijfers Q3'), 'Kwartaalcijfers Q3');
    });

    test('een minteken midden in tekst blijft staan', () {
      expect(
        sanitizeImportedText('kosten-baten analyse'),
        'kosten-baten analyse',
      );
    });
  });
}
