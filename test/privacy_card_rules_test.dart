// Creditcardnummers, hun beveiligingscode, en het notitieveld (§3-C, §3-I).
//
// De PAN is een van de weinige regels met twee onafhankelijke bewijzen in het
// nummer zelf: een Luhn-controlecijfer en een IIN-bereik. Deze test bewaakt
// vooral dat ze allebei nodig blijven — een reeks die de Luhn haalt maar bij
// geen enkel kaartschema hoort, is toeval en geen kaart.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_card_rules.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanBullets(List<String> bullets) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [Slide.create(SlideType.bullets).copyWith(bullets: bullets)],
    ),
  );

  Set<String> rulesIn(String text) => scanBullets([text]).firedRules;

  group('cardSchemeOf', () {
    test('herkent de schema\'s uit §3-C', () {
      expect(cardSchemeOf('4539578763621486'), 'Visa');
      expect(cardSchemeOf('5425233430109903'), 'Mastercard');
      expect(cardSchemeOf('2223003122003222'), 'Mastercard');
      expect(cardSchemeOf('374245455400126'), 'American Express');
      expect(cardSchemeOf('6011000991300009'), 'Discover');
      expect(cardSchemeOf('3566002020360505'), 'JCB');
      expect(cardSchemeOf('6212345678901232'), 'UnionPay');
    });

    test('het Mastercard-bereik stopt bij 2720', () {
      // 2221-2720 is het bereik dat in 2017 bijkwam. 2721 hoort er niet bij, en
      // een prefixvergelijking op twee tekens zou dat missen.
      expect(cardSchemeOf('2720990000000000'), isNotNull);
      expect(cardSchemeOf('2721990000000000'), isNull);
      expect(cardSchemeOf('2220990000000000'), isNull);
    });

    test('de juiste lengte hoort bij het schema', () {
      // Amex is vijftien cijfers. Zestien met een 37-prefix is geen Amex.
      expect(cardSchemeOf('3742454554001267'), isNull);
    });

    test('een onbekend bereik is geen kaart', () {
      expect(cardSchemeOf('1234567812345670'), isNull);
      expect(cardSchemeOf('9999999999999995'), isNull);
    });
  });

  group('fin.pan', () {
    test('vindt een kaartnummer, met en zonder groepjes', () {
      expect(rulesIn('Kaart 4539578763621486'), contains('fin.pan'));
      expect(rulesIn('4539 5787 6362 1486'), contains('fin.pan'));
      expect(rulesIn('4539-5787-6362-1486'), contains('fin.pan'));
    });

    test('de Luhn alleen is niet genoeg', () {
      // Eén op de tien willekeurige reeksen haalt de Luhn. Zonder het
      // IIN-bereik zou elk ordernummer van zestien cijfers een kaart zijn.
      expect(rulesIn('Ordernummer 1234567812345670'), isEmpty);
    });

    test('het IIN-bereik alleen ook niet', () {
      // Begint met 4 en is zestien cijfers, maar faalt de Luhn.
      expect(rulesIn('Referentie 4539578763621487'), isEmpty);
    });

    test('de officiële testkaarten tellen niet', () {
      // Die doorstaan de Luhn met opzet — dat is waar ze voor gemaakt zijn — en
      // staan in elke betaalhandleiding.
      expect(rulesIn('Test met 4111111111111111'), isEmpty);
      expect(rulesIn('of 4242424242424242'), isEmpty);
      expect(rulesIn('of 5555555555554444'), isEmpty);
      expect(rulesIn('of 378282246310005'), isEmpty);
    });

    test('een kaartnummer is zeker', () {
      final f = scanBullets([
        'Kaart 4539578763621486',
      ]).findings.firstWhere((x) => x.ruleId == 'fin.pan');
      expect(f.confidence, PrivacyConfidence.certain);
      expect(f.family, PrivacyFamily.financial);
      expect(f.maskedSample.contains('4539'), isFalse);
    });

    test('een Amex botst niet meer met de IMEI', () {
      // Vijftien cijfers met een geldige Luhn is op vorm allebei. Bij het
      // bouwen van digital.imei zijn de Amex-bereiken 34/37 daar uitgesloten;
      // deze regel pikt ze op. Precies één van de twee hoort te vuren.
      final rules = rulesIn('Kaart 374245455400126');
      expect(rules, contains('fin.pan'));
      expect(rules, isNot(contains('digital.imei')));
    });
  });

  group('fin.cvv', () {
    test('vuurt alleen naast een kaartnummer', () {
      // `123` betekent niets. Drie cijfers achter het woord cvv betekenen
      // alleen iets als er een kaart bij staat.
      expect(rulesIn('CVV 123'), isEmpty);
      expect(rulesIn('De beveiligingscode is 456'), isEmpty);
    });

    test('mét een kaartnummer erbij is het een betaalinstructie', () {
      final rules = rulesIn('Kaart 4539578763621486, cvv 123');
      expect(rules, containsAll(<String>['fin.pan', 'fin.cvv']));
    });

    test('ook in de Nederlandse formulering', () {
      expect(
        rulesIn('4539578763621486 met beveiligingscode 123'),
        contains('fin.cvv'),
      );
    });
  });

  group('struct.notes_leak', () {
    PrivacyScanResult scanNotes(
      String notes, {
      List<String> bullets = const [],
    }) => scanner.scan(
      Deck(
        title: 'Deck',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(notes: notes, bullets: bullets),
        ],
      ),
    );

    test('meldt dat er iets in de notities staat', () {
      // Het vuilste veld van allemaal: onzichtbaar in de preview, wél in de
      // PPTX-export.
      final r = scanNotes('Contact: marieke@acme.nl');
      expect(r.firedRules, contains('struct.notes_leak'));
    });

    test('één melding per slide, niet per treffer', () {
      final r = scanNotes('marieke@acme.nl en jan@acme.nl en piet@acme.nl');
      final leaks = r.findings.where((f) => f.ruleId == 'struct.notes_leak');
      expect(leaks, hasLength(1));
      expect(leaks.first.maskedSample, '3');
    });

    test('een bevinding elders op de slide telt niet mee', () {
      final r = scanNotes('', bullets: ['Contact: marieke@acme.nl']);
      expect(r.firedRules, isNot(contains('struct.notes_leak')));
    });

    test('een informatieve treffer is geen lek om over te waarschuwen', () {
      // Een contextloze BSN-achtige reeks in de notities blijft `possible`, en
      // daar hoort geen extra waarschuwing bij.
      final r = scanNotes('Transactie 728398242 verwerkt');
      expect(r.firedRules, isNot(contains('struct.notes_leak')));
    });

    test('schone notities melden niets', () {
      final r = scanNotes('Denk aan de tijd, en begin met de agenda.');
      expect(r.firedRules, isNot(contains('struct.notes_leak')));
    });
  });
}
