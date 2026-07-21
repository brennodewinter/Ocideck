import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// De Europese landpakketten in de scanner.
//
// Per land één positieve treffer en — belangrijker — het bewijs dat de scanner
// niet luider wordt van al die regels. Twintig checksums naast elkaar mogen geen
// enkel ordernummer extra laten afgaan.
void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scan(String text) => scanner.scan(
    Deck(
      title: 'D',
      slides: [
        Slide.create(SlideType.bullets).copyWith(bullets: [text]),
      ],
    ),
  );

  Set<String> rulesIn(String text) => scan(text).firedRules;

  group('checksum-regels vuren zonder contextwoord', () {
    // Deze nummers zijn zo sterk gevalideerd dat het formaat op zichzelf bewijs
    // is: een willekeurige cijferreeks haalt ze niet.
    final cases = {
      'be.rijksregister': '85073003031',
      'de.steuer_id': '49729806357',
      'fr.nir': '1 85 05 73 083 215 16',
      'es.dni': '12345678Z',
      'pl.pesel': '44051401359',
      'it.codice_fiscale': 'RSSMRA85T10A562S',
      'hr.oib': '69828986577',
      'bg.egn': '7531256005',
      'ro.cnp': '1800510123458',
      'fi.hetu': '131052-308T',
      'ee.isikukood': '37205030203',
      'is.kennitala': '290200-7170',
    };

    cases.forEach((rule, value) {
      test(rule, () {
        expect(rulesIn('gegevens: $value'), contains(rule), reason: value);
      });
    });
  });

  group('de zwakke nummers vragen om context', () {
    test('Zweeds personnummer vuurt alleen mét contextwoord', () {
      // Luhn over tien cijfers is zwak: één op de tien willekeurige reeksen
      // slaagt. Zonder de eis van een contextwoord zou dit op elk tiencijferig
      // ordernummer afgaan.
      expect(rulesIn('811218-9876'), isNot(contains('se.personnummer')));
      expect(rulesIn('personnummer 811218-9876'), contains('se.personnummer'));
    });

    test('NHS-nummer vuurt alleen mét contextwoord', () {
      expect(rulesIn('943 476 7016'), isNot(contains('uk.nhs')));
      expect(rulesIn('NHS 943 476 7016'), contains('uk.nhs'));
    });

    test('NINO heeft geen checksum en komt niet boven "waarschijnlijk"', () {
      final result = scan('National Insurance AB123456C');
      final finding = result.findings.firstWhere((f) => f.ruleId == 'uk.nino');
      expect(finding.confidence, PrivacyConfidence.likely);
      expect(finding.family, PrivacyFamily.identifier);

      // Zonder context: stil.
      expect(rulesIn('artikelcode AB123456C'), isNot(contains('uk.nino')));
    });
  });

  group('twintig checksums naast elkaar maken de scanner niet luider', () {
    test('gewone zakelijke tekst blijft schoon', () {
      // Dit is de eigenlijke test van deze PR. "Heel Europa aanzetten" is alleen
      // verdedigbaar als het geen ruis kost — en dat is precies wat een checksum
      // levert: hij kost geen precisie, hij wínt precisie.
      final corpus = [
        'Factuurnummer 100000001, betaald op 3 maart',
        'Ordernummer 202512345 staat klaar',
        'Klantnummer 847362910 in het CRM',
        'Artikelcode 123-456-789 uit de catalogus',
        'Versie 1.2.3, release 4.8.1, CVE-2024-12345',
        'Omzet 1.250.000 euro over 2024',
        'Bereikbaar op 0800 8844 tijdens kantooruren',
        'Referentie 2025-Q3-0042 bij Inkoop',
        'Serienummer SN-2024-889231-XT',
        'Zie NEN 7510, ISO 27001 en NIS2',
      ];

      for (final regel in corpus) {
        final zeker = scan(regel).certain.map((f) => f.ruleId).toSet();
        expect(zeker, isEmpty, reason: regel);
      }
    });
  });
}
