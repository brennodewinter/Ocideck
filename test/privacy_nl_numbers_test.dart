// De zes Nederlandse nummers naast het BSN (OCIWACHT §3-A).
//
// Eén ervan draagt een checksum, vijf niet. Die vijf zijn kale cijferreeksen van
// acht, tien of elf posities, en zulke reeksen staan met duizenden tegelijk in
// een gewoon zakelijk deck. De contextpoort is daar dus geen verfijning maar het
// enige wat ze bruikbaar maakt, en dat is waar de meeste tests hieronder op
// zitten: niet of het nummer wordt gevónden, maar of een ordernummer met
// rust wordt gelaten.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_checksums_eu.dart';
import 'package:ocideck/services/privacy/privacy_eu_rules.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  List<PrivacyFinding> scan(String text) => scanner
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .findings
      .where((f) => f.ruleId.startsWith('nl.'))
      .toList();

  Set<String> rules(String text) => scan(text).map((f) => f.ruleId).toSet();

  group('nl.btw_id_legacy — de enige met een checksum', () {
    test('een oud btw-nummer waarvan de negen cijfers een BSN zijn, vuurt', () {
      // 111222333 haalt de 11-proef; dit is de vorm van vóór 2020, en die negen
      // cijfers wáren het BSN van de ondernemer.
      expect(rules('BTW: NL111222333B01'), contains('nl.btw_id_legacy'));
    });

    test('zonder contextwoord vuurt hij ook — de vorm draagt het bewijs', () {
      expect(rules('Factuur NL111222333B01'), contains('nl.btw_id_legacy'));
    });

    test('een nummer waarvan de negen cijfers geen BSN zijn, vuurt niet', () {
      // Dit is de scheiding die de regel moet maken: sinds 2020 krijgen
      // eenmanszaken een nummer dat níét van het BSN is afgeleid, en dat mag
      // geen melding opleveren op een factuurslide.
      expect(isValidNlBtwIdLegacy('NL123456789B01'), isFalse);
      expect(rules('BTW: NL123456789B01'), isEmpty);
    });

    test('de validator accepteert punten en spaties, en kleine letters', () {
      expect(isValidNlBtwIdLegacy('nl111222333b01'), isTrue);
      expect(isValidNlBtwIdLegacy('NL 111222333 B01'), isTrue);
    });
  });

  group('de vijf zonder checksum eisen een contextwoord', () {
    test('A-nummer: mét context wel, zonder context niet', () {
      expect(rules('A-nummer: 1234567890'), contains('nl.anummer'));
      expect(rules('Ordernummer 1234567890'), isNot(contains('nl.anummer')));
    });

    test('V-nummer: mét context wel, zonder context niet', () {
      expect(rules('V-nummer 2712345678'), contains('nl.vnummer'));
      expect(rules('Referentie 2712345678'), isNot(contains('nl.vnummer')));
    });

    test('BIG-nummer: mét context wel, zonder context niet', () {
      expect(rules('BIG-nummer 12345678901'), contains('nl.big'));
      expect(rules('Artikelcode 12345678901'), isNot(contains('nl.big')));
    });

    test('AGB-code: mét context wel, zonder context niet', () {
      expect(rules('AGB-code 01234567'), contains('nl.agb'));
      expect(rules('Artikel 01234567'), isNot(contains('nl.agb')));
    });

    test('PV-nummer: mét context wel, zonder context niet', () {
      expect(
        rules('Proces-verbaal PL1300-2024123456'),
        contains('nl.pv_nummer'),
      );
      expect(
        rules('Bestelling PL1300-2024123456'),
        isNot(contains('nl.pv_nummer')),
      );
    });
  });

  group('wat een zakelijk deck bevat en géén melding mag opleveren', () {
    // Dit is de reden dat vijf van de zes een contextpoort hebben. Elk van deze
    // regels heeft de vorm van een van de nummers hierboven.
    const onschuldig = [
      'Ordernummer 20250131',
      'Factuurnummer 2024000123',
      'Artikelcode 12345678',
      'Referentie 98765432101',
      'Versie 20240115',
      'Bedrag 1234567890 cent',
    ];

    for (final regel in onschuldig) {
      test('"$regel" levert geen Nederlandse nummertreffer op', () {
        expect(rules(regel), isEmpty, reason: regel);
      });
    }
  });

  group('de regels zelf', () {
    test('alle zes staan in het NL-pakket', () {
      final nl = euIdentifierRules
          .where((r) => r.country == 'NL')
          .map((r) => r.id)
          .toSet();
      expect(nl, {
        'nl.btw_id_legacy',
        'nl.vnummer',
        'nl.anummer',
        'nl.big',
        'nl.agb',
        'nl.pv_nummer',
      });
    });

    test('alleen het btw-nummer mag zonder contextwoord', () {
      // Deze test is de vangrail onder de hele familie: wie later een
      // contextpoort weghaalt "omdat de regel te weinig vindt", loopt hier vast.
      for (final rule in euIdentifierRules.where((r) => r.country == 'NL')) {
        if (rule.id == 'nl.btw_id_legacy') {
          expect(rule.contextWords, isEmpty, reason: rule.id);
          expect(rule.validate, isNotNull, reason: rule.id);
        } else {
          expect(rule.contextWords, isNotEmpty, reason: rule.id);
        }
      }
    });

    test('geen van de vijf komt boven `waarschijnlijk` uit', () {
      // Zonder checksum is het formaat geen bewijs. Dit begrenst tegelijk de
      // schade: `certain` zou als persoonskoppeling tellen en elk artikel
      // 9-trefwoord op dezelfde slide meetillen.
      for (final rule in euIdentifierRules.where(
        (r) => r.country == 'NL' && r.id != 'nl.btw_id_legacy',
      )) {
        expect(
          rule.confidence,
          isNot(PrivacyConfidence.certain),
          reason: rule.id,
        );
      }
    });
  });
}
