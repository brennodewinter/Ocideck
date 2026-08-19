import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/documentation_service.dart';

import '../tool/translate_docs.dart';

void main() {
  group('translate_docs — variantpaden', () {
    test('voegt de taalcode vóór de .md-extensie in', () {
      expect(variantPath('docs/USER_GUIDE.md', 'de'), 'docs/USER_GUIDE.de.md');
      expect(variantPath('LICENSE.md', 'fr'), 'LICENSE.fr.md');
    });

    test('houdt subpad en meervoudige punten heel', () {
      // Alleen de laatste extensie krijgt de taalcode ervóór; de rest van de
      // naam blijft ongemoeid, zodat de app-resolutie (_variantKey) exact
      // hetzelfde pad opbouwt.
      expect(variantPath('docs/FAQ.md', 'pl'), 'docs/FAQ.pl.md');
    });
  });

  group('translate_docs — banner', () {
    test('zet de machinevertaal-melding en de Engelse bronregel bovenaan', () {
      final out = withBanner('Machinevertaling.', '# Titel\n\nTekst.\n');
      final lines = out.split('\n');
      expect(lines.first, contains('🤖'));
      expect(lines.first, contains('Machinevertaling.'));
      expect(out, contains(bannerSourceLine));
      // De inhoud volgt ná de banner.
      expect(
        out.indexOf('# Titel'),
        greaterThan(out.indexOf(bannerSourceLine)),
      );
    });
  });

  group('translate_docs — uitgesloten documenten', () {
    test('PRIVACY en SECURITY_DESIGN worden nooit vertaald', () {
      expect(excludedDocs, contains('docs/PRIVACY.md'));
      expect(excludedDocs, contains('docs/SECURITY_DESIGN.md'));
      // En ze staan niet per ongeluk óók in de te-vertalen lijst.
      for (final doc in excludedDocs) {
        expect(translatableDocs, isNot(contains(doc)));
      }
    });
  });

  group('translate_docs — verscheepte doctalen', () {
    test(
      'is een korte, expliciete lijst met de Engelse basis buiten beeld',
      () {
        // OciDeck verscheept docs in Engels (basis) + Nederlands; andere talen
        // vallen in de lezer terug op de Engelse basis. Dus géén lange lijst.
        expect(shippedDocLanguages, contains('nl'));
        expect(
          shippedDocLanguages,
          isNot(contains(DocumentationService.baseLanguage)),
        );
      },
    );
  });

  group('translate_docs — variantconsistentie', () {
    test('de verscheepte docvarianten in deze repo zijn consistent', () {
      // Draait de echte poortlogica tegen de repo (cwd = pakketroot): elke
      // verscheepte variant bestaat en is geregistreerd, er staat geen variant
      // voor een niet-verscheepte taal, geen registratie is verweesd, en geen
      // uitgesloten document is vertaald. Dit is óók de test die de poort
      // beschermt: gaat hij rood, dan zou `make translate-docs-check` dat ook.
      expect(docVariantProblems(), isEmpty);
    });
  });

  group('translate_docs — pubspec-registratie', () {
    const pubspec = '''
flutter:
  assets:
    - docs/USER_GUIDE.md
    - docs/PRIVACY.md
''';

    test(
      'voegt variantregels toe ná de basisregel, met dezelfde inspringing',
      () {
        final out = registerVariants(
          pubspec,
          ['docs/USER_GUIDE.md'],
          ['de', 'nl'],
        );
        expect(out, contains('    - docs/USER_GUIDE.md\n'));
        expect(out, contains('    - docs/USER_GUIDE.de.md'));
        expect(out, contains('    - docs/USER_GUIDE.nl.md'));
        // De variant staat direct ná zijn basis, niet ná een andere doc.
        expect(
          out.indexOf('docs/USER_GUIDE.de.md'),
          lessThan(out.indexOf('docs/PRIVACY.md')),
        );
        // Een niet-genoemde basis (PRIVACY) krijgt geen varianten.
        expect(out, isNot(contains('docs/PRIVACY.de.md')));
      },
    );

    test('is idempotent: opnieuw draaien voegt niets dubbel toe', () {
      final once = registerVariants(pubspec, ['docs/USER_GUIDE.md'], ['de']);
      final twice = registerVariants(once, ['docs/USER_GUIDE.md'], ['de']);
      expect(twice, once);
      expect(RegExp('docs/USER_GUIDE.de.md').allMatches(twice).length, 1);
    });
  });

  group('translate_docs — structuurdrift tussen bron en variant', () {
    // De poort die #1571 gevangen zou hebben: de tijdlijnsectie kwam er in het
    // Engels bij en niet in het Nederlands, terwijl alles groen stond. Deze
    // toetsen pinnen de drie stukken waar dat op rust.

    test('koppen binnen een codeblok tellen niet mee', () {
      // Precies de val waar FILE_FORMAT vol mee staat: `# Rapport` is dáár de
      // inhoud van een voorbeeld en geen kop van het document. Zonder deze
      // regel vergelijkt de poort ruis met ruis.
      const markdown =
          '# Titel\n\n'
          '```markdown\n'
          '# Dit is inhoud\n'
          '## En dit ook\n'
          '```\n\n'
          '## Echte kop\n';
      expect(markdownHeadings(markdown).map((h) => h.text), [
        'Titel',
        'Echte kop',
      ]);
    });

    test('een langere fence wordt niet gesloten door een kortere erin', () {
      const markdown =
          '````markdown\n'
          '```\n'
          '## Geen kop\n'
          '```\n'
          '````\n\n'
          '## Wel een kop\n';
      expect(markdownHeadings(markdown).map((h) => h.text), ['Wel een kop']);
    });

    test('leest het niveau van elke kop', () {
      expect(
        markdownHeadings('# Een\n### Drie\n#### Vier\n').map((h) => h.level),
        [1, 3, 4],
      );
    });

    test('sectienummers overleven de vertaling, woorden niet', () {
      const nederlands =
          '### 14.11 Tijdlijnweergave\n'
          '#### 6.3.1 In een git-repo\n'
          '### 3.1b Privacydispositie\n'
          '## Zonder nummer\n';
      expect(markdownSectionNumbers(nederlands), {'14.11', '6.3.1', '3.1b'});
    });

    test('een getal midden in een kop is geen sectienummer', () {
      expect(markdownSectionNumbers('## Marp 2 en verder\n'), isEmpty);
    });

    test('een hernoemde kop is geen drift, een ontbrekende wel', () {
      final bron = markdownHeadings('## Een\n## Twee\n### Drie\n');
      final hernoemd = markdownHeadings('## Één\n## Twee\n### Drie\n');
      expect(missingHeadingCount(bron, hernoemd), 0);

      final zonderDrie = markdownHeadings('## Een\n## Twee\n');
      expect(missingHeadingCount(bron, zonderDrie), 1);
    });

    test('telt per niveau, zodat een verschoven kop opvalt', () {
      final bron = markdownHeadings('## Een\n### Twee\n');
      final verschoven = markdownHeadings('## Een\n## Twee\n');
      // Niveau 3 mist er één; dat niveau 2 er één te veel heeft verrekent niet
      // — anders zou een sectie die stilletjes een niveau opschuift wegvallen
      // tegen de sectie die haar verdringt.
      expect(missingHeadingCount(bron, verschoven), 1);
    });

    test('de basislijn noemt alleen documenten die echt achterlopen', () {
      // Groeit deze lijst, dan is er een sectie niet meevertaald. Krimpt hij,
      // verlaag het getal — dat is waar de ratchet voor bestaat.
      expect(headingDriftBaseline.keys, [
        'docs/KNOWN_LIMITATIONS.md',
        'docs/USER_GUIDE.md',
      ]);
      for (final entry in headingDriftBaseline.entries) {
        expect(translatableDocs, contains(entry.key));
        expect(entry.value, greaterThan(0));
      }
    });
  });
}
