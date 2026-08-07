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
}
