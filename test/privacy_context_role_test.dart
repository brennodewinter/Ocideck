// Verdachte, aangever, getuige — en meestal onbekend (OCIWACHT §13.6, fase 14).
//
// De claim die deze test bewaakt is niet "de rol wordt herkend" maar iets
// strengers: **bij twijfel geen rol**. Een tweeweg (verdachte of niet) heeft geen
// vakje voor onwetendheid en dwingt daarmee de duurste fout af — een aangeefster
// een verdachte noemen. De helft van de tests hieronder gaat dus over gevallen
// waarin het antwoord `unknown` hóórt te zijn.
//
// Dat is niet overdreven voorzichtig. VACCINE (WWW 2019) meet subjectdetectie —
// "van wie is dit gegeven?" — op F1 48,35%, tegen 90,20% voor de vraag wát het
// is. Ongeveer de helft.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_context_role.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  PrivacyPersonRole roleIn(String text) {
    final result = scanner.scan(
      Deck(
        title: 'Deck',
        slides: [
          Slide.create(SlideType.bullets).copyWith(bullets: [text]),
        ],
      ),
    );
    final criminal = result.findings.where(
      (f) => f.ruleId == 'special.criminal',
    );
    return criminal.isEmpty
        ? PrivacyPersonRole.unknown
        : criminal.first.personRole;
  }

  group('de rol wordt herkend waar de tekst hem noemt', () {
    test('verdachte', () {
      expect(roleIn('De verdachte is aangehouden'), PrivacyPersonRole.suspect);
      expect(
        roleIn('M. de Vries werd veroordeeld voor een misdrijf'),
        PrivacyPersonRole.suspect,
      );
    });

    test('aangever of slachtoffer', () {
      expect(
        roleIn('De aangeefster deed aangifte van het misdrijf'),
        PrivacyPersonRole.reporter,
      );
      expect(
        roleIn('Het slachtoffer van het misdrijf is gehoord'),
        PrivacyPersonRole.reporter,
      );
    });

    test('getuige', () {
      expect(
        roleIn('De getuige verklaarde over het misdrijf'),
        PrivacyPersonRole.witness,
      );
    });
  });

  group('bij twijfel geen rol', () {
    test('zonder trigger blijft de rol onbekend', () {
      expect(
        roleIn('Het misdrijf vond plaats op dinsdag'),
        PrivacyPersonRole.unknown,
      );
    });

    test('twee rollen in één mededeling leveren er geen op', () {
      // Er staan er twee, dus er valt niets toe te wijzen. Dit is het geval
      // waarin een tweeweg zou móéten gokken.
      expect(
        roleIn('De verdachte en de aangeefster kenden elkaar, een misdrijf'),
        PrivacyPersonRole.unknown,
      );
    });

    test('een terminatiewoord kapt het bereik van een trigger af', () {
      // Zonder terminator zou "verdachte" over de hele zin heen liggen en ook de
      // aangeefster claimen. Mét terminator ziet de tweede helft alleen zijn
      // eigen rol.
      final scope = personRoleFor(
        'De verdachte verklaarde dit maar de aangeefster sprak dat tegen',
        50,
        61,
      );
      expect(scope, PrivacyPersonRole.reporter);
    });
  });

  group('de rol reist mee naar de melding', () {
    test('een herkende rol scherpt de regelsleutel aan', () {
      final result = scanner.scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(
              bullets: ['De aangeefster deed aangifte van het misdrijf'],
            ),
          ],
        ),
      );
      final finding = result.findings.firstWhere(
        (f) => f.ruleId == 'special.criminal',
      );
      expect(finding.personRole, PrivacyPersonRole.reporter);
    });

    test('een gezondheidsgegeven kent geen verdachte', () {
      final result = scanner.scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(bullets: ['Bekend met diabetes']),
          ],
        ),
      );
      final finding = result.findings.firstWhere(
        (f) => f.ruleId == 'special.health',
      );
      expect(finding.personRole, PrivacyPersonRole.unknown);
    });
  });
}
