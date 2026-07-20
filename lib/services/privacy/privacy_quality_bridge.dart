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
///
/// [strictSeverity] volgt de gelijknamige instelling: aan tilt het een
/// `zeker`-bevinding van waarschuwing naar fout. De vlag is een parameter en
/// geen provider-lookup, zodat deze laag zonder Riverpod te testen blijft — de
/// aanroepers in `privacy_provider.dart` en `slide_badge_popover.dart` lezen de
/// instelling en geven haar door.
List<SlideQualityIssue> privacyIssuesFrom(
  PrivacyScanResult scan, {
  bool strictSeverity = false,
}) {
  return [
    for (final finding in scan.findings)
      _issueFrom(finding, strictSeverity: strictSeverity),
  ];
}

SlideQualityIssue _issueFrom(
  PrivacyFinding finding, {
  required bool strictSeverity,
}) {
  return SlideQualityIssue(
    slideIndex: finding.isDeckWide ? kDeckWideSlideIndex : finding.slideIndex,
    kind: _kindFor(finding.family),
    category: SlideQualityCategory.privacy,
    severity: _severityFor(finding.confidence, strictSeverity),
    field: finding.field,
    // De positie reist mee. Zonder haar weet de auteur wél dat er een naam op
    // slide 5 staat, maar niet wáár — en bij een slide vol tekst is dat het
    // verschil tussen een bruikbare melding en een raadsel. De gevonden waarde
    // blijft buiten beeld; alleen de coördinaten gaan mee.
    span: SlideQualitySpan(
      start: finding.start,
      end: finding.end,
      fragmentIndex: finding.fragmentIndex,
    ),
    args: {
      // Bij een strafrechtelijk gegeven draagt de regelsleutel de herkende rol
      // mee, zodat de melding "aangever of slachtoffer" kan zeggen in plaats van
      // het neutrale "strafrechtelijk gegeven". Zonder herkende rol blijft het
      // bij de kale sleutel — liever niets zeggen dan het verkeerde, want een
      // aangeefster een verdachte noemen is de duurste fout die hier te maken is.
      'rule': _ruleKeyFor(finding),
      // Gemaskeerd, nooit de volledige waarde: deze melding komt in een paneel,
      // een tooltip en straks een exportsamenvatting terecht. Een privacycontrole
      // die de gevonden BSN's in haar eigen meldingen zet, heeft het probleem
      // verplaatst in plaats van opgelost.
      'sample': finding.maskedSample,
    },
  );
}

/// De regelsleutel voor de melding, met de persoonsrol erin als die herkend is.
String _ruleKeyFor(PrivacyFinding finding) {
  final suffix = switch (finding.personRole) {
    PrivacyPersonRole.suspect => '.suspect',
    PrivacyPersonRole.reporter => '.reporter',
    PrivacyPersonRole.witness => '.witness',
    PrivacyPersonRole.unknown => '',
  };
  return '${finding.ruleId}$suffix';
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
    PrivacyFamily.image => SlideQualityIssueKind.privacyImage,
  };
}

/// Zekerheid → ernst.
///
/// `certain` wordt bewust een **waarschuwing** en geen fout. Een fout zou
/// `qualityBlockExportOnErrors` bij bestaande gebruikers onbedoeld scherp zetten:
/// wie die instelling ooit aanzette voor contrastfouten, zou ineens geen deck met
/// een e-mailadres meer kunnen exporteren. De strengere variant komt als eigen
/// instelling (OCIWACHT §7), niet als bijwerking.
///
/// `possible` blijft informatief. Dat is waar de contextloze BSN-treffers landen,
/// en die mogen niemand onderbreken — zie `privacy_scanner.dart`.
///
/// Die eigen instelling is er inmiddels: [strict] is `privacyStrictSeverity`.
/// Aan verschuift **alleen** `certain`. `likely` blijft een waarschuwing, want
/// daar zit per definitie een restkans op een vals positief, en een blokkade op
/// een vals positief kost de gebruiker een export die hij niet kan afdwingen.
/// `possible` blijft informatief, om de reden hierboven — ook in de strenge
/// stand hoort de contextloze treffer niemand tegen te houden.
MarkdownValidationSeverity _severityFor(
  PrivacyConfidence confidence,
  bool strict,
) {
  return switch (confidence) {
    PrivacyConfidence.certain =>
      strict
          ? MarkdownValidationSeverity.error
          : MarkdownValidationSeverity.warning,
    PrivacyConfidence.likely => MarkdownValidationSeverity.warning,
    PrivacyConfidence.possible => MarkdownValidationSeverity.informational,
  };
}
