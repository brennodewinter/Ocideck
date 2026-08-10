import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/front_matter_merge.dart';

/// De regelbewerking op zichzelf: geen deck, geen markdown, alleen de vraag of
/// een onbekende regel exact blijft staan waar hij stond.
void main() {
  group('frontMatterKeyOf', () {
    test('herkent een sleutel op kolom 0, met en zonder waarde', () {
      expect(frontMatterKeyOf('theme: ocideck'), 'theme');
      expect(frontMatterKeyOf('style:'), 'style');
      expect(
        frontMatterKeyOf('ocideck_seal_at: 2026-07-21T10:00:00Z'),
        ('ocideck_seal_at'),
      );
    });

    test('een ingesprongen regel is geen sleutel maar een vervolgregel', () {
      // Dit is het hele verschil tussen "een sleutel die ik bezit" en "de
      // binnenkant van een blok van iemand anders".
      expect(frontMatterKeyOf('  section { color: red }'), isNull);
      expect(frontMatterKeyOf('\ttheme: dark'), isNull);
    });

    test('commentaar, lege regels en lijstitems dragen geen sleutel', () {
      expect(frontMatterKeyOf('# theme: dark'), isNull);
      expect(frontMatterKeyOf(''), isNull);
      expect(frontMatterKeyOf('- theme: dark'), isNull);
    });
  });

  group('mergeFrontMatter', () {
    test('zonder bronregels is de uitkomst wat de generator schrijft', () {
      expect(
        mergeFrontMatter(
          original: const [],
          generated: const ['marp: true', 'theme: ocideck'],
        ),
        ['marp: true', 'theme: ocideck'],
      );
    });

    test('een lijstwaarde onder een eigen sleutel gaat mee met die sleutel', () {
      // De lijst-tak van de vervolgregeltoets (`- ` op kolom 0) is de enige die
      // hier iets doet: zonder hem valt `- OWASP WSTG@4.2` door naar "onbekende
      // regel, laten staan" en blijft het wees-lijstitem onder de nieuwe
      // scalaire waarde hangen — kapotte YAML in andermans bestand.
      expect(
        mergeFrontMatter(
          original: const [
            'marp: true',
            'standards:',
            '- OWASP WSTG@4.2',
            '- OWASP MASTG@2.0',
          ],
          generated: const ['marp: true', 'standards: OWASP WSTG@4.2'],
        ),
        ['marp: true', 'standards: OWASP WSTG@4.2'],
      );
    });

    test('een lijstwaarde onder een vreemde sleutel blijft ongemoeid', () {
      // De andere helft van diezelfde tak. Zonder deze assertie zou "gooi alle
      // lijstitems weg" ook groen zijn, en dat vernielt de kop van de gebruiker.
      expect(
        mergeFrontMatter(
          original: const [
            'marp: true',
            'authors:',
            '- Jan Jansen',
            '-',
            '  affiliatie: LibreKAT',
          ],
          generated: const ['marp: true'],
        ),
        [
          'marp: true',
          'authors:',
          '- Jan Jansen',
          '-',
          '  affiliatie: LibreKAT',
        ],
      );
    });

    test('een eigen sleutel wordt op zijn eigen plek vervangen', () {
      expect(
        mergeFrontMatter(
          original: const ['marp: true', 'theme: oud', 'size: 16:9'],
          generated: const ['marp: true', 'theme: nieuw'],
        ),
        ['marp: true', 'theme: nieuw', 'size: 16:9'],
      );
    });

    test('een eigen sleutel die niet meer geschreven wordt, verdwijnt', () {
      expect(
        mergeFrontMatter(
          original: const ['marp: true', 'paginate: true', 'size: 16:9'],
          generated: const ['marp: true'],
        ),
        ['marp: true', 'size: 16:9'],
      );
    });

    test('een nieuwe eigen sleutel komt achteraan, in generatorvolgorde', () {
      expect(
        mergeFrontMatter(
          original: const ['marp: true', 'size: 16:9'],
          generated: const ['marp: true', 'title: T', 'author: A'],
        ),
        ['marp: true', 'size: 16:9', 'title: T', 'author: A'],
      );
    });

    test('commentaar en lege regels blijven precies staan', () {
      expect(
        mergeFrontMatter(
          original: const [
            '# van de hand van de auteur',
            'marp: true',
            '',
            '# hieronder staat mijn eigen kop',
            'size: 16:9',
          ],
          generated: const ['marp: true'],
        ),
        [
          '# van de hand van de auteur',
          'marp: true',
          '',
          '# hieronder staat mijn eigen kop',
          'size: 16:9',
        ],
      );
    });

    test('een genest blok van een onbekende sleutel blijft heel', () {
      const style = ['style: |', '  section {', '    color: red;', '  }'];
      expect(
        mergeFrontMatter(
          original: const ['marp: true', ...style, 'theme: oud'],
          generated: const ['marp: true', 'theme: nieuw'],
        ),
        ['marp: true', ...style, 'theme: nieuw'],
      );
    });

    test('een lijst onder een onbekende sleutel blijft heel', () {
      expect(
        mergeFrontMatter(
          original: const ['mijn_lijst:', '- een', '- twee', 'theme: oud'],
          generated: const ['theme: nieuw'],
        ),
        ['mijn_lijst:', '- een', '- twee', 'theme: nieuw'],
      );
    });

    test('de vervolgregels van een eigen sleutel gaan mee met de waarde', () {
      // Half werk is hier erger dan schoon vervangen: een achtergebleven
      // ingesprongen regel is geen geldige YAML meer.
      expect(
        mergeFrontMatter(
          original: const ['title: |', '  Lange', '  titel', 'size: 16:9'],
          generated: const ['title: Kort'],
        ),
        ['title: Kort', 'size: 16:9'],
      );
    });

    test('een sleutel die meermaals mag voorkomen landt op de eerste plek', () {
      expect(
        mergeFrontMatter(
          original: const ['tool: Burp@1', 'size: 16:9', 'tool: Nmap@7'],
          generated: const ['tool: Burp@2', 'tool: Nmap@8', 'tool: Zap@1'],
        ),
        ['tool: Burp@2', 'tool: Nmap@8', 'tool: Zap@1', 'size: 16:9'],
      );
    });

    test('de bewerking is idempotent', () {
      const original = [
        '# kop',
        'marp: true',
        'style: |',
        '  section { color: red }',
        '',
        'theme: oud',
        'footer: voet',
      ];
      const generated = ['marp: true', 'theme: nieuw', 'title: T'];
      final eerste = mergeFrontMatter(original: original, generated: generated);
      final tweede = mergeFrontMatter(original: eerste, generated: generated);
      expect(tweede, eerste);
    });
  });
}
