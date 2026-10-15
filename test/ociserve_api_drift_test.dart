// Contract-drift gate: every OciServe route that ociserve_gateway.dart calls
// must exist in the pinned OpenAPI spec, with the right method and the
// response fields OciDeck reads.  When OciServe renames, removes or reshapes
// a route, this test goes red — *before* a user hits a broken endpoint.
//
// Pinned spec:  test/fixtures/ociserve_openapi.yaml
// OciServe commit:  3c7c40f39456c71259b5958204de405b9dbd35af
//
// Updaten:  zie docs/CHECKS.md → "OciServe contractpoort".

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_privacy_dictionary.dart';

/// The OciServe commit the pinned spec was copied from.
const pinnedOciServeCommit = '3c7c40f39456c71259b5958204de405b9dbd35af';

/// SHA-256 of the pinned spec file itself — a spec silently replaced or
/// hand-edited shows up here, not in a subtle field rename.
const pinnedOciServeSpecSha256 =
    'c94de1dd15b6d384997652e6844d2e8a6c14b82e53529058d87a7cf1981e5c27';

/// The capability catalogue the pinned spec declares (`info.x-capability-
/// catalog-version`) and the intake capabilities OciDeck may rely on.
const pinnedCapabilityCatalogVersion = 10;
const pinnedIntakeCapabilities = {
  'intake:publish',
  'intake:manage',
  'intake:read',
};

/// One route the gateway calls, with the response fields OciDeck reads.
/// Fields are dot-paths into the JSON response (after $ref resolution).
/// An empty [responseFields] list means OciDeck does not parse the body
/// (binary download, or fire-and-forget POST).
class GatewayRoute {
  const GatewayRoute({
    required this.method,
    required this.path,
    this.responseFields = const [],
    this.responseSchema, // expected schema name for 200/201 responses
    this.security,
  });

  final String method;
  final String path;
  final List<String> responseFields;
  final String? responseSchema;

  /// The security scheme the operation must declare: a scheme name from
  /// `components.securitySchemes` (`'BearerAuth'`, `'IntakeGrant'`), or
  /// `'none'` for a public operation (`security: []`). `null` skips the
  /// check — the intake routes all carry an explicit value so a scheme
  /// rename or an accidental public route goes red.
  final String? security;
}

