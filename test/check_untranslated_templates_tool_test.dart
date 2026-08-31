@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_untranslated_templates.dart';

/// De poort op onvertaalde sjabloontekst, getoetst op een eigen mini-boom.
///
/// Wat hier bewaakt wordt is niet dat de poort íets vindt, maar dat hij de twee
/// dingen uit elkaar houdt die hem bruikbaar maken: een regel die alleen in het
/// Engels zo staat (een vertaalgat) en een regel die ook in de Nederlandse bron
/// zo staat (de bedoelde vorm). Zonder dat tweede deel meldt hij de
/// SIPOC-tabelkop, `ATIS / QNH` en `**Scope object:**` — en dan is hij ruis.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('untranslated'));
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String id, String lang, String body) {
    final dir = Directory('${temp.path}/$templatesDir');
    dir.createSync(recursive: true);
    File(
      '${dir.path}/$id.$lang.md',
    ).writeAsStringSync('---\nmarp: true\nlanguage: $lang\n---\n\n$body\n');
  }

  group('comparableLines', () {
    test('houdt title maar laat de rest van de front matter vallen', () {
      const md =
          '---\nmarp: true\ntitle: Kickoff\ntheme: ocideck\n---\n\n# Kop\n';
      expect(comparableLines(md), contains('title: Kickoff'));
      expect(comparableLines(md), isNot(contains('marp: true')));
      expect(comparableLines(md), contains('# Kop'));
    });

    test('slaat lege regels over en snijdt navolgende spaties weg', () {
      const md = '# Kop   \n\n\n- punt\n';
      expect(comparableLines(md), {'# Kop', '- punt'});
    });
  });

  group('carriesWords', () {
    test('twee woorden van drie letters tellen mee', () {
      expect(carriesWords('# Test status'), isTrue);
    });

    test(
      'één woord telt niet — te vaak identiek zonder dat er iets mis is',
      () {
        expect(carriesWords('# Design'), isFalse);
        expect(carriesWords('| Total | … |'), isFalse);
      },
    );

    test('cijfers en leestekens maken nog geen woord', () {
      expect(carriesWords('| … | … | … |'), isFalse);
    });

    test('de front-matter-sleutel telt niet als woord', () {
      // Anders haalt een titel van één woord de drempel op `title:` zelf, en
      // meldt de poort `title: Report` wél en `# Report` niet.
      expect(carriesWords('title: Report'), isFalse);
      expect(carriesWords('title: Executive summary'), isTrue);
    });
  });

  group('findUntranslated', () {
    test('meldt een regel die alleen in het Engels zo staat', () {
      write('demo', 'en', '# Executive summary');
      write('demo', 'nl', '# Managementsamenvatting');
      write('demo', 'de', '# Executive summary');

      final hits = findUntranslated(temp.path);
      expect(hits, hasLength(1));
      expect(hits.single.language, 'de');
      expect(hits.single.line, '# Executive summary');
      expect(hits.single.path, 'assets/templates/demo.de.md');
    });

    test('zwijgt als de Nederlandse bron dezelfde regel draagt', () {
      // Precies de vorm van de SIPOC-tabelkop: het Nederlands schrijft hem ook
      // zo, dus is hij bedoeld en geen vertaalgat.
      write('demo', 'en', '| Supplier | Input | Process |');
      write('demo', 'nl', '| Supplier | Input | Process |');
      write('demo', 'de', '| Supplier | Input | Process |');

      expect(findUntranslated(temp.path), isEmpty);
    });

    test('zwijgt onder de woorddrempel', () {
      write('demo', 'en', '# Design');
      write('demo', 'nl', '# Ontwerp');
      write('demo', 'de', '# Design');

      expect(findUntranslated(temp.path), isEmpty);
    });

    test('ziet ook wat binnen een codeblok of HTML staat', () {
      // Juist die twee reizen ongemoeid door de exporteur; een poort die alleen
      // naar koppen en bullets keek zou er langs kijken.
      write(
        'demo',
        'en',
        '```question\n"prompt": "The correct answer"\n```\n'
            '<li>Ask for a specific example</li>',
      );
      write(
        'demo',
        'nl',
        '```question\n"prompt": "Het juiste antwoord"\n```\n'
            '<li>Vraag door naar een voorbeeld</li>',
      );
      write(
        'demo',
        'de',
        '```question\n"prompt": "The correct answer"\n```\n'
            '<li>Ask for a specific example</li>',
      );

      final lines = findUntranslated(temp.path).map((h) => h.line).toSet();
      expect(lines, contains('"prompt": "The correct answer"'));
      expect(lines, contains('<li>Ask for a specific example</li>'));
    });

    test('slaat het Klingon over — dat staat op de Engelse terugval', () {
      write('demo', 'en', '# Executive summary');
      write('demo', 'nl', '# Managementsamenvatting');
      write('demo', 'tlh', '# Executive summary');

      expect(findUntranslated(temp.path), isEmpty);
    });

    test('slaat een sjabloon zonder Nederlandse bron over', () {
      // Zonder bron is er geen maatlat; melden zou raden zijn.
      write('demo', 'en', '# Executive summary');
      write('demo', 'de', '# Executive summary');

      expect(findUntranslated(temp.path), isEmpty);
    });

    test('een langere sjabloon-id verwart de taalherkenning niet', () {
      write('demo', 'en', '# Executive summary');
      write('demo', 'nl', '# Managementsamenvatting');
      write('demo-extra', 'en', '# Executive summary');
      write('demo-extra', 'nl', '# Managementsamenvatting');
      write('demo-extra', 'de', '# Executive summary');

      final hits = findUntranslated(temp.path);
      expect(hits.map((h) => h.template).toSet(), {'demo-extra'});
    });
  });

  group('de boom zelf', () {
    test('geen enkel gebundeld sjabloon draagt nog een Engelse regel', () {
      expect(
        findUntranslated('.').map((h) => '${h.path}: ${h.line}').toList(),
        isEmpty,
        reason:
            'vertaal de regel, of zet het paar (taal, regel) in '
            'allowedCognates in tool/check_untranslated_templates.dart',
      );
    });
  });
}
