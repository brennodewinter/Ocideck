// Kenteken en buitenlandse postcode (OCIWACHT §3-D, de ◐-regels).
//
// Twee regels die aan het landpakket hangen, en die daarom als eerste moeten
// bewijzen dat ze dáár ook werkelijk aan hangen: hun regel-id draagt de landcode
// vooraan (`nl.plate`, `de.postcode`), en dat is wat de regiopoort leest.
//
// Voor de rest is dit weer een test die vooral uit negatieven bestaat. Een
// kentekenpatroon zonder contextwoord meet artikelnummers, en vijf kale cijfers
// zijn net zo goed een bedrag.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  Set<String> rulesWith(PrivacyScanner s, String text) => s
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .firedRules;

  Set<String> rulesIn(String text) => rulesWith(scanner, text);

  group('nl.plate', () {
    test('vindt een kenteken achter een contextwoord', () {
      expect(
        rulesIn('Kenteken 12-ABC-3 staat genoteerd'),
        contains('nl.plate'),
      );
      expect(rulesIn('Het voertuig met XX-99-88'), contains('nl.plate'));
      expect(rulesIn('Nummerbord 99-ZZ-12'), contains('nl.plate'));
    });

    test('zonder contextwoord vuurt het patroon niet', () {
      // Dit is de hele reden dat de eis er is: het patroon dekt zo'n beetje elke
      // combinatie van letter- en cijfergroepen met streepjes.
      expect(rulesIn('Artikelcode 12-ABC-3 uit de catalogus'), isEmpty);
      expect(rulesIn('Serie 99-ZZ-12 is uitverkocht'), isEmpty);
    });

    test('een uitgesloten lettergroep telt niet', () {
      expect(rulesIn('Kenteken 12-SS-34'), isEmpty);
      expect(rulesIn('Kenteken SD-12-34'), isEmpty);
    });

    test('het kenteken hangt aan het Nederlandse pakket', () {
      const zonderNl = PrivacyScanner(regions: {'de', 'be'});
      expect(rulesWith(zonderNl, 'Kenteken 12-ABC-3'), isEmpty);
    });
  });

  group('buitenlandse postcodes', () {
    test('het Britse formaat is specifiek genoeg zonder contextwoord', () {
      expect(rulesIn('Bezoekadres SW1A 1AA'), contains('uk.postcode'));
    });

    test('vijf kale cijfers eisen wél een contextwoord', () {
      // Anders is elk bedrag en elk artikelnummer een Duitse postcode.
      expect(rulesIn('Bedrag 10115 euro verwerkt'), isEmpty);
      expect(rulesIn('Postleitzahl 10115 Berlin'), contains('de.postcode'));
    });

    test('een postcode blijft informatief', () {
      final findings = scanner
          .scan(
            Deck(
              title: 'Deck',
              slides: [
                Slide.create(
                  SlideType.bullets,
                ).copyWith(bullets: ['Bezoekadres SW1A 1AA']),
              ],
            ),
          )
          .certain;
      expect(findings, isEmpty);
    });

    test('een uitgezet pakket haalt zijn postcode weg', () {
      const zonderUk = PrivacyScanner(regions: {'nl', 'de'});
      expect(rulesWith(zonderUk, 'Bezoekadres SW1A 1AA'), isEmpty);
    });
  });
}
