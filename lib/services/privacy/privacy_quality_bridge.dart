// De brug van de privacyscanner naar het kwaliteitspaneel.
//
// De scanner is een eigen familie met een eigen model (bereiken, zekerheid,
// regel-id's), want redactie heeft dat nodig en de kwaliteitscontrole niet. Maar
// de bevindingen horen te verschijnen wáár de gebruiker al kijkt: in het
// kwaliteitspaneel, met dezelfde badges op de thumbnails en dezelfde export-gate.
//
// Vandaar deze vertaling. Precies zoals de asynchrone contrastcheck al in het
// paneel wordt gemengd, komen privacybevindingen er als
// `SlideQualityCategory.privacy` bij.

import '../../models/markdown_validation.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide_quality.dart';

/// Vertaalt een scanresultaat naar kwaliteitsmeldingen.
List<SlideQualityIssue> privacyIssuesFrom(PrivacyScanResult scan) {
  return [for (final finding in scan.findings) _issueFrom(finding)];
}

SlideQualityIssue _issueFrom(PrivacyFinding finding) {
  return SlideQualityIssue(
    slideIndex: finding.isDeckWide ? kDeckWideSlideIndex : finding.slideIndex,
    kind: _kindFor(finding.family),
    category: SlideQualityCategory.privacy,
    severity: _severityFor(finding.confidence),
    field: finding.field,
    args: {
      'rule': finding.ruleId,
      // Gemaskeerd, nooit de volledige waarde: deze melding komt in een paneel,
      // een tooltip en straks een exportsamenvatting terecht. Een privacycontrole
      // die de gevonden BSN's in haar eigen meldingen zet, heeft het probleem
      // verplaatst in plaats van opgelost.
      'sample': finding.maskedSample,
    },
  );
}

SlideQualityIssueKind _kindFor(PrivacyFamily family) {
  return switch (family) {
    PrivacyFamily.identifier => SlideQualityIssueKind.privacyIdentifier,
    PrivacyFamily.financial => SlideQualityIssueKind.privacyFinancial,
    PrivacyFamily.contact => SlideQualityIssueKind.privacyContact,
    PrivacyFamily.digital => SlideQualityIssueKind.privacyDigital,
    PrivacyFamily.secret => SlideQualityIssueKind.privacySecret,
    PrivacyFamily.specialCategory =>
      SlideQualityIssueKind.privacySpecialCategory,
    PrivacyFamily.bulk => SlideQualityIssueKind.privacyBulk,
    PrivacyFamily.structural => SlideQualityIssueKind.privacyStructural,
  };
}

/// Zekerheid → ernst.
///
/// `certain` wordt bewust een **waarschuwing** en geen fout. Een fout zou
/// `qualityBlockExportOnErrors` bij bestaande gebruikers onbedoeld scherp zetten:
/// wie die instelling ooit aanzette voor contrastfouten, zou ineens geen deck met
/// een e-mailadres meer kunnen exporteren. De strengere variant komt als eigen
/// instelling (PRIVACY_SHIELD §7), niet als bijwerking.
///
/// `possible` blijft informatief. Dat is waar de contextloze BSN-treffers landen,
/// en die mogen niemand onderbreken — zie `privacy_scanner.dart`.
MarkdownValidationSeverity _severityFor(PrivacyConfidence confidence) {
  return switch (confidence) {
    PrivacyConfidence.certain => MarkdownValidationSeverity.warning,
    PrivacyConfidence.likely => MarkdownValidationSeverity.warning,
    PrivacyConfidence.possible => MarkdownValidationSeverity.informational,
  };
}
