import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/privacy/privacy_quality_bridge.dart';

void main() {
  PrivacyFinding finding({
    required String ruleId,
    required PrivacyFamily family,
    required PrivacyConfidence confidence,
    int slideIndex = 0,
  }) => PrivacyFinding(
    ruleId: ruleId,
    family: family,
    confidence: confidence,
    slideIndex: slideIndex,
    field: 'bullets',
    start: 0,
    end: 5,
    maskedSample: 'j…l',
  );

  test('een zekere bevinding wordt een waarschuwing, geen fout', () {
    // Bewust géén fout: `qualityBlockExportOnErrors` zou dan bij bestaande
    // gebruikers ineens scherp staan — wie die instelling ooit aanzette voor
    // contrastfouten, zou geen deck met een e-mailadres meer kunnen exporteren.
    final issue = privacyIssuesFrom(
      PrivacyScanResult([
        finding(
          ruleId: 'contact.email',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.certain,
        ),
      ]),
    ).single;

    expect(issue.severity, MarkdownValidationSeverity.warning);
    expect(issue.category, SlideQualityCategory.privacy);
    expect(issue.kind, SlideQualityIssueKind.privacyContact);
  });

  test('een mogelijke bevinding blijft informatief', () {
    // Hier landen de contextloze BSN-treffers. Die mogen niemand onderbreken —
    // ongeveer één op de elf willekeurige 9-cijferige getallen haalt de 11-proef.
    final issue = privacyIssuesFrom(
      PrivacyScanResult([
        finding(
          ruleId: 'nl.bsn',
          family: PrivacyFamily.identifier,
          confidence: PrivacyConfidence.possible,
        ),
      ]),
    ).single;

    expect(issue.severity, MarkdownValidationSeverity.informational);
    expect(issue.kind, SlideQualityIssueKind.privacyIdentifier);
  });

  test('de melding draagt de regel en een gemaskeerd fragment, geen waarde', () {
    final issue = privacyIssuesFrom(
      PrivacyScanResult([
        finding(
          ruleId: 'fin.iban',
          family: PrivacyFamily.financial,
          confidence: PrivacyConfidence.certain,
        ),
      ]),
    ).single;

    expect(issue.args['rule'], 'fin.iban');
    expect(issue.args['sample'], 'j…l');
    // De volledige waarde staat er niet in — een privacycontrole die de gevonden
    // gegevens in haar eigen meldingen zet, heeft het probleem verplaatst.
    expect(issue.args.values.join(), isNot(contains('jansen')));
  });

  test('een deckbrede bevinding krijgt de deckbrede sentinel', () {
    final issue = privacyIssuesFrom(
      PrivacyScanResult([
        finding(
          ruleId: 'contact.email',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.certain,
          slideIndex: kDeckWidePrivacyIndex,
        ),
      ]),
    ).single;

    expect(issue.slideIndex, kDeckWideSlideIndex);
    expect(issue.isDeckWide, isTrue);
  });

  test('elke familie heeft een eigen kind — de switch is exhaustief', () {
    for (final family in PrivacyFamily.values) {
      final issue = privacyIssuesFrom(
        PrivacyScanResult([
          finding(
            ruleId: 'x',
            family: family,
            confidence: PrivacyConfidence.certain,
          ),
        ]),
      ).single;
      expect(issue.category, SlideQualityCategory.privacy);
    }
  });
}
