// De combinatie van quasi-identificatoren (OCIWACHT §3-H, §5.6).
//
// Latanya Sweeney liet in 1997 zien dat postcode, geboortedatum en geslacht
// samen 87% van de Amerikaanse bevolking uniek aanwijzen. Geen van de drie is op
// zichzelf een identificator — en juist daarom overleven ze het schrappen van
// namen en nummers, waarna het resultaat "geanonimiseerd" heet.
//
// Deze test bewaakt twee dingen die even hard zijn:
//
//   1. dat de drie sámen wél melden, ook wanneer ze als tabelkolommen staan;
//   2. dat twee van de drie níét melden. Dat is de helft van de waarde: een
//      regel die al bij twee afgaat, meldt elke adreslijst.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_bulk_rules.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  Set<String> rulesFor(Slide slide) =>
      scanner.scan(Deck(title: 'Deck', slides: [slide])).firedRules;

  Set<String> rulesInBullets(List<String> bullets) =>
      rulesFor(Slide.create(SlideType.bullets).copyWith(bullets: bullets));

  Slide tableWith(List<String> headers, {int rows = 3}) =>
      Slide.create(SlideType.table).copyWith(
        tableRows: [
          headers,
          for (var i = 0; i < rows; i++)
            [for (var c = 0; c < headers.length; c++) 'x'],
        ],
      );

  group('de drie samen', () {
    test('in lopende tekst', () {
      final rules = rulesInBullets([
        'Geboortedatum: 12-03-1980',
        'Postcode 1234 AB',
        'Geslacht: v',
      ]);
      expect(rules, contains('bulk.quasi_combo'));
    });

    test('als tabelkolommen', () {
      // Dit is het geval waar de regel voor bestaat: een geëxporteerde tabel
      // waar de namen uit zijn gehaald.
      final rules = rulesFor(
        tableWith(['Geboortedatum', 'Postcode', 'Geslacht']),
      );
      expect(rules, contains('bulk.quasi_combo'));
    });

    test('gemengd: kolommen plus een veld in de tekst', () {
      final slide = tableWith([
        'Geboortedatum',
        'Postcode',
      ]).copyWith(notes: 'Alle records hebben geslacht: m');
      expect(rulesFor(slide), contains('bulk.quasi_combo'));
    });

    test('blijft waarschijnlijk, niet zeker', () {
      // Sweeney's 87% is een bevolkingscijfer, geen uitspraak over dít geval:
      // bij een grove postcode ligt het onderscheidend vermogen lager.
      final f = scanner
          .scan(
            Deck(
              title: 'Deck',
              slides: [
                tableWith(['Geboortedatum', 'Postcode', 'Geslacht']),
              ],
            ),
          )
          .findings
          .firstWhere((x) => x.ruleId == 'bulk.quasi_combo');
      expect(f.confidence, PrivacyConfidence.likely);
      expect(f.family, PrivacyFamily.bulk);
      // Geen waarden in de melding, alleen welke drie signalen samenvielen.
      expect(f.maskedSample, 'geboortedatum+postcode+geslacht');
    });
  });

  group('twee van de drie is niets', () {
    test('geboortedatum en postcode zonder geslacht', () {
      expect(
        rulesInBullets(['Geboortedatum: 12-03-1980', 'Postcode 1234 AB']),
        isNot(contains('bulk.quasi_combo')),
      );
    });

    test('postcode en geslacht zonder geboortedatum', () {
      expect(
        rulesInBullets(['Postcode 1234 AB', 'Geslacht: v']),
        isNot(contains('bulk.quasi_combo')),
      );
    });

    test('een gewone adreslijst meldt niets', () {
      // Zonder deze grens zou elke ledenlijst met adressen afgaan.
      expect(
        rulesFor(tableWith(['Naam', 'Straat', 'Postcode', 'Woonplaats'])),
        isNot(contains('bulk.quasi_combo')),
      );
    });
  });

  group('geslacht telt als veld, niet als woord', () {
    test('een label met een waarde telt', () {
      expect(genderFieldPattern.hasMatch('Geslacht: v'), isTrue);
      expect(genderFieldPattern.hasMatch('gender = female'), isTrue);
      expect(genderFieldPattern.hasMatch('Sex: M'), isTrue);
    });

    test('een kaal woord in lopende tekst telt niet', () {
      // "De man liep naar buiten" is geen geslachtsveld. Zou dat wél tellen,
      // dan zou deze regel op elk verhaal afgaan waar iemand in voorkomt.
      expect(genderFieldPattern.hasMatch('De man liep naar buiten'), isFalse);
      expect(genderFieldPattern.hasMatch('vrouw en kind'), isFalse);
    });

    test('een waarde die niet in tweeën deelt telt niet', () {
      // `onbekend` draagt geen onderscheidend vermogen, en daar gaat Sweeney's
      // rekensom nu juist over.
      expect(genderFieldPattern.hasMatch('Geslacht: onbekend'), isFalse);
      expect(genderFieldPattern.hasMatch('Geslacht: n.v.t.'), isFalse);
    });

    test('een beroep dat met een m begint is geen geslacht', () {
      // Zonder woordgrens ná de waarde matcht `m` op elk woord dat met een m
      // begint. Dat is precies wat er misging bij het schrijven van dit patroon.
      expect(genderFieldPattern.hasMatch('Geslacht: monteur'), isFalse);
      expect(genderFieldPattern.hasMatch('Gender: management'), isFalse);
    });
  });
}