/// Every route ociserve_gateway.dart calls, with the fields it reads.
/// Adding a route to the gateway means adding it here too — that is the
/// point: the list is the contract, and the test checks it against the spec.
const gatewayRoutes = <GatewayRoute>[
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/installation',
    security: 'none',
    responseSchema: 'InstallationStatus',
    // OciDeck reads these from the top level (with an oidc.* fallback).
    responseFields: ['ocideck_native_client_id', 'oidc_issuer'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/me',
    responseSchema: 'MeResponse',
    responseFields: [
      'account.id',
      'account.display_name',
      'account.email',
      'account.avatar_hash',
      'memberships',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/learning-feed',
    responseSchema: 'SelfLearningFeed',
    responseFields: ['courses'],
  ),
  GatewayRoute(
    method: 'POST',
    path:
        '/api/v1/organizations/{}/me/course-versions/{}/lessons/{}/playback-sessions',
    responseFields: [
      'id',
      'package_password',
      'package_url',
      'package_profile',
      'expires_at',
      'digest',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/lesson-playback-sessions/{}/package',
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/lesson-playback-sessions/{}/close',
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/assets/{}',
    // Binary download — no JSON fields to check.
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/me/avatar',
    // Binary download — no JSON fields to check.
  ),
  // — Account-audit en profielfoto (#2428) —
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/auth/ocideck-login',
    // 204 audit-registratie — geen body om te lezen.
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/course-versions/{}/lessons/{}/opened',
    // 204 audit-registratie — geen body om te lezen.
  ),
  GatewayRoute(
    method: 'PUT',
    path: '/api/v1/me/avatar',
    responseSchema: 'AvatarResponse',
    responseFields: ['hash'],
  ),
  GatewayRoute(
    method: 'DELETE',
    path: '/api/v1/me/avatar',
    // 204 — geen body om te lezen.
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/learning-state',
    responseSchema: 'LearningState',
    responseFields: ['lessons'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/privacy-data',
    responseSchema: 'SelfPrivacyDataResponse',
    responseFields: [
      'schema_version',
      'participant_id',
      'generated_at',
      'data',
      'omissions',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/playback-sessions',
    // Fire-and-forget POST — no response fields to check.
  ),
  // — Formele kandidaat-examens —
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/exam-sessions',
    responseFields: [
      'exam_sessions',
      'server_time',
      'exam_sessions.image_hash',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/exam-results',
    responseFields: [
      'results',
      'server_time',
      'results.attempt_id',
      'results.exam_session_id',
      'results.title',
      'results.image_hash',
      'results.status',
      'results.submitted_at',
      'results.released_at',
      'results.total_items',
      'results.correct_items',
      'results.percentage',
      'results.passed',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/exam-sessions/{}/attempts',
    responseFields: ['id', 'participant_id', 'status', 'started_at'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/attempts/{}/items/current',
    responseFields: [
      'attempt_id',
      'attempt_item_id',
      'content',
      'option_order',
      'revision',
      'challenge',
    ],
  ),
  GatewayRoute(
    method: 'PUT',
    path: '/api/v1/organizations/{}/me/attempts/{}/items/{}/answer',
    responseFields: [
      'attempt_id',
      'attempt_item_id',
      'revision',
      'accepted_at',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/attempts/{}/submit',
    responseFields: ['id', 'participant_id', 'status', 'submitted_at'],
  ),
  // — Evidence & badges —
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/participants/{}/evidence',
    responseSchema: 'EvidenceList',
    responseFields: ['uploads'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/participants/{}/qualifications',
    responseSchema: 'QualificationList',
    responseFields: ['qualifications'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/evidence-uploads',
    responseSchema: 'EvidenceResponse',
    responseFields: ['id', 'status'],
  ),
  GatewayRoute(
    method: 'PUT',
    path: '/api/v1/organizations/{}/evidence-uploads/{}/content',
    responseSchema: 'EvidenceResponse',
    responseFields: ['id', 'status'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/evidence-uploads/{}/content',
    // Binary download — no JSON fields to check.
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/evidence-uploads/{}',
    responseSchema: 'EvidenceResponse',
    responseFields: ['id', 'status'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/evidence-types',
    responseSchema: 'EvidenceTypeList',
    responseFields: [
      'evidence_types',
      'evidence_types.id',
      'evidence_types.slug',
      'evidence_types.title',
      'evidence_types.status',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/participants/{}/evidence-items',
    responseSchema: 'EvidenceItemResponse',
    responseFields: [
      'id',
      'evidence_type_id',
      'content_status',
      'upload_id',
      'declared_valid_until',
      'review_note',
      'created_at',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/participants/{}/evidence-items',
    responseSchema: 'EvidenceItemList',
    responseFields: [
      'evidence_items',
      'evidence_items.id',
      'evidence_items.evidence_type_id',
      'evidence_items.content_status',
      'evidence_items.upload_id',
      'evidence_items.declared_valid_until',
      'evidence_items.review_note',
      'evidence_items.created_at',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/evidence-types/{}/versions',
    responseSchema: 'EvidenceTypeVersionList',
    responseFields: ['versions', 'versions.id', 'versions.version'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/participants/{}/evidence-items/{}/withdraw',
    responseSchema: 'EvidenceItemResponse',
    responseFields: ['id', 'content_status'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/participants/{}/portfolio-imports',
    responseSchema: 'PortfolioImportCreateResponse',
    responseFields: ['import_id'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/participants/{}/portfolio-imports/{}',
    responseSchema: 'PortfolioImportResponse',
    responseFields: [
      'import_id',
      'status',
      'items',
      'items.id',
      'items.title',
      'items.issuer_id',
      'items.selected',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path:
        '/api/v1/organizations/{}/participants/{}/portfolio-imports/{}/select',
    responseSchema: 'PortfolioImportSelectResponse',
    responseFields: ['created_item_ids'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/skills',
    responseSchema: 'SkillList',
    responseFields: ['skills', 'skills.id', 'skills.title'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/skills/{}/versions',
    responseSchema: 'SkillVersionList',
    responseFields: ['versions', 'versions.id'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/participants/{}/skills/{}/badge-readiness',
    responseSchema: 'BadgeReadiness',
    responseFields: [
      'skill_id',
      'skill_title',
      'kwalificatiesoort',
      'validity_months',
      'requirements',
      'requirements.kind',
      'requirements.title',
      'requirements.met',
      'requirements.evidence_type',
      'requirements.course_id',
      'requirements.blueprint_id',
      'requirements.min_assurance',
      'ready',
    ],
  ),
  // — Certificaten (#2426): lijst + PDF-download —
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/participants/{}/certificates',
    responseSchema: 'CertificateList',
    responseFields: [
      'certificates',
      'certificates.id',
      'certificates.title',
      'certificates.description',
      'certificates.certificate_number',
      'certificates.status',
      'certificates.issued_at',
      'certificates.revoked_at',
      'certificates.revocation_reason',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/certificates/{}/pdf',
    // Binary PDF — no JSON schema to check.
  ),
  // — Uitnodigingen (#2425): preview en registratie zijn publiek
  // (security: []), acceptatie loopt op de bestaande sessie —
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/invitation-registration-preview',
    security: 'none',
    responseSchema: 'InvitationRegistrationPreview',
    responseFields: ['invited_email'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/invitation-registrations',
    security: 'none',
    responseSchema: 'InvitationAcceptResult',
    responseFields: ['organization_id', 'role'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/invitation-acceptances',
    responseSchema: 'InvitationAcceptResult',
    responseFields: ['organization_id', 'role'],
  ),
  // — Agenda-abonnement (#2427): eenmalige feed-URL uitgeven/roteren en
  // intrekken. De `.ics`-feed zelf haalt de agenda-app van de gebruiker op —
  // OciDeck roept hem niet aan en hoeft hem hier dus niet te registreren.
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/calendar-subscription',
    responseSchema: 'CalendarSubscription',
    responseFields: ['url', 'expires_at'],
  ),
  GatewayRoute(
    method: 'DELETE',
    path: '/api/v1/organizations/{}/me/calendar-subscription',
    // 204 — no body.
  ),
  // — Themaregister (#2429): delen, ophalen met ETag, bijwerken met
  // If-Match en verwijderen (409 = ingebouwd/in gebruik) —
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/themes',
    responseSchema: 'ThemeList',
    responseFields: [
      'themes',
      'themes.id',
      'themes.name',
      'themes.definition',
      'themes.is_builtin',
      'next_cursor',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/themes/{}',
    responseSchema: 'ThemeItem',
    responseFields: ['id', 'name', 'definition', 'is_builtin'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/themes',
    responseSchema: 'ThemeItem',
    responseFields: ['id', 'name', 'definition', 'is_builtin'],
  ),
  GatewayRoute(
    method: 'PUT',
    path: '/api/v1/organizations/{}/themes/{}',
    responseSchema: 'ThemeItem',
    responseFields: ['id', 'name', 'definition', 'is_builtin'],
  ),
  GatewayRoute(
    method: 'DELETE',
    path: '/api/v1/organizations/{}/themes/{}',
    // 204 — no body.
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/badges',
    // Returns an external URL — minimal schema check.
  ),
  // — Planning: zelfinschrijving (self-service) —
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/course-offerings',
    responseSchema: 'SelfOfferingList',
    responseFields: ['offerings', 'next_cursor'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/course-offerings/{}',
    responseFields: [
      'id',
      'name',
      'voucher_required',
      'cancellation_notice_hours',
      'classroom_lessons',
      'sessions',
      'eligibility',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/course-offerings/{}/registrations',
    responseSchema: 'RegistrationResponse',
    responseFields: ['enrollment_id', 'bookings'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/me/bookings',
    responseSchema: 'MyBookingList',
    responseFields: ['bookings'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/bookings/{}/cancel',
    responseSchema: 'SessionBookingResponse',
    responseFields: ['id', 'session_id', 'status'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/bookings/{}/confirm',
    responseSchema: 'SessionBookingResponse',
    responseFields: ['id', 'session_id', 'status'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/me/bookings/{}/decline',
    responseSchema: 'SessionBookingResponse',
    responseFields: ['id', 'session_id', 'status'],
  ),
  // — Managed Intake: organisator (OIDC + tenantcapability × per-form grant) —
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/intake-forms',
    security: 'BearerAuth',
    responseSchema: 'IntakeFormListResponse',
    responseFields: [
      'items',
      'items.form_id',
      'items.name',
      'items.operational_status',
      'items.active_version',
      'items.my_grant',
      'next_cursor',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/intake-forms',
    security: 'BearerAuth',
    responseSchema: 'IntakeForm',
    responseFields: [
      'form_id',
      'form_ref',
      'name',
      'operational_status',
      'active_version',
      'versions',
      'created_at',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/intake-forms/{}',
    security: 'BearerAuth',
    responseSchema: 'IntakeForm',
    responseFields: [
      'form_id',
      'form_ref',
      'name',
      'operational_status',
      'active_version',
      'versions',
    ],
  ),
  GatewayRoute(
    method: 'PATCH',
    path: '/api/v1/organizations/{}/intake-forms/{}',
    security: 'BearerAuth',
    responseSchema: 'IntakeForm',
    responseFields: ['form_id', 'operational_status'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/intake-forms/{}/versions',
    security: 'BearerAuth',
    responseSchema: 'IntakeFormVersion',
    responseFields: ['version', 'sha256', 'published_at', 'snapshot'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/intake-forms/{}/versions/{}',
    security: 'BearerAuth',
    responseSchema: 'IntakeFormVersion',
    responseFields: ['version', 'sha256', 'published_at', 'snapshot'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/intake-forms/{}/submissions',
    security: 'BearerAuth',
    responseSchema: 'IntakeSubmissionListResponse',
    responseFields: [
      'items',
      'items.submission_id',
      'items.state',
      'items.revision',
      'items.handled',
      'items.submitted_at',
      'next_cursor',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/organizations/{}/intake-forms/{}/submissions/{}',
    security: 'BearerAuth',
    responseSchema: 'IntakeSubmissionDetail',
    responseFields: [
      'submission_id',
      'state',
      'revision',
      'handled',
      'created_at',
      'revisions',
    ],
  ),
  GatewayRoute(
    method: 'GET',
    path:
        '/api/v1/organizations/{}/intake-forms/{}/submissions/{}/revisions/{}/content',
    security: 'BearerAuth',
    // Binary stream — Digest header is checked client-side, no JSON fields.
  ),
  GatewayRoute(
    method: 'POST',
    path:
        '/api/v1/organizations/{}/intake-forms/{}/submissions/{}/open-correction',
    security: 'BearerAuth',
    responseSchema: 'IntakeSubmissionDetail',
    responseFields: ['submission_id', 'state', 'correction_deadline'],
  ),
  GatewayRoute(
    method: 'POST',
    path:
        '/api/v1/organizations/{}/intake-forms/{}/submissions/{}/mark-handled',
    security: 'BearerAuth',
    responseSchema: 'IntakeSubmissionDetail',
    responseFields: ['submission_id', 'handled'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/organizations/{}/intake-forms/{}/submissions/{}/purge',
    security: 'BearerAuth',
    // 202 with no body — the ledger is OciServe's, not ours to read.
  ),
  // — Managed Intake: respondent (no OIDC — public or IntakeGrant bearer) —
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/intake/forms/{}',
    security: 'none',
    responseSchema: 'IntakePublicForm',
    responseFields: [
      'form_ref',
      'version',
      'accepting',
      'operational_status',
      'snapshot',
    ],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/intake/challenges',
    security: 'none',
    responseFields: ['challenge_id', 'expires_in', 'resend_after'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/intake/challenges/{}/verify',
    security: 'none',
    responseSchema: 'IntakeGrantResponse',
    responseFields: ['grant', 'expires_in', 'purpose', 'locator', 'state'],
  ),
  GatewayRoute(
    method: 'GET',
    path: '/api/v1/intake/submissions/{}',
    security: 'IntakeGrant',
    responseSchema: 'IntakeRespondentSubmission',
    responseFields: [
      'locator',
      'state',
      'revision',
      'draft_present',
      'allowed_actions',
    ],
  ),
  GatewayRoute(
    method: 'PUT',
    path: '/api/v1/intake/submissions/{}/draft',
    security: 'IntakeGrant',
    responseSchema: 'IntakeDraftReceipt',
    responseFields: ['sha256', 'size'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/intake/submissions/{}/submit',
    security: 'IntakeGrant',
    responseSchema: 'IntakeSubmitReceipt',
    responseFields: ['revision', 'submitted_at', 'sha256', 'size'],
  ),
  GatewayRoute(
    method: 'POST',
    path: '/api/v1/intake/submissions/{}/withdraw',
    security: 'IntakeGrant',
    responseSchema: 'IntakeWithdrawReceipt',
    responseFields: ['state'],
  ),
];

/// Normalise a path so {param_name} becomes {} for comparison.
String normalisePath(String path) =>
    path.replaceAll(RegExp(r'\{[^}]+\}'), '{}');

/// Het deelnemersoppervlak van de gepinde spec (#2430): routes die OciDeck
/// als deelnemers-app wél zou kunnen aanroepen. Dat zijn de `/me/`-routes
/// van de aangemelde cursist, de participant-eigen `participants/{}/…`-paden
/// en de publieke registratie-, intake- en auth-routes. Staf-routes zoals
/// ledenbeheer, cursusbeheer en vouchers vallen er structureel buiten.
bool inOciDeckSurface(String normalisedPath) =>
    normalisedPath.contains('/me/') ||
    normalisedPath.endsWith('/me') ||
    normalisedPath.startsWith('/api/v1/organizations/{}/participants/') ||
    normalisedPath.startsWith('/api/v1/installation') ||
    normalisedPath.startsWith('/api/v1/invitation-') ||
    normalisedPath.startsWith('/api/v1/intake/') ||
    normalisedPath.startsWith('/api/v1/public/') ||
    normalisedPath.startsWith('/api/v1/auth/') ||
    normalisedPath.endsWith('/self-register');

/// Spec-routes in het deelnemersoppervlak die OciDeck bewust níét aanroept,
/// elk met de reden. Een route die hier staat moet daadwerkelijk onaangeroepen
/// blijven: zodra de gateway hem gaat gebruiken, verdwijnt de regel —
/// precies zoals de omgekeerde poort bedoeld is (#2430, naar Keiko #372).
const unusedSpecRoutes = <String, String>{
  // Browserflows van Keiko, niet van OciDeck.
  'GET /api/v1/auth/web/login': 'browseraanmelding van Keiko',
  'GET /api/v1/auth/web/callback': 'browseraanmelding van Keiko',
  'GET /api/v1/auth/web/me': 'browseraanmelding van Keiko',
  'GET /api/v1/auth/web/provider-logout': 'browseraanmelding van Keiko',
  'POST /api/v1/auth/web/logout': 'browseraanmelding van Keiko',
  'POST /api/v1/auth/web/backchannel-logout': 'browseraanmelding van Keiko',
  'POST /api/v1/auth/keiko-login': 'auditpunt van Keiko, niet van OciDeck',
  'POST /api/v1/auth/logout':
      'OciDeck logt lokaal uit; serverlogout volgt als de sessie dat vraagt',
  'POST /api/v1/installation/claim':
      'eigenaar-setup van de server, geen deelnemer',

  // De feed-URL draagt het token en wordt door de agenda-app van de
  // gebruiker gelezen — OciDeck toont hem alleen eenmalig (#2427).
  'GET /api/v1/organizations/{}/me/calendar.ics':
      'wordt door de agenda-app van de gebruiker opgehaald (#2427)',

  // Docentenopervlak dat bij Keiko hoort, niet bij de deelnemers-app.
  'GET /api/v1/organizations/{}/me/teaching-sessions':
      'docenten-overzicht; OciDeck is de deelnemers-app',

  // Legacy-pakketroute is uitgeschakeld; OciDeck gebruikt
  // lesson-playback-sessions voor het pakket.
  'GET /api/v1/organizations/{}/me/course-versions/{}/lessons/{}/package':
      'uitgeschakelde legacy-route; pakket loopt via lesson-playback-sessions',

  // Deelnemerroutes die al door een /me/-equivalent of een andere route
  // worden gedekt.
  'GET /api/v1/organizations/{}/participants/{}':
      'deelnemerprofiel komt via me en me/privacy-data',
  'GET /api/v1/organizations/{}/participants/{}/feed':
      'gedekt door me/learning-feed',
  'GET /api/v1/organizations/{}/participants/{}/versions/{}/manifest':
      'gedekt door me/lesson-playback-sessions/{}/package',
  'GET /api/v1/organizations/{}/participants/{}/versions/{}/progress':
      'gedekt door me/learning-state',
  'POST /api/v1/organizations/{}/participants/{}/versions/{}/progress':
      'gedekt door me/learning-state',
  'GET /api/v1/organizations/{}/participants/{}/attempts/{}/score':
      'gedekt door me/exam-results (#2424)',

  // Staf- en beoordelaarsroutes over participant-paden — de deelnemer zelf
  // mag ze niet aanroepen, de app hoeft ze dus ook niet te kennen.
  'GET /api/v1/organizations/{}/participants/{}/attempts': 'stafroute',
  'POST /api/v1/organizations/{}/participants/{}/attempts': 'stafroute',
  'GET /api/v1/organizations/{}/participants/{}/attempts/{}': 'stafroute',
  'POST /api/v1/organizations/{}/participants/{}/attempts/{}/submit':
      'stafroute',
  'POST /api/v1/organizations/{}/participants/{}/attempts/{}/score':
      'stafroute',
  'POST /api/v1/organizations/{}/participants/{}/attempts/{}/release':
      'stafroute',
  'GET /api/v1/organizations/{}/participants/{}/attempts/{}/answers':
      'stafroute',
  'PUT /api/v1/organizations/{}/participants/{}/attempts/{}/items/{}/answer':
      'stafroute',
  'GET /api/v1/organizations/{}/participants/{}/enrollments': 'stafroute',
  'POST /api/v1/organizations/{}/participants/{}/enrollments': 'stafroute',
  'POST /api/v1/organizations/{}/participants/{}/enrollments/{}/upgrade':
      'stafroute',
  'GET /api/v1/organizations/{}/participants/{}/participations': 'stafroute',
  'GET /api/v1/organizations/{}/participants/{}/pe-awards': 'stafroute',
  'POST /api/v1/organizations/{}/participants/{}/evidence-items/{}/review':
      'beoordelaarsroute',
  'POST /api/v1/organizations/{}/participants/{}/evidence-items/{}/source-check':
      'beoordelaarsroute',
  'POST /api/v1/organizations/{}/participants/{}/evidence-items/{}/verify-credential':
      'beoordelaarsroute',
  'POST /api/v1/organizations/{}/participants/{}/evidence-items/{}/holder-binding':
      'beoordelaarsroute',

  // Deelnemer-leesmodellen die nog geen scherm hebben — zichtbaar als
  // achterstand, niet stilletjes.
  'GET /api/v1/organizations/{}/participants/{}/evidence-items/{}':
      'bewijsstuk-detail komt mee als de detailweergave erom vraagt',
  'GET /api/v1/organizations/{}/participants/{}/evidence-items/{}/events':
      'gebeurtenissen per stuk volgen met de detailweergave',
  'GET /api/v1/organizations/{}/participants/{}/learning-statistics':
      'statistiekscherm voor de deelnemer staat niet op de planning',
  'GET /api/v1/organizations/{}/participants/{}/privacy/requests':
      'privacy-verzoekenlijst volgt met de AVG-verzoekenflow',
  'POST /api/v1/organizations/{}/participants/{}/privacy/export':
      'AVG-exportverzoek volgt met de AVG-verzoekenflow',
  'POST /api/v1/organizations/{}/participants/{}/privacy/delete':
      'AVG-verwijderverzoek volgt met de AVG-verzoekenflow',
  'POST /api/v1/organizations/{}/participants/{}/privacy/anonymize':
      'AVG-anonimiseerverzoek volgt met de AVG-verzoekenflow',

  // Zelfregistratie zonder uitnodiging is bewust uitgesteld: de
  // beleidsvraag ligt bij OciServe#661.
  'POST /api/v1/organizations/{}/self-register':
      'wacht op het registratiebeleid (OciServe#661, #2425)',

  // Verificatie door derden (werkgever, verificatieportaal) — niet de
  // deelnemers-app.
  'POST /api/v1/public/certificates/verify':
      'publieke verificatie voor derden; OciDeck is de deelnemers-app',
};

/// Resolve a $ref like '#/components/schemas/Foo' to the actual node.
dynamic resolveRef(dynamic node, String ref) {
  if (!ref.startsWith('#/')) return null;
  final parts = ref.substring(2).split('/');
  dynamic current = node;
  for (final part in parts) {
    if (current is Map) {
      current = current[part];
    } else {
      return null;
    }
  }
  return current;
}

/// Recursively resolve all $ref pointers in a schema node.
dynamic resolveAllRefs(dynamic node, dynamic root) {
  if (node is Map) {
    if (node.containsKey(r'$ref')) {
      final resolved = resolveRef(root, node[r'$ref'] as String);
      if (resolved == null) return node;
      return resolveAllRefs(resolved, root);
    }
    return Map<String, dynamic>.from({
      for (final entry in node.entries)
        entry.key.toString(): resolveAllRefs(entry.value, root),
    });
  }
  if (node is List) {
    return [for (final item in node) resolveAllRefs(item, root)];
  }
  return node;
}

/// Get the response schema for a 200/201 response of an operation.
Map<String, dynamic>? responseSchemaFor(
  Map<String, dynamic> operation,
  dynamic root,
) {
  final responses = operation['responses'] as Map<String, dynamic>?;
  if (responses == null) return null;
  // Try 200, then 201, then 202, then 2xx.
  for (final code in ['200', '201', '202', '2xx']) {
    final response = responses[code] as Map<String, dynamic>?;
    if (response == null) continue;
    final content = response['content'] as Map<String, dynamic>?;
    if (content == null) continue;
    final jsonContent = content['application/json'] as Map<String, dynamic>?;
    if (jsonContent == null) continue;
    final schema = jsonContent['schema'];
    if (schema is Map) {
      return resolveAllRefs(schema, root) as Map<String, dynamic>;
    }
  }
  return null;
}

/// Merge the `properties` maps of a schema node and its `allOf` branches —
/// SelfOffering and SelfSession extend a $ref schema this way.
Map<String, dynamic> _mergedProperties(
  Map<String, dynamic> node,
  Map<String, dynamic> root,
) {
  final merged = <String, dynamic>{
    ...(node['properties'] as Map<String, dynamic>? ?? const {}),
  };
  for (final branch in node['allOf'] as List? ?? const []) {
    final resolved = resolveAllRefs(branch, root);
    if (resolved is Map<String, dynamic>) {
      merged.addAll(_mergedProperties(resolved, root));
    }
  }
  return merged;
}

/// Check that a dot-path like 'account.id' exists in a schema map.
/// Handles nested objects via 'properties', allOf composition, and
/// descends into array 'items' for paths like 'items.form_id'.
bool schemaHasField(Map<String, dynamic>? schema, String dotPath) {
  if (schema == null) return false;
  final parts = dotPath.split('.');
  dynamic current = schema;
  for (final part in parts) {
    if (current is! Map) return false;
    // Array node: the next part addresses an element field, so walk
    // into `items` instead of looking for a property literally named.
    if (current['type'] == 'array' && current['items'] != null) {
      current = resolveAllRefs(current['items'], schema);
      if (current is! Map) return false;
    }
    final value =
        _mergedProperties(Map<String, dynamic>.from(current), schema)[part] ??
        current[part];
    if (value == null) return false;
    current = resolveAllRefs(value, schema);
  }
  return true;
}

void main() {
  late final Map<String, dynamic> spec;
  late final Map<String, Map<String, dynamic>>
  specPaths; // normalised path → {method: operation}

  setUpAll(() {
    final file = File('test/fixtures/ociserve_openapi.yaml');
    final yaml = loadYaml(file.readAsStringSync());
    // Convert to plain maps for easy traversal.
    spec = _toDart(yaml) as Map<String, dynamic>;

    final rawPaths = spec['paths'] as Map<String, dynamic>? ?? {};
    specPaths = {};
    for (final entry in rawPaths.entries) {
      final normalised = normalisePath(entry.key);
      final methods = <String, dynamic>{};
      for (final methodEntry in (entry.value as Map<String, dynamic>).entries) {
        final method = methodEntry.key.toUpperCase();
        if (['GET', 'POST', 'PUT', 'DELETE', 'PATCH'].contains(method)) {
          methods[method] = methodEntry.value;
        }
      }
      specPaths[normalised] = methods;
    }
  });

  test('pinned OpenAPI spec exists and is non-empty', () {
    expect(
      spec['openapi'],
      isNotNull,
      reason: 'test/fixtures/ociserve_openapi.yaml is not a valid OpenAPI doc',
    );
    expect(
      (spec['paths'] as Map).isNotEmpty,
      true,
      reason: 'pinned spec has no paths',
    );
  });

  test('pinned OciServe commit SHA is recorded', () {
    expect(
      pinnedOciServeCommit,
      hasLength(40),
      reason: 'The OciServe commit SHA must be a full 40-char git SHA',
    );
    expect(pinnedOciServeCommit, matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  test('pinned spec file matches its recorded SHA-256', () {
    final bytes = File('test/fixtures/ociserve_openapi.yaml').readAsBytesSync();
    expect(
      sha256.convert(bytes).toString(),
      pinnedOciServeSpecSha256,
      reason:
          'The pinned spec changed without updating pinnedOciServeSpecSha256 — '
          'renew the pin from a verifiable OciServe main commit, never in place',
    );
  });

  test('capability catalogue version and intake capabilities match', () {
    final info = spec['info'] as Map<String, dynamic>;
    expect(
      info['x-capability-catalog-version'],
      pinnedCapabilityCatalogVersion,
      reason:
          'OciServe shipped a new capability catalogue — check which '
          'capabilities changed before extending the client',
    );
    final declared = (info['x-tenant-capabilities'] as List)
        .cast<String>()
        .toSet();
    expect(
      declared.containsAll(pinnedIntakeCapabilities),
      true,
      reason:
          'A capability OciDeck relies on was renamed or removed '
          '(expected $pinnedIntakeCapabilities)',
    );
  });

  test('current exam item distinguishes completion with no-content', () {
    const path = '/api/v1/organizations/{}/me/attempts/{}/items/current';
    final operation = specPaths[path]!['GET'] as Map<String, dynamic>;
    final responses = operation['responses'] as Map<String, dynamic>;
    final complete = responses['204'] as Map<String, dynamic>?;

    expect(complete, isNotNull);
    expect(
      complete!['headers']['Cache-Control']['schema']['const'],
      'private, no-store',
    );
  });

  test('privacy-data v2 categories and omission reason stay understood', () {
    final schemas = spec['components']['schemas'] as Map<String, dynamic>;
    final response = schemas['SelfPrivacyDataResponse'] as Map<String, dynamic>;
    final responseProperties = response['properties'] as Map<String, dynamic>;
    expect(responseProperties['schema_version']['const'], 'privacy-data/v2');

    final omission = schemas['PrivacyDataOmission'] as Map<String, dynamic>;
    final omissionProperties = omission['properties'] as Map<String, dynamic>;
    expect(omissionProperties['reason']['enum'], ['third_party_data']);

    final privacyData = schemas['PrivacyData'] as Map<String, dynamic>;
    final categories = (privacyData['properties'] as Map<String, dynamic>).keys
        .toSet();
    expect(
      categories,
      ociservePrivacyCategories.keys.toSet(),
      reason:
          'Every server-declared privacy category needs an understandable OciDeck group and label',
    );
    expect(privacyData['additionalProperties'], true);
  });

  group('every gateway route exists in the pinned spec', () {
    for (final route in gatewayRoutes) {
      test('${route.method} ${route.path}', () {
        final normalised = normalisePath(route.path);
        final methods = specPaths[normalised];
        expect(
          methods,
          isNotNull,
          reason:
              'Path $normalised not found in pinned spec — route removed or renamed in OciServe',
        );
        expect(
          methods!.containsKey(route.method),
          true,
          reason:
              'Method ${route.method} not found on $normalised in pinned spec',
        );
      });
    }
  });

  group('declared security scheme matches how OciDeck authenticates', () {
    for (final route in gatewayRoutes) {
      if (route.security == null) continue;

      test('${route.method} ${route.path}', () {
        final normalised = normalisePath(route.path);
        final operation =
            specPaths[normalised]?[route.method] as Map<String, dynamic>?;
        expect(
          operation,
          isNotNull,
          reason: 'Operation not found for $normalised ${route.method}',
        );

        // An operation without its own `security` inherits the spec-level
        // requirement (BearerAuth); `security: []` means public.
        final declared = operation!['security'] ?? spec['security'];
        final schemes = declared is List
            ? declared.expand((req) => (req as Map).keys.cast<String>()).toSet()
            : <String>{};
        if (route.security == 'none') {
          expect(
            declared,
            isA<List<dynamic>>().having((l) => l.isEmpty, 'empty', isTrue),
            reason:
                '$normalised ${route.method} is called without credentials '
                'but the spec secures it — organiser and respondent auth '
                'must stay strictly separated',
          );
        } else {
          expect(
            schemes,
            contains(route.security),
            reason:
                '$normalised ${route.method} no longer accepts '
                '${route.security} in the pinned spec',
          );
        }
      });
    }
  });

  group('response fields OciDeck reads exist in the spec schema', () {
    for (final route in gatewayRoutes) {
      if (route.responseFields.isEmpty) continue;

      test('${route.method} ${route.path}', () {
        final normalised = normalisePath(route.path);
        final operation =
            specPaths[normalised]?[route.method] as Map<String, dynamic>?;
        expect(
          operation,
          isNotNull,
          reason: 'Operation not found for $normalised ${route.method}',
        );

        final schema = responseSchemaFor(operation!, spec);
        expect(
          schema,
          isNotNull,
          reason:
              'No JSON response schema found for $normalised ${route.method}',
        );

        for (final field in route.responseFields) {
          expect(
            schemaHasField(schema, field),
            true,
            reason:
                'Field "$field" not found in response schema of $normalised ${route.method} — '
                'the server renamed or removed a field OciDeck reads',
          );
        }
      });
    }
  });

  test('no gateway route is missing from the gatewayRoutes list', () {
    // This is a sanity check: if someone adds a route to the gateway but
    // forgets to add it here, the test count won't match. We can't
    // automatically count _api() calls in a Dart test, but we can at least
    // verify the list is non-empty and covers the known routes.
    expect(
      gatewayRoutes.length,
      greaterThanOrEqualTo(16),
      reason: 'The gateway calls at least 16 routes; the list must cover them',
    );
  });

  // — De omgekeerde richting (#2430): routes die de server voor deelnemers
  // biedt maar die niemand in OciDeck aanroept, mogen niet onzichtbaar
  // blijven. —
  test(
    'every participant-facing spec route is called or consciously excepted',
    () {
      final called = {
        for (final route in gatewayRoutes) '${route.method} ${route.path}',
      };
      final missing = <String>[];
      for (final entry in specPaths.entries) {
        if (!inOciDeckSurface(entry.key)) continue;
        for (final method in entry.value.keys) {
          final key = '$method ${entry.key}';
          if (!called.contains(key) && !unusedSpecRoutes.containsKey(key)) {
            missing.add(key);
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'Nieuwe deelnemersroutes in de pin: sluit ze aan in de gateway, of '
            'zet ze met een reden in unusedSpecRoutes — $missing',
      );
    },
  );

  test(
    'every unused exception exists in spec, is uncalled and has a reason',
    () {
      final called = {
        for (final route in gatewayRoutes) '${route.method} ${route.path}',
      };
      for (final entry in unusedSpecRoutes.entries) {
        final split = entry.key.split(' ');
        expect(split.length, 2, reason: 'sleutel "METHOD pad" verwacht');
        final (method, path) = (split[0], split[1]);
        expect(
          specPaths[path]?[method],
          isNotNull,
          reason:
              '${entry.key} staat in de uitzonderingen maar niet in de '
              'gepinde spec — de route bestaat niet meer, haal de regel weg',
        );
        expect(
          called.contains(entry.key),
          isFalse,
          reason:
              '${entry.key} wordt inmiddels aangeroepen — haal de uitzondering '
              'weg, de forward-dekking is geregeld',
        );
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '${entry.key} mist een reden',
        );
      }
    },
  );
}

/// Recursively convert yaml_* nodes to plain Dart maps/lists for traversal.
dynamic _toDart(dynamic node) {
  if (node is Map) {
    return {for (final e in node.entries) e.key.toString(): _toDart(e.value)};
  }
  if (node is List) {
    return [for (final item in node) _toDart(item)];
  }
  return node;
}
