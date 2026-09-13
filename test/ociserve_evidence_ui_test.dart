import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/learning_session.dart';
import 'package:ocideck/models/ociserve_evidence.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_portfolio.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/models/playback.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/widgets/dialogs/ociserve_courses_dialog.dart';
import 'package:ocideck/widgets/dialogs/ociserve_evidence.dart';
import 'package:ocideck/widgets/dialogs/ociserve_evidence_submit.dart';
import 'package:ocideck/widgets/dialogs/ociserve_portfolio_link.dart';

// ---------------------------------------------------------------------------
// Model tests — cover ociserve_portfolio.dart
// ---------------------------------------------------------------------------

void main() {
  // — Portfolio model —

  group('PortfolioCredential', () {
    test('parses from JSON with all fields', () {
      final cred = PortfolioCredential.fromJson({
        'id': 'cred-1',
        'title': 'BHV Certificaat',
        'issuer': 'ROC van Amsterdam',
        'issued_at': '2026-01-15T10:00:00Z',
        'expires_at': '2028-01-15T10:00:00Z',
        'credential_type': 'OpenBadge',
      });
      expect(cred.id, 'cred-1');
      expect(cred.title, 'BHV Certificaat');
      expect(cred.issuer, 'ROC van Amsterdam');
      expect(cred.credentialType, 'OpenBadge');
      expect(cred.issuedAt, isNotNull);
      expect(cred.expiresAt, isNotNull);
      expect(cred.isActive, isTrue);
    });

    test('isActive is true when expiresAt is null', () {
      const cred = PortfolioCredential(id: 'c', title: 't', issuer: 'i');
      expect(cred.isActive, isTrue);
    });

    test('isActive is false when expired', () {
      final cred = PortfolioCredential(
        id: 'c',
        title: 't',
        issuer: 'i',
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(cred.isActive, isFalse);
    });

    test('copyWith toggles selected', () {
      const cred = PortfolioCredential(id: 'c', title: 't', issuer: 'i');
      final selected = cred.copyWith(selected: true);
      expect(selected.selected, isTrue);
      expect(cred.selected, isFalse);
    });

    test('throws on missing id', () {
      expect(
        () => PortfolioCredential.fromJson({'title': 't'}),
        throwsFormatException,
      );
    });

    test('parses with minimal fields and defaults', () {
      final cred = PortfolioCredential.fromJson({'id': 'x'});
      expect(cred.title, isEmpty);
      expect(cred.issuer, isEmpty);
      expect(cred.credentialType, isEmpty);
      expect(cred.selected, isFalse);
    });
  });

  group('PortfolioConnection', () {
    test('parses a connected portfolio with credentials', () {
      final conn = PortfolioConnection.fromJson({
        'provider_id': 'edubadges',
        'provider_name': 'EduBadges',
        'state': 'connected',
        'connected_at': '2026-09-01T10:00:00Z',
        'credentials': [
          {'id': 'c1', 'title': 'BHV', 'issuer': 'ROC'},
          {'id': 'c2', 'title': 'EHBO', 'issuer': 'ROC'},
        ],
      });
      expect(conn.providerId, 'edubadges');
      expect(conn.providerName, 'EduBadges');
      expect(conn.state, PortfolioConnectionState.connected);
      expect(conn.credentials.length, 2);
      // fromJson does not parse `selected`; use copyWith to mark selected.
      final selected = conn.credentials[1].copyWith(selected: true);
      expect(selected.selected, isTrue);
      expect(conn.selectedCredentials, isEmpty);
    });

    test('defaults to unavailable for unknown state', () {
      final conn = PortfolioConnection.fromJson({
        'provider_id': 'p',
        'state': 'unknown',
      });
      expect(conn.state, PortfolioConnectionState.unavailable);
    });

    test('parses all known states', () {
      for (final entry in {
        'disconnected': PortfolioConnectionState.disconnected,
        'connecting': PortfolioConnectionState.connecting,
        'connected': PortfolioConnectionState.connected,
        'revoked': PortfolioConnectionState.revoked,
        'unavailable': PortfolioConnectionState.unavailable,
      }.entries) {
        final conn = PortfolioConnection.fromJson({
          'provider_id': 'p',
          'state': entry.key,
        });
        expect(conn.state, entry.value);
      }
    });

    test('throws on missing provider_id', () {
      expect(
        () => PortfolioConnection.fromJson({'state': 'connected'}),
        throwsFormatException,
      );
    });

    test('selectedCredentials is empty when none selected', () {
      final conn = PortfolioConnection.fromJson({
        'provider_id': 'p',
        'state': 'connected',
        'credentials': [
          {'id': 'c1', 'title': 'BHV', 'issuer': 'ROC'},
        ],
      });
      expect(conn.selectedCredentials, isEmpty);
    });
  });

  // — Widget tests —

  group('OciServeEvidence widget', () {
    Future<void> pumpEvidence(
      WidgetTester tester, {
      List<OciServeQualification> qualifications = const [],
      List<EvidenceUpload> evidenceUploads = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ociServeProvider.overrideWith(() => _EvidenceTestNotifier()),
          ],
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: OciServeEvidence(
                qualifications: qualifications,
                evidenceUploads: evidenceUploads,
                organizationId: 'org',
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows empty state when no badges and no uploads', (
      tester,
    ) async {
      await pumpEvidence(tester);
      expect(find.text('U hebt nog geen badges.'), findsOneWidget);
      expect(find.text('Nog geen bewijsstukken aangeleverd.'), findsOneWidget);
      expect(find.text('Bewijs aanleveren'), findsOneWidget);
    });

    testWidgets('shows badge cards and upload cards with data', (tester) async {
      await pumpEvidence(
        tester,
        qualifications: [
          OciServeQualification.fromJson({
            'id': 'q1',
            'participant_id': 'p',
            'skill_version_id': 's',
            'status': 'approved',
            'issued_by': 'a',
            'issued_at': '2026-01-15T10:00:00Z',
            'snapshot': {'title': 'Bedrijfshulpverlener'},
            'created_at': '2026-01-15T10:00:00Z',
          }),
        ],
        evidenceUploads: [
          EvidenceUpload.fromJson({
            'id': 'e1',
            'filename': 'cert.pdf',
            'declared_type': 'application/pdf',
            'declared_size': 1024,
            'declared_hash': 'h',
            'status': 'clean',
            'created_at': '2026-09-01T10:00:00Z',
          }),
        ],
      );
      expect(find.text('Mijn badges'), findsOneWidget);
      expect(find.text('Bedrijfshulpverlener'), findsOneWidget);
      expect(find.text('Mijn bewijsstukken'), findsOneWidget);
      expect(find.text('cert.pdf'), findsOneWidget);
      expect(find.text('Gecontroleerd'), findsOneWidget);
      expect(find.text('Openen'), findsOneWidget);
    });

    testWidgets('shows rejected upload with reason and next step', (
      tester,
    ) async {
      await pumpEvidence(
        tester,
        evidenceUploads: [
          EvidenceUpload.fromJson({
            'id': 'e1',
            'filename': 'scan.jpg',
            'declared_type': 'image/jpeg',
            'declared_size': 512,
            'declared_hash': 'h',
            'status': 'rejected',
            'rejection_reason': 'Onleesbaar',
            'created_at': '2026-09-01T10:00:00Z',
          }),
        ],
      );
      expect(find.text('Afgekeurd: Onleesbaar'), findsOneWidget);
      expect(
        find.text('Lever een nieuw of gecorrigeerd bestand aan.'),
        findsOneWidget,
      );
      expect(find.text('Openen'), findsNothing);
    });

    testWidgets('shows portfolio section as unavailable', (tester) async {
      await pumpEvidence(tester);
      expect(find.text('Externe portefeuille'), findsOneWidget);
      expect(find.text('Portefeuille koppelen'), findsOneWidget);
    });
  });

  group('OciServePortfolioLink widget', () {
    Future<void> pumpLink(
      WidgetTester tester, {
      required PortfolioConnection connection,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: OciServePortfolioLink(connection: connection)),
        ),
      );
      // Use pump (not pumpAndSettle) — the connecting state has a spinner
      // that animates forever and would time out pumpAndSettle.
      await tester.pump();
    }

    testWidgets('shows unavailable message', (tester) async {
      await pumpLink(
        tester,
        connection: const PortfolioConnection(
          providerId: '',
          providerName: '',
          state: PortfolioConnectionState.unavailable,
        ),
      );
      expect(find.text('Portefeuille koppelen'), findsOneWidget);
      expect(find.textContaining('nog niet beschikbaar'), findsOneWidget);
    });

    testWidgets('shows connect button when disconnected', (tester) async {
      await pumpLink(
        tester,
        connection: const PortfolioConnection(
          providerId: 'p',
          providerName: 'EduBadges',
          state: PortfolioConnectionState.disconnected,
        ),
      );
      expect(find.text('Portefeuille verbinden'), findsOneWidget);
    });

    testWidgets('shows connecting spinner', (tester) async {
      await pumpLink(
        tester,
        connection: const PortfolioConnection(
          providerId: 'p',
          providerName: 'EduBadges',
          state: PortfolioConnectionState.connecting,
        ),
      );
      // Use pump (not pumpAndSettle) — the CircularProgressIndicator animates
      // forever and would time out pumpAndSettle.
      await tester.pump();
      expect(find.text('Verbinding maken…'), findsOneWidget);
    });

    testWidgets('shows connected state with credentials', (tester) async {
      await pumpLink(
        tester,
        connection: PortfolioConnection(
          providerId: 'p',
          providerName: 'EduBadges',
          state: PortfolioConnectionState.connected,
          credentials: [
            const PortfolioCredential(
              id: 'c1',
              title: 'BHV',
              issuer: 'ROC',
              selected: true,
            ),
          ],
        ),
      );
      expect(find.textContaining('Verbonden met'), findsOneWidget);
      expect(find.text('BHV'), findsOneWidget);
      expect(find.textContaining('credential(s) geselecteerd'), findsOneWidget);
    });

    testWidgets('shows revoke button when connected', (tester) async {
      await pumpLink(
        tester,
        connection: const PortfolioConnection(
          providerId: 'p',
          providerName: 'EduBadges',
          state: PortfolioConnectionState.connected,
        ),
      );
      expect(find.text('Verbinding verbreken'), findsOneWidget);
    });

    testWidgets('shows reconnect button when revoked', (tester) async {
      await pumpLink(
        tester,
        connection: const PortfolioConnection(
          providerId: 'p',
          providerName: 'EduBadges',
          state: PortfolioConnectionState.revoked,
        ),
      );
      expect(find.text('Opnieuw verbinden'), findsOneWidget);
    });

    testWidgets('opens connect dialog from disconnected state', (tester) async {
      await pumpLink(
        tester,
        connection: const PortfolioConnection(
          providerId: 'p',
          providerName: 'EduBadges',
          state: PortfolioConnectionState.disconnected,
        ),
      );
      await tester.tap(find.text('Portefeuille verbinden'));
      await tester.pumpAndSettle();
      expect(find.text('Doorgaan'), findsOneWidget);
      await tester.tap(find.text('Doorgaan'));
      await tester.pumpAndSettle();
      expect(find.text('Kies wat u deelt'), findsOneWidget);
    });

    testWidgets('opens revoke confirm from connected state', (tester) async {
      await pumpLink(
        tester,
        connection: const PortfolioConnection(
          providerId: 'p',
          providerName: 'EduBadges',
          state: PortfolioConnectionState.connected,
        ),
      );
      await tester.tap(find.text('Verbinding verbreken'));
      await tester.pumpAndSettle();
      expect(find.text('Verbinding verbreken?'), findsOneWidget);
      expect(find.text('Verbreken'), findsOneWidget);
    });
  });

  group('OciServeEvidenceSubmit dialog', () {
    Future<void> pumpSubmit(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ociServeProvider.overrideWith(() => _EvidenceTestNotifier()),
          ],
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => OciServeEvidenceSubmit.show(
                      context,
                      organizationId: 'org',
                      badgeTitle: 'BHV',
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows four steps with badge title', (tester) async {
      await pumpSubmit(tester);
      expect(find.text('Bewijs aanleveren'), findsOneWidget);
      expect(find.text('Soort'), findsOneWidget);
      expect(find.text('Bestand'), findsOneWidget);
      expect(find.text('Geldig tot'), findsOneWidget);
      expect(find.text('Toestemming'), findsOneWidget);
      expect(find.textContaining('BHV'), findsOneWidget);
    });

    testWidgets('shows file error when continuing without file', (
      tester,
    ) async {
      await pumpSubmit(tester);
      // Step 0 → 1: continue to Bestand step (Stepper renders a control per step).
      await tester.tap(find.text('Volgende').first);
      await tester.pumpAndSettle();
      // Try to continue without a file.
      await tester.tap(find.text('Volgende').first);
      await tester.pumpAndSettle();
      expect(find.text('Kies een bestand om aan te leveren.'), findsOneWidget);
    });

    testWidgets('cancel closes the dialog', (tester) async {
      await pumpSubmit(tester);
      await tester.tap(find.text('Annuleren').first);
      await tester.pumpAndSettle();
      expect(find.text('Bewijs aanleveren'), findsNothing);
    });
  });

  // — Courses dialog evidence tab —

  group('OciServeCoursesDialog evidence tab', () {
    testWidgets('shows evidence body after navigating to Mijn bewijs', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ociServeProvider.overrideWith(() => _EvidenceTestNotifier()),
          ],
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: const Scaffold(body: OciServeCoursesDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The dialog loads courses first; navigate to the evidence tab.
      await tester.tap(find.text('Mijn bewijs'));
      await tester.pumpAndSettle();

      // After loading, the evidence body should show the evidence widget.
      expect(find.byKey(const Key('ociserve-evidence')), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Test notifier — authenticated with evidence data
// ---------------------------------------------------------------------------

const _account = OciServeAccount(
  id: 'learner',
  displayName: 'Lerende',
  memberships: [
    OciServeMembership(organizationId: 'org', name: 'Opleidingsorganisatie'),
  ],
);

const _authenticated = OciServeState(
  settings: OciServeSettings(enabled: true),
  status: OciServeStatus.authenticated,
  account: _account,
);

const _feed = <OciServeFeedItem>[];

class _EvidenceTestNotifier extends OciServeNotifier {
  @override
  OciServeState build() => _authenticated;

  @override
  Future<List<OciServeFeedItem>> learningFeed(String organizationId) async =>
      _feed;

  @override
  Future<OciServeLearningState> learningState(String organizationId) async =>
      const OciServeLearningState([]);

  @override
  Future<OciServePrivacyData> privacyData(String organizationId) async =>
      OciServePrivacyData(
        participantId: 'participant-1',
        generatedAt: DateTime.utc(2026, 9, 9),
        data: const {},
      );

  @override
  Future<List<EvidenceUpload>> listEvidence({
    required String organizationId,
    required String participantId,
  }) async => [
    EvidenceUpload.fromJson({
      'id': 'e1',
      'filename': 'cert.pdf',
      'declared_type': 'application/pdf',
      'declared_size': 1024,
      'declared_hash': 'h',
      'status': 'clean',
      'created_at': '2026-09-01T10:00:00Z',
    }),
  ];

  @override
  Future<List<OciServeQualification>> listQualifications({
    required String organizationId,
    required String participantId,
  }) async => [
    OciServeQualification.fromJson({
      'id': 'q1',
      'participant_id': 'p',
      'skill_version_id': 's',
      'status': 'approved',
      'issued_by': 'a',
      'issued_at': '2026-01-15T10:00:00Z',
      'snapshot': {'title': 'Bedrijfshulpverlener'},
      'created_at': '2026-01-15T10:00:00Z',
    }),
  ];

  @override
  Future<Uint8List> courseImage({
    required String organizationId,
    required String imageHash,
  }) async => Uint8List(0);

  @override
  Future<Uint8List> accountAvatar(String avatarHash) async => Uint8List(0);

  @override
  Future<void> reportPlayback({
    required LearningSessionRef session,
    required PlaybackReport report,
    required DateTime startedAt,
  }) async {}

  @override
  Future<void> flushPendingReports() async {}

  @override
  Future<bool> login() async => true;
}
