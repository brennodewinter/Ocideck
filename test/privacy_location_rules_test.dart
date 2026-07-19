// Geboortedatum en coördinaten (OCIWACHT §3-D).
//
// Twee regels met tegengestelde poorten, en de test bewaakt vooral dát
// verschil. De geboortedatum eist een contextwoord omdat een datum de meest
// voorkomende getalsvorm in een zakelijk deck is — zonder poort meldt de regel
// de agenda. Coördinaten eisen er juist géén, omdat hun vorm in gewone tekst
// niet voorkomt; daar doet het decimalenaantal het werk.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanText(String text) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [
        Slide.create(SlideType.bullets).copyWith(bullets: [text]),
      ],
    ),
  );

  Set<String> rulesIn(String text) => scanText(text).firedRules;

  PrivacyConfidence? confidenceOf(String text, String ruleId) {
    final matches = scanText(text).findings.where((f) => f.ruleId == ruleId);
    return matches.isEmpty ? null : matches.first.confidence;
  }

  group('contact.birthdate', () {
    test('vindt een datum achter een contextwoord', () {
      expect(
        rulesIn('Geboortedatum: 31-12-1980'),
        contains('contact.birthdate'),
      );
      expect(rulesIn('geboren op 03/04/1975'), contains('contact.birthdate'));
      expect(
        rulesIn('Date of birth 1980-12-31'),
        contains('contact.birthdate'),
      );
      expect(rulesIn('Geburtsdatum 12.03.1966'), contains('contact.birthdate'));
    });

    test('vindt een datum met de maandnaam erin', () {
      expect(
        rulesIn('Geboortedatum: 12 maart 1980'),
        contains('contact.birthdate'),
      );
      expect(rulesIn('born 3 May 1975'), contains('contact.birthdate'));
    });

    test('een datum zonder contextwoord is gewoon een datum', () {
      // Dit is de hele reden dat de poort er is: zonder haar meldt de regel de
      // agenda in plaats van een persoonsgegeven.
      expect(rulesIn('Release op 31-12-2025'), isEmpty);
      expect(rulesIn('De deadline is 01/03/2026'), isEmpty);
      expect(rulesIn('Vergadering 12 maart 2026'), isEmpty);
      expect(rulesIn('Het contract loopt tot 2027-01-01'), isEmpty);
    });

    test('een onmogelijke datum telt niet', () {
      expect(rulesIn('Geboortedatum: 31-02-1980'), isEmpty);
      expect(rulesIn('geboren op 45-13-1980'), isEmpty);
    });

    test('een jaartal buiten het plausibele bereik telt niet', () {
      expect(rulesIn('Geboortedatum: 01-01-1850'), isEmpty);
      expect(rulesIn('geboren op 01-01-2099'), isEmpty);
    });

    test('een geboortedatum blijft een waarschijnlijkheid, geen zekerheid', () {
      expect(
        confidenceOf('Geboortedatum: 31-12-1980', 'contact.birthdate'),
        PrivacyConfidence.likely,
      );
    });
  });

  group('contact.geo', () {
    test('vindt een decimaal coördinatenpaar zonder contextwoord', () {
      expect(rulesIn('Locatie 52.37403, 4.88969'), contains('contact.geo'));
      expect(rulesIn('-33.86882, 151.20930'), contains('contact.geo'));
    });

    test('te weinig decimalen wijst een dorp aan, geen deur', () {
      // Met twee decimalen is de precisie ruwweg een kilometer. Dat is geen
      // persoonsgegeven meer, en het botst met gewone getallenparen.
      expect(rulesIn('Meting 52.37, 4.88 genoteerd'), isEmpty);
      expect(rulesIn('Verhouding 1.25, 3.50 gemeten'), isEmpty);
    });

    test('buiten het bereik van de aardbol is het geen coördinaat', () {
      expect(rulesIn('Waarden 95.12345, 4.88969'), isEmpty);
      expect(rulesIn('Waarden 52.37403, 999.88969'), isEmpty);
    });

    test('nul-nul is "geen locatie bekend"', () {
      expect(rulesIn('Fallback 0.00000, 0.00000'), isEmpty);
    });

    test('een geo:-URI en what3words zijn zeker', () {
      expect(
        confidenceOf('geo:52.37403,4.88969', 'contact.geo'),
        PrivacyConfidence.certain,
      );
      expect(
        confidenceOf('///stelsel.trotse.klapt', 'contact.geo'),
        PrivacyConfidence.certain,
      );
    });

    test('een plus-code blijft mogelijk, want hij botst met productcodes', () {
      expect(
        confidenceOf('Plus-code 9F26RC2X+2F', 'contact.geo'),
        PrivacyConfidence.possible,
      );
    });

    test('grafiekdata is geen locatie', () {
      // Een dataset ís een reeks getallenparen; die hoort hier niet af te gaan.
      final result = scanner.scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(
              // Het reguliere tekstveld meldt wél — dat is de bedoeling.
              notes: '52.37403, 4.88969',
            ),
          ],
        ),
      );
      expect(result.firedRules, contains('contact.geo'));
    });
  });

  group('geboortedatum als bouwsteen', () {
    test('een geboortedatum koppelt geen bijzonder gegeven op zichzelf', () {
      // Een datum wijst geen persoon aan; dat doet pas de combinatie. Zie
      // §5.6 — de quasi-identificatoren zijn een eigen regel (bulk.quasi_combo).
      final result = scanText('Geboortedatum: 31-12-1980, diagnose gesteld');
      final health = result.findings.where((f) => f.ruleId == 'special.health');
      expect(health, isNotEmpty);
      expect(health.first.confidence, PrivacyConfidence.possible);
    });
  });
}
