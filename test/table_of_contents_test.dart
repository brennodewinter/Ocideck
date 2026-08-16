import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/table_of_contents.dart';

/// Feature 4: de inhoudsopgave-service — TOC genereren uit koppen, marker
/// vervangen, en marker strippen. Puur headless, testbaar.
void main() {
  group('generateTocMarkdown', () {
    test('genereert een GFM-lijst uit H1–H3', () {
      const body =
          '# Inleiding\n\n## Achtergrond\n\n## Methode\n\n### Detail\n\n# Conclusie\n';
      final toc = generateTocMarkdown(body);
      expect(toc, contains('- [Inleiding](#inleiding)'));
      expect(toc, contains('  - [Achtergrond](#achtergrond)'));
      expect(toc, contains('  - [Methode](#methode)'));
      expect(toc, contains('    - [Detail](#detail)'));
      expect(toc, contains('- [Conclusie](#conclusie)'));
    });

    test('maxDepth=2 laat H3 weg', () {
      const body = '# H1\n\n## H2\n\n### H3\n';
      final toc = generateTocMarkdown(body, maxDepth: 2);
      expect(toc, contains('- [H1](#h1)'));
      expect(toc, contains('  - [H2](#h2)'));
      expect(toc, isNot(contains('H3')));
    });

    test('geen koppen → lege string', () {
      expect(generateTocMarkdown('Gewoon een alinea.\n\nMeer tekst.'), '');
    });

    test('slug: spaties → streepjes, leestekens gestript', () {
      const body = '# Hallo, Wereld!\n';
      final toc = generateTocMarkdown(body);
      expect(toc, contains('- [Hallo, Wereld!](#hallo-wereld)'));
    });

    test('slug: Nederlandse diakritenen blijven behouden (\\w)', () {
      const body = '# Overzicht van koffie\n';
      final toc = generateTocMarkdown(body);
      expect(toc, contains('[Overzicht van koffie](#overzicht-van-koffie)'));
    });
  });

  group('replaceTocMarker', () {
    test('vervangt marker door marker + verse TOC', () {
      const body = '<!-- toc -->\n\n# Inleiding\n\n## Achtergrond\n';
      final toc = generateTocMarkdown(body);
      final result = replaceTocMarker(body, toc);
      expect(result, contains('<!-- toc -->'));
      expect(result, contains('- [Inleiding](#inleiding)'));
      expect(result, contains('  - [Achtergrond](#achtergrond)'));
    });

    test('geen marker → body ongewijzigd', () {
      const body = '# Inleiding\n\nGeen marker hier.\n';
      expect(replaceTocMarker(body, 'irrelevant'), body);
    });

    test('lege TOC → alleen marker blijft', () {
      const body = '<!-- toc -->\n\nGeen koppen hier.\n';
      final result = replaceTocMarker(body, '');
      expect(result, contains('<!-- toc -->'));
      expect(result, isNot(contains('- [')));
    });

    test('keepMarker: false houdt de TOC op zijn plek, zonder marker', () {
      const body = '# Titel\n\n<!-- toc -->\n\n## Een\n\n## Twee\n';
      final result = replaceTocMarker(
        body,
        generateTocMarkdown(body),
        keepMarker: false,
      );
      expect(result, isNot(contains('<!-- toc -->')));
      // Op de plek van de marker — ná de titel, vóór de eerste kop.
      expect(
        result.indexOf('- [Een](#een)'),
        greaterThan(result.indexOf('# Titel')),
      );
      expect(
        result.indexOf('- [Een](#een)'),
        lessThan(result.indexOf('## Een')),
      );
    });

    test('keepMarker: false zonder koppen laat geen kale marker achter', () {
      // De .md-export lekte hier een letterlijke `<!-- toc -->` het bestand in.
      const body = '<!-- toc -->\n\nGeen koppen hier.\n';
      final result = replaceTocMarker(body, '', keepMarker: false);
      expect(result, isNot(contains('<!-- toc -->')));
      expect(result.trim(), 'Geen koppen hier.');
    });

    test('vervangt een bestaande TOC onder de marker door een verse', () {
      const body = '<!-- toc -->\n\n- [Oud](#oud)\n\n# Nieuw\n';
      final toc = generateTocMarkdown(body);
      final result = replaceTocMarker(body, toc);
      expect(result, contains('- [Nieuw](#nieuw)'));
      expect(result, isNot(contains('- [Oud](#oud)')));
    });
  });

  group('hasTocMarker', () {
    test('true wanneer marker op eigen regel', () {
      expect(hasTocMarker('<!-- toc -->\n\n# H1\n'), isTrue);
    });

    test('false zonder marker', () {
      expect(hasTocMarker('# H1\n\nTekst\n'), isFalse);
    });

    test('false wanneer marker inline in tekst', () {
      // De marker moet op een eigen regel staan.
      expect(hasTocMarker('Tekst <!-- toc --> meer\n'), isFalse);
    });
  });

  group('stripTocMarker', () {
    test('verwijdert marker en gegenereerde TOC', () {
      const body =
          '<!-- toc -->\n\n- [H1](#h1)\n  - [H2](#h2)\n\n# H1\n\n## H2\n';
      final result = stripTocMarker(body);
      expect(result, isNot(contains('<!-- toc -->')));
      expect(result, isNot(contains('[H1](#h1)')));
      // Óók de ingesprongen regel. Deze test bevatte 'm al in de invoer maar
      // toetste alleen de H1-regel; de strip-regex accepteerde geen inspringing
      // en liet `  - [H2](#h2)` als los lijstitem in het document achter.
      expect(
        result,
        isNot(contains('[H2](#h2)')),
        reason: 'een geneste TOC-regel hoort net zo goed weg te zijn',
      );
      expect(result, startsWith('# H1'));
      expect(result, contains('## H2'));
    });

    test('een diepe TOC (H1–H3) laat niets achter', () {
      const body =
          '<!-- toc -->\n\n'
          '- [Een](#een)\n  - [Twee](#twee)\n    - [Drie](#drie)\n\n'
          '# Een\n\n## Twee\n\n### Drie\n';
      expect(stripTocMarker(body), '# Een\n\n## Twee\n\n### Drie\n');
    });

    test('geen marker → body ongewijzigd (behalve trimLeft)', () {
      const body = '# H1\n\nTekst\n';
      expect(stripTocMarker(body), body);
    });
  });
}
