import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/front_matter_merge.dart';

/// De regelbewerking op zichzelf: geen deck, geen markdown, alleen de vraag of
/// een onbekende regel exact blijft staan waar hij stond.
void main() {
  group('frontMatterKeyOf', () {
    test('herkent een sleutel op kolom 0, met en zonder waarde', () {
      expect(frontMatterKeyOf('theme: ocideck'), 'theme');
      expect(frontMatterKeyOf('style:'), 'style');
      expect(frontMatterKeyOf('ocideck_seal_at: 2026-07-21T10:00:00Z'), (
        'ocideck_seal_at'
      ));
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

    test('een eigen sleutel wordt op zijn eigen plek vervangen', () {
      expect(
        mergeFrontMatter(
          original: const ['marp: true', 'theme: oud', 'footer: mijn voet'],
          generated: const ['marp: true', 'theme: nieuw'],
        ),
        ['marp: true', 'theme: nieuw', 'footer: mijn voet'],
      );
    });

    test('een eigen sleutel die niet meer geschreven wordt, verdwijnt', () {
      expect(
        mergeFrontMatter(
          original: const ['marp: true', 'paginate: true', 'header: kop'],
          generated: const ['marp: true'],
        ),
        ['marp: true', 'header: kop'],
      );
    });

    test('een nieuwe eigen sleutel komt achteraan, in generatorvolgorde', () {
      expect(
        mergeFrontMatter(
          original: const ['marp: true', 'header: kop'],
          generated: const ['marp: true', 'title: T', 'author: A'],
        ),
        ['marp: true', 'header: kop', 'title: T', 'author: A'],
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
            'header: kop',
          ],
          generated: const ['marp: true'],
        ),
        [
          '# van de hand van de auteur',
          'marp: true',
          '',
          '# hieronder staat mijn eigen kop',
          'header: kop',
        ],
      );
    });

    test('een genest blok van een onbekende sleutel blijft heel', () {
      const style = [
        'style: |',
        '  section {',
        '    color: red;',
        '  }',
      ];
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
          original: const ['title: |', '  Lange', '  titel', 'header: kop'],
          generated: const ['title: Kort'],
        ),
        ['title: Kort', 'header: kop'],
      );
    });

    test('een sleutel die meermaals mag voorkomen landt op de eerste plek', () {
      expect(
        mergeFrontMatter(
          original: const [
            'tool: Burp@1',
            'header: kop',
            'tool: Nmap@7',
          ],
          generated: const ['tool: Burp@2', 'tool: Nmap@8', 'tool: Zap@1'],
        ),
        ['tool: Burp@2', 'tool: Nmap@8', 'tool: Zap@1', 'header: kop'],
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
      final eerste = mergeFrontMatter(
        original: original,
        generated: generated,
      );
      final tweede = mergeFrontMatter(original: eerste, generated: generated);
      expect(tweede, eerste);
    });
  });
}
