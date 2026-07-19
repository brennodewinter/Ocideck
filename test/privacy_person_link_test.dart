// De persoonskoppelingspoort (OCIWACHT §13.2, fase 11).
//
// Een bijzonder persoonsgegeven is pas een bijzonder persoonsgegeven als het bij
// een persoon hoort. Het Hof zegt het in C-21/23 (Lindenapotheke, §84) met zoveel
// woorden: de bestelling werd een artikel 9-gegeven doordat er een verband lag
// tussen het middel en een geïdentificeerde of identificeerbare persoon.
//
// Deze test bewaakt beide kanten van dat verband, en vooral de tweede:
//
//   1. mét koppeling escaleert de melding — anders mist de scanner precies het
//      geval waar hij voor bestaat;
//   2. zónder koppeling doet ze dat niet — anders slaat een privacyles alarm op
//      haar eigen lesmateriaal, en wordt de hele controle uitgezet.
//
// En de reikwijdte van de koppeling: een identificator koppelt slidebreed, een
// naam niet verder dan zijn eigen mededeling.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanBullets(List<String> bullets) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [Slide.create(SlideType.bullets).copyWith(bullets: bullets)],
    ),
  );

  PrivacyConfidence? confidenceOf(PrivacyScanResult result, String ruleId) {
    final matches = result.findings.where((f) => f.ruleId == ruleId);
    return matches.isEmpty ? null : matches.first.confidence;
  }

  group('de poort laat door wat bij een persoon hoort', () {
    test('een naam via een predicaat koppelt het strafrechtelijke gegeven', () {
      // Dit is het geval uit §13.1 dat vóór fase 11 volledig gemist werd: geen
      // BSN, geen label, en toch onmiskenbaar een artikel 10-gegeven.
      final result = scanBullets([
        'Marieke de Vries wordt verdacht van diefstal',
      ]);
      expect(
        confidenceOf(result, 'special.criminal'),
        PrivacyConfidence.certain,
      );
    });

    test('een naam via een aanhef koppelt het gezondheidsgegeven', () {
      final result = scanBullets(['Bij mevr. De Jong is diabetes vastgesteld']);
      expect(confidenceOf(result, 'special.health'), PrivacyConfidence.certain);
    });

    test('een identificator koppelt slidebreed, ook over bullets heen', () {
      // De identificator staat in een andere bullet dan het trefwoord. Een slide
      // is klein genoeg dat "er staat hier iemand" opgaat.
      final result = scanBullets([
        'Dossier van burgerservicenummer 728398242',
        'Behandeling loopt sinds maart, diagnose gesteld in februari',
      ]);
      expect(confidenceOf(result, 'special.health'), PrivacyConfidence.certain);
    });
  });

  group('de poort houdt tegen wat bij niemand hoort', () {
    test('een slide óver de AVG blijft stil', () {
      final result = scanBullets([
        'Onder de AVG zijn gezondheidsgegevens bijzondere persoonsgegevens',
        'Een veroordeling valt onder artikel 10',
        'Denk aan een diagnose of vakbondslidmaatschap',
      ]);
      expect(result.certain, isEmpty);
      // Stil is niet hetzelfde als blind: de meldingen zijn er wél, informatief.
      expect(result.findings, isNotEmpty);
    });

    test('een naam reikt niet verder dan zijn eigen mededeling', () {
      // Dit is de fout die de vals-positievencorpustest ving: een naam bovenaan
      // een lang vrij-markdownveld tilde élk trefwoord eronder naar een harde
      // melding.
      final result = scanner.scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.freeMarkdown).copyWith(
              customMarkdown:
                  'Contactpersoon: Marieke de Vries\n'
                  '\n'
                  'Deze cursus behandelt wat een diagnose juridisch betekent.',
            ),
          ],
        ),
      );
      expect(confidenceOf(result, 'contact.name'), PrivacyConfidence.likely);
      expect(
        confidenceOf(result, 'special.health'),
        PrivacyConfidence.possible,
      );
    });

    test('een API-sleutel wijst niemand aan', () {
      final result = scanBullets([
        'export TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8',
        'De diagnose van het prestatieprobleem is helder',
      ]);
      expect(
        confidenceOf(result, 'special.health'),
        PrivacyConfidence.possible,
      );
    });

    test('een IBAN wijst niemand aan', () {
      final result = scanBullets([
        'Rekening NL02ABNA0123456789 van de vereniging',
        'Het bestuur bespreekt het vakbondslidmaatschap van de sector',
      ]);
      expect(confidenceOf(result, 'special.union'), PrivacyConfidence.possible);
    });
  });

  group('de koppeling verbreedt het bereik, niet alleen de zekerheid', () {
    test('een gekoppeld trefwoord beslaat de hele mededeling', () {
      // Alleen het woord weglakken laat de naam en de mededeling staan; dán is
      // er niets verborgen en denkt de ontvanger ten onrechte dat er iets stond.
      const line = 'Marieke de Vries meldde zich ziek met een burn-out';
      final result = scanBullets([line]);
      final health = result.findings.firstWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(health.start, 0);
      expect(health.end, line.length);
    });
  });
}
