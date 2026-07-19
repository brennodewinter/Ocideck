// Regiopakketten en taaldekking (OCIWACHT §5.7, §13.3 — fase 13).
//
// Twee mechanismen die allebei over eerlijkheid gaan in plaats van over
// detectie:
//
//   * een uitgezet **landpakket** haalt regels weg die voor deze gebruiker niet
//     relevant zijn, zónder de universele laag te raken. Dat laatste is de test
//     die ertoe doet: wie het Poolse pakket uitzet, moet nog steeds een IBAN en
//     een paspoortstrook gemeld krijgen;
//   * de **taaldekking** vertelt dat er voor een taal geen trefwoordenlijst is.
//     Zonder die mededeling leest "niets gevonden" als "er zit niets in", in 24
//     talen tegelijk.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_bulk_lexicon.dart';
import 'package:ocideck/services/privacy/privacy_lexicon_data.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  Set<String> rulesWith(PrivacyScanner scanner, String text) => scanner
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .firedRules;

  group('privacyRuleRegion', () {
    test('herkent een landcode aan het begin van het regel-id', () {
      expect(privacyRuleRegion('nl.bsn'), 'nl');
      expect(privacyRuleRegion('pl.pesel'), 'pl');
      expect(privacyRuleRegion('uk.nino'), 'uk');
    });

    test('een universele regel hangt aan geen enkel land', () {
      // `fin.iban` begint óók met letters en een punt, maar `fin` is geen
      // landcode — en de IBAN-regel geldt voor 89 landen tegelijk. Zonder deze
      // eis zou hij uitvallen zodra iemand een pakket uitzet.
      expect(privacyRuleRegion('fin.iban'), isNull);
      expect(privacyRuleRegion('contact.email'), isNull);
      expect(privacyRuleRegion('secret.aws'), isNull);
      expect(privacyRuleRegion('doc.mrz'), isNull);
      expect(privacyRuleRegion('digital.ipv4'), isNull);
      expect(privacyRuleRegion('special.health'), isNull);
    });
  });

  group('het pakket bepaalt wat er draait', () {
    test('standaard staat heel Europa aan, plus de VS en Canada', () {
      expect(defaultPrivacyRegions, contains('nl'));
      expect(defaultPrivacyRegions, contains('pl'));
      expect(defaultPrivacyRegions, contains('uk'));
      expect(defaultPrivacyRegions, contains('ch'));
      // §15.6: bescherming mag niet afhangen van de vraag of de auteur wist dat
      // hij een vinkje moest aanzetten. Elke Amerikaanse en Canadese regel
      // draagt een checksum of een contextpoort, dus het aanzetten kost geen
      // precisie.
      expect(defaultPrivacyRegions, contains('us'));
      expect(defaultPrivacyRegions, contains('ca'));
    });

    test('de landen zonder regels staan nog uit', () {
      // Zodra 8d er is hoort dit met de hand herzien te worden, niet
      // automatisch: cw en aw hebben geen gedocumenteerde checksum.
      for (final code in ['au', 'in', 'br', 'za', 'cw', 'aw']) {
        expect(defaultPrivacyRegions, isNot(contains(code)), reason: code);
        expect(worldPrivacyRegions, contains(code), reason: code);
      }
    });

    test('een uitgezet pakket meldt zijn nummers niet meer', () {
      const scanner = PrivacyScanner();
      const zonderNl = PrivacyScanner(regions: {'be', 'de'});
      const bsn = 'Het burgerservicenummer is 728398242';
      expect(rulesWith(scanner, bsn), contains('nl.bsn'));
      expect(rulesWith(zonderNl, bsn), isNot(contains('nl.bsn')));
    });

    test('de universele laag blijft draaien, ook zonder één pakket', () {
      // Dit is de belangrijkste test van het hele mechanisme: een regiokeuze mag
      // nooit een IBAN, een e-mailadres of een paspoortstrook wegnemen.
      const geenPakketten = PrivacyScanner(regions: {});
      expect(
        rulesWith(geenPakketten, 'Rekening NL18RABO0123459876'),
        contains('fin.iban'),
      );
      expect(
        rulesWith(geenPakketten, 'Mail naar marieke@acme.nl'),
        contains('contact.email'),
      );
      expect(
        rulesWith(
          geenPakketten,
          'export TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8',
        ),
        contains('secret.github'),
      );
    });
  });

  group('taaldekking', () {
    test('zonder de gebundelde ziektenamen is geen taal volledig gedekt', () {
      // `covered` betekent sinds fase 13b: er zijn gebundelde aandoeningsnamen
      // voor deze taal. De handgeschreven vloer alleen is een handvol
      // signaalwoorden, en die "gedekt" noemen was altijd al genereus.
      expect(privacyLexiconCoverage('nl'), PrivacyLexiconCoverage.partial);
      expect(privacyLexiconCoverage('en'), PrivacyLexiconCoverage.partial);
    });

    test('mét de gebundelde ziektenamen wél', () {
      PrivacyBulkLexicon.instance.loadForTest({
        'nl': ['taaislijmziekte'],
        'en': ['cystic fibrosis'],
      }, category: 'special.health');
      addTearDown(PrivacyBulkLexicon.instance.resetForTest);
      expect(privacyLexiconCoverage('nl'), PrivacyLexiconCoverage.covered);
      expect(privacyLexiconCoverage('en'), PrivacyLexiconCoverage.covered);
    });

    test('een taal zonder één term heet ongedekt', () {
      // Dit is het geval waarvoor de meter bestaat. Pools scannen met Engelse
      // triggerwoorden geeft bijna nul recall, en niemand merkt het.
      expect(privacyLexiconCoverage('pl'), PrivacyLexiconCoverage.none);
      expect(privacyLexiconCoverage('fy'), PrivacyLexiconCoverage.none);
      expect(privacyLexiconCoverage('tlh'), PrivacyLexiconCoverage.none);
    });

    test('een dun gevulde taal heet gedeeltelijk, niet gedekt', () {
      expect(privacyLexiconCoverage('fr'), PrivacyLexiconCoverage.partial);
    });

    test('de regio in een taalcode telt niet mee', () {
      // `nl-BE` en `nl` delen hun lexicon.
      PrivacyBulkLexicon.instance.loadForTest({
        'nl': ['taaislijmziekte'],
      }, category: 'special.health');
      addTearDown(PrivacyBulkLexicon.instance.resetForTest);
      expect(privacyLexiconCoverage('nl-BE'), PrivacyLexiconCoverage.covered);
      expect(privacyLexiconCoverage('nl_NL'), PrivacyLexiconCoverage.covered);
    });

    test('de dekking is eerlijk over hoe scheef ze is', () {
      // Geen assertie op een streefwaarde: het punt is dat het verschil tussen
      // de rijkste en de dunste taal groot is en opvraagbaar, niet dat het klein
      // is. Zolang dat zo is, moet het paneel het zeggen.
      final counts = privacyLexiconTermCounts;
      expect(counts['nl'], greaterThan(counts['fr'] ?? 0));
    });
  });
}
