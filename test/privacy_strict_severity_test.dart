// De strenge stand: `privacyStrictSeverity` (OCIWACHT §7).
//
// Aan tilt een `zeker`-bevinding van waarschuwing naar fout. Dat klinkt als een
// kleurtje, maar het is de enige instelling in de privacycontrole die een export
// kan tegenhouden: een fout activeert `qualityBlockExportOnErrors`. Daarom staat
// hier niet alleen dát certain schuift, maar ook dat de andere twee zekerheden
// níét meeschuiven — dat is waar de instelling gevaarlijk zou worden.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/privacy/privacy_quality_bridge.dart';

void main() {
  PrivacyFinding finding(PrivacyConfidence confidence) => PrivacyFinding(
    ruleId: 'contact.email',
    family: PrivacyFamily.contact,
    confidence: confidence,
    slideIndex: 0,
    field: 'bullets',
    fragmentIndex: 0,
    start: 0,
    end: 5,
    maskedSample: 'j…l',
  );

  MarkdownValidationSeverity severity(
    PrivacyConfidence confidence, {
    required bool strict,
  }) => privacyIssuesFrom(
    PrivacyScanResult([finding(confidence)]),
    strictSeverity: strict,
  ).single.severity;

  test('standaard staat de strenge stand uit', () {
    // De standaard is hier het hele punt: aanzetten verandert wat
    // `qualityBlockExportOnErrors` betekent voor een bestaande gebruiker, en dat
    // mag niet gebeuren doordat iemand de app bijwerkt.
    expect(const AppSettings().privacyStrictSeverity, isFalse);
  });

  test('uit blijft een zekere bevinding een waarschuwing', () {
    expect(
      severity(PrivacyConfidence.certain, strict: false),
      MarkdownValidationSeverity.warning,
    );
  });

  test('aan wordt een zekere bevinding een fout', () {
    expect(
      severity(PrivacyConfidence.certain, strict: true),
      MarkdownValidationSeverity.error,
    );
  });

  test('waarschijnlijk schuift niet mee, ook niet in de strenge stand', () {
    // Hier zit per definitie een restkans op een vals positief. Een blokkade op
    // een vals positief kost de gebruiker een export die hij niet kan afdwingen,
    // en dan is de instelling erger dan het probleem.
    for (final strict in [false, true]) {
      expect(
        severity(PrivacyConfidence.likely, strict: strict),
        MarkdownValidationSeverity.warning,
        reason: 'strict=$strict',
      );
    }
  });

  test('mogelijk blijft informatief, ook in de strenge stand', () {
    // Dit is waar de contextloze treffers landen — een kaal negencijferig getal
    // dat toevallig de 11-proef haalt. Die mogen niemand onderbreken, en al
    // helemaal geen export blokkeren.
    for (final strict in [false, true]) {
      expect(
        severity(PrivacyConfidence.possible, strict: strict),
        MarkdownValidationSeverity.informational,
        reason: 'strict=$strict',
      );
    }
  });

  test('de instelling overleeft een copyWith die haar niet noemt', () {
    // Een weggevallen veld in `copyWith` is precies het soort fout dat pas
    // opvalt wanneer een gebruiker meldt dat zijn instelling telkens terugspringt.
    const aan = AppSettings(privacyStrictSeverity: true);
    expect(
      aan.copyWith(privacyChecksEnabled: true).privacyStrictSeverity,
      isTrue,
    );
    expect(
      aan.copyWith(privacyStrictSeverity: false).privacyStrictSeverity,
      isFalse,
    );
  });
}
