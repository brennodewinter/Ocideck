/// Stable, headless presentation metadata for OciServe privacy-data category
/// codes. OciServe owns the codes; OciDeck owns their localised wording.
enum OciServePrivacyGroup {
  profile,
  learning,
  assessment,
  results,
  privacy,
  security,
  other,
}

class OciServePrivacyCategoryDefinition {
  const OciServePrivacyCategoryDefinition({
    required this.group,
    required this.dutchLabel,
    required this.dutchDescription,
  });

  final OciServePrivacyGroup group;
  final String dutchLabel;
  final String dutchDescription;
}

const _profileDescription =
    'Gegevens over uw profiel, account en plaats binnen de organisatie.';
const _learningDescription =
    'Gegevens over uw inschrijving, deelname en voortgang in lessen.';
const _assessmentDescription =
    'Gegevens over uw toetsmomenten en de vragen die daarbij zijn aangeboden.';
const _resultDescription =
    'Gegevens over bewijsstukken, behaalde resultaten en certificaten.';
const _privacyDescription =
    'Gegevens over privacyverzoeken en wie uw gegevens bekeek of wijzigde.';
const _retentionDescription =
    'Gegevens over bewaartermijnen en het verwijderen van uw gegevens.';
const _securityDescription =
    'Technische gegevens die nodig zijn voor aanmelden, beveiligen en betrouwbaar verwerken.';

const ociservePrivacyCategories = <String, OciServePrivacyCategoryDefinition>{
  'participant': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.profile,
    dutchLabel: 'Cursistprofiel',
    dutchDescription: _profileDescription,
  ),
  'accounts': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.profile,
    dutchLabel: 'Accountgegevens',
    dutchDescription: _profileDescription,
  ),
  'memberships': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.profile,
    dutchLabel: 'Lidmaatschappen',
    dutchDescription: _profileDescription,
  ),
  'enrollments': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.learning,
    dutchLabel: 'Inschrijvingen',
    dutchDescription: _learningDescription,
  ),
  'lesson_progress': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.learning,
    dutchLabel: 'Lesvoortgang',
    dutchDescription: _learningDescription,
  ),
  'playback_sessions': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.learning,
    dutchLabel: 'Bekeken lessen',
    dutchDescription: _learningDescription,
  ),
  'participations': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.learning,
    dutchLabel: 'Deelnames',
    dutchDescription: _learningDescription,
  ),
  'session_bookings': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.learning,
    dutchLabel: 'Lesreserveringen',
    dutchDescription: _learningDescription,
  ),
  'requirement_waivers': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.learning,
    dutchLabel: 'Uitzonderingen op deelname-eisen',
    dutchDescription:
        'Uitzonderingen die voor u zijn gemaakt op eisen voor deelname aan een cursus.',
  ),
  'voucher_redemptions': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.learning,
    dutchLabel: 'Gebruikte inschrijfcodes',
    dutchDescription:
        'Gegevens over inschrijfcodes die u heeft gebruikt om aan een cursus deel te nemen.',
  ),
  'attempts': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.assessment,
    dutchLabel: 'Toetspogingen',
    dutchDescription: _assessmentDescription,
  ),
  'attempt_items': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.assessment,
    dutchLabel: 'Vragen in toetspogingen',
    dutchDescription: _assessmentDescription,
  ),
  'answers': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.assessment,
    dutchLabel: 'Antwoorden',
    dutchDescription: 'De antwoorden die u bij toetsvragen heeft gegeven.',
  ),
  'evidence_uploads': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.results,
    dutchLabel: 'Bewijsstukken',
    dutchDescription: _resultDescription,
  ),
  'qualifications': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.results,
    dutchLabel: 'Kwalificaties',
    dutchDescription: _resultDescription,
  ),
  'qualification_events': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.results,
    dutchLabel: 'Wijzigingen aan kwalificaties',
    dutchDescription: _resultDescription,
  ),
  'pe_awards': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.results,
    dutchLabel: 'PE-punten',
    dutchDescription: _resultDescription,
  ),
  'pe_award_events': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.results,
    dutchLabel: 'Wijzigingen aan PE-punten',
    dutchDescription: _resultDescription,
  ),
  'certificates': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.results,
    dutchLabel: 'Certificaten',
    dutchDescription: _resultDescription,
  ),
  'privacy_requests': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.privacy,
    dutchLabel: 'Privacyverzoeken',
    dutchDescription: _privacyDescription,
  ),
  'access_audit_events': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.privacy,
    dutchLabel: 'Technisch toegangslogboek',
    dutchDescription: _privacyDescription,
  ),
  'participant_data_access_history': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.privacy,
    dutchLabel: 'Inzage en wijzigingen',
    dutchDescription: _privacyDescription,
  ),
  'participant_data_access_history_metadata': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.privacy,
    dutchLabel: 'Beschikbaarheid van het inzagespoor',
    dutchDescription: _privacyDescription,
  ),
  'retention_policies': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.privacy,
    dutchLabel: 'Bewaarregels',
    dutchDescription: _retentionDescription,
  ),
  'deletion_ledger': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.privacy,
    dutchLabel: 'Verwijderingsregister',
    dutchDescription: _retentionDescription,
  ),
  'identity_operations': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Accountbewerkingen',
    dutchDescription: _securityDescription,
  ),
  'installation_requests': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Installatieverzoeken',
    dutchDescription: _securityDescription,
  ),
  'claim_attempts': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Beheerpogingen',
    dutchDescription: _securityDescription,
  ),
  'api_idempotency_requests': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Verwerkte verzoeken',
    dutchDescription: _securityDescription,
  ),
  'installation_audit_events': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Installatiebeveiligingslogboek',
    dutchDescription: _securityDescription,
  ),
  'installation_ownership': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Beheer van de installatie',
    dutchDescription: _securityDescription,
  ),
  'access_policy_changes': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Wijzigingen in aanmeldbeveiliging',
    dutchDescription: _securityDescription,
  ),
  'invitations': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Uitnodigingen',
    dutchDescription: _securityDescription,
  ),
  'email_messages': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'E-mailberichten',
    dutchDescription: _securityDescription,
  ),
  'web_sessions': OciServePrivacyCategoryDefinition(
    group: OciServePrivacyGroup.security,
    dutchLabel: 'Aanmeldsessies',
    dutchDescription: _securityDescription,
  ),
};
