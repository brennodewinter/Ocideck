// Nederlandse persoons- en bijvoeglijke vormen (OCIWACHT §13.3).
//
// EuroVoc levert `katholicisme`, mensen schrijven `katholiek`. Deze test
// bewaakt drie dingen, en het middelste is waar de meeste zorg in zit:
//
//   1. dat de persoonsvormen gevonden worden;
//   2. dat de *institutionele* vormen dat níét worden — `christelijke school`
//      is geen geloofsovertuiging van iemand;
//   3. dat de Nederlandse stamwisselingen gedekt zijn. Voorvoegselmatching gaat
//      ervan uit dat het woordbegin stabiel is, en bij `conservatief` →
//      `conservatieve` klopt dat niet.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  Set<String> rulesIn(String text) => scanner
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .firedRules;

  PrivacyFinding? findingFor(String text, String ruleId) {
    final m = scanner
        .scan(
          Deck(
            title: 'Deck',
            slides: [
              Slide.create(SlideType.bullets).copyWith(bullets: [text]),
            ],
          ),
        )
        .findings
        .where((f) => f.ruleId == ruleId);
    return m.isEmpty ? null : m.first;
  }

  group('de vormen die EuroVoc niet levert', () {
    test(
      'een persoonsvorm wordt gevonden waar het zelfstandig naamwoord faalde',
      () {
        // Dit is letterlijk het geval dat bij het bundelen van EuroVoc gemist
        // werd: de bron kent `katholicisme`, de tekst zegt `katholiek`.
        expect(
          rulesIn('Betrokkene is katholiek opgevoed'),
          contains('special.religion'),
        );
        expect(rulesIn('Hij is moslim'), contains('special.religion'));
        expect(rulesIn('Zij is joods'), contains('special.religion'));
        expect(rulesIn('Hij is gereformeerd'), contains('special.religion'));
      },
    );

    test('de verbogen vorm hoort er ook bij', () {
      expect(rulesIn('De katholieke betrokkene'), contains('special.religion'));
      expect(rulesIn('Twee moslims gehoord'), contains('special.religion'));
    });

    test('een geloofsovertuiging is het gegeven zelf, geen aanwijzing', () {
      final f = findingFor('Betrokkene is moslim', 'special.religion');
      expect(f!.role, PrivacyTermRole.value);
      expect(f.isRedactable, isTrue);
    });

    test('met een persoon erbij escaleert het', () {
      final f = findingFor('Mevr. De Jong is moslim', 'special.religion');
      expect(f!.confidence, PrivacyConfidence.certain);
    });
  });

  group('instellingen zijn geen personen', () {
    test('christelijk onderwijs is geen geloofsovertuiging', () {
      // `christen` gaat mee, `christelijk` niet: dat beschrijft in Nederlands
      // zakelijk taalgebruik overwegend een school, een omroep of een feestdag.
      expect(rulesIn('De christelijke school aan de overkant'), isEmpty);
      expect(rulesIn('Rooster met christelijke feestdagen'), isEmpty);
    });

    test('maar de persoonsvorm wel', () {
      expect(rulesIn('Betrokkene is christen'), contains('special.religion'));
    });

    test('kerkelijk en praktiserend staan er bewust niet in', () {
      // `kerkelijke gemeente` is een instelling; `praktiserend` betekent alleen
      // iets in combinatie ("praktiserend jurist" evengoed).
      expect(rulesIn('De kerkelijke gemeente vergadert'), isEmpty);
      expect(rulesIn('Een praktiserend jurist'), isEmpty);
    });
  });

  group('Nederlandse stamwisselingen', () {
    test('conservatief dekt ook conservatieve (f wordt v)', () {
      expect(
        rulesIn('Een conservatieve stroming binnen de partij'),
        contains('special.politics'),
      );
    });

    test('liberaal dekt ook liberale (aa verkort)', () {
      expect(
        rulesIn('De liberale kandidaat won'),
        contains('special.politics'),
      );
    });

    test('maar liberalisering is geen overtuiging', () {
      // De grens tussen "iemands standpunt" en "een beleidsproces" ligt precies
      // hier, en voorvoegselmatching moet hem halen.
      expect(rulesIn('De liberalisering van de markt'), isEmpty);
    });

    test('een bekende vals-positieve, en waarom hij aanvaardbaar is', () {
      // "Een conservatieve schatting" is geen politieke overtuiging. Dat dit
      // afgaat is de prijs van `conservatiev` als stam, en de rekening blijft
      // klein: special.politics staat standaard uit (defaultDisabledPrivacyRules)
      // en de melding is informatief tot er iemand bij staat.
      final f = findingFor(
        'Een conservatieve schatting van de kosten',
        'special.politics',
      );
      expect(f, isNotNull);
      expect(f!.confidence, PrivacyConfidence.possible);
      expect(
        defaultDisabledPrivacyRules,
        contains('special.politics'),
        reason: 'als deze regel ooit standaard aan gaat, moet deze term eruit',
      );
    });
  });
}
