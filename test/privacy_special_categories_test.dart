import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// Bijzondere persoonsgegevens (AVG art. 9/10) en de co-occurrence-escalator.
//
// De hele familie staat of valt bij één vraag: blijft een slide die *over*
// privacy gaat stil? Zo niet, dan is een privacyles een alarmkanon en zet de
// gebruiker de controle binnen een dag uit.
void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scan(List<String> bullets) => scanner.scan(
    Deck(
      title: 'D',
      slides: [Slide.create(SlideType.bullets).copyWith(bullets: bullets)],
    ),
  );

  PrivacyFinding? findingFor(PrivacyScanResult r, String rule) =>
      r.findings.where((f) => f.ruleId == rule).firstOrNull;

  group('de co-occurrence-escalator', () {
    test('een trefwoord zonder persoon blijft een hint', () {
      // DIT is de test die de familie bruikbaar maakt. Een slide over de AVG
      // noemt deze woorden nu eenmaal; hem laten afgaan is de scanner slopen.
      final result = scan([
        'Onder de AVG zijn gezondheidsgegevens en een strafblad bijzondere '
            'persoonsgegevens. Denk aan een diagnose of een veroordeling.',
      ]);

      expect(result.certain, isEmpty);
      expect(
        result.findings.every(
          (f) => f.confidence == PrivacyConfidence.possible,
        ),
        isTrue,
      );
    });

    test('een trefwoord MÉT een persoon erbij wordt een melding', () {
      // Zodra er iemand op de slide staat om het gegeven aan te koppelen, is het
      // herleidbaar tot een persoon — en dát is wat artikel 9 beschermt.
      final result = scan(['BSN 728398242 — diagnose vastgesteld in maart']);

      final health = findingFor(result, 'special.health')!;
      expect(health.confidence, PrivacyConfidence.certain);
      expect(health.family, PrivacyFamily.specialCategory);
    });

    test('een e-mailadres telt ook als persoon', () {
      final result = scan(['j.jansen@politie.nl is verdachte in deze zaak']);
      expect(
        findingFor(result, 'special.criminal')!.confidence,
        PrivacyConfidence.certain,
      );
    });

    test('een Europees nummer telt ook als persoon', () {
      final result = scan(['PESEL 44051401359 — medicatie aangepast']);
      expect(
        findingFor(result, 'special.health')!.confidence,
        PrivacyConfidence.certain,
      );
    });

    test('een API-sleutel telt NIET als persoon', () {
      // Een geheim zegt niets over wíé. Zou het meetellen, dan escaleert een
      // technische slide met het woord "diagnose" onterecht.
      final result = scan([
        'AKIAZ4XY7QWERTY12345 — draai een diagnose op de cluster',
      ]);
      expect(
        findingFor(result, 'special.health')!.confidence,
        PrivacyConfidence.possible,
      );
    });

    test('een IBAN telt niet als persoon', () {
      final result = scan(['NL18RABO0123459876 — verslaving in het dossier']);
      expect(
        findingFor(result, 'special.health')!.confidence,
        PrivacyConfidence.possible,
      );
    });

    test('de escalatie geldt per slide, niet per deck', () {
      // Een BSN op slide 1 mag het woord "diagnose" op slide 2 niet omhoog
      // trekken: die twee staan niet naast elkaar voor de ontvanger.
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.bullets).copyWith(bullets: ['BSN 728398242']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(bullets: ['de diagnose volgt later']),
        ],
      );
      final result = scanner.scan(deck);

      final health = result.findings.firstWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.confidence, PrivacyConfidence.possible);
      expect(health.slideIndex, 1);
    });
  });

  group('genetische gegevens', () {
    test('herkent een dbSNP-identificator', () {
      expect(
        scan(['variant rs334 aangetroffen']).firedRules,
        contains('special.genetic'),
      );
    });

    test('herkent HGVS-notatie', () {
      expect(
        scan(['c.1521_1523delCTT']).firedRules,
        contains('special.genetic'),
      );
      expect(
        scan(['p.Val600Glu in het BRAF-gen']).firedRules,
        contains('special.genetic'),
      );
    });

    test('vuurt niet op gewone tekst met een punt en cijfers', () {
      expect(scan(['zie hoofdstuk 4.2 en versie 1.2.3']).firedRules, isEmpty);
      expect(scan(['rs 500 per maand']).firedRules, isEmpty);
      expect(scan(['zie p. 42 van het rapport']).firedRules, isEmpty);
      expect(scan(['rs12 is te kort']).firedRules, isEmpty);
    });
  });

  group('nl.parketnummer', () {
    test('herkent het formaat', () {
      final result = scan(['zaak 01/234567-19 loopt nog']);
      final finding = findingFor(result, 'nl.parketnummer')!;
      expect(finding.family, PrivacyFamily.specialCategory);
      expect(finding.confidence, PrivacyConfidence.likely);
    });

    test('vuurt niet op een gewone datum of breuk', () {
      expect(scan(['op 01/02-19 vergaderen we']).firedRules, isEmpty);
    });
  });

  test('tien synoniemen in één zin geven één melding, geen tien', () {
    final result = scan([
      'diagnose, medicatie, zwangerschap, depressie en kanker',
    ]);
    expect(
      result.findings.where((f) => f.ruleId == 'special.health'),
      hasLength(1),
    );
  });
}
