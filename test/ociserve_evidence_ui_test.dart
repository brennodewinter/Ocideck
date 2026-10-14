import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/learning_session.dart';
import 'package:ocideck/models/ociserve_evidence.dart';
import 'package:ocideck/models/ociserve_evidence_item.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_portfolio.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/models/playback.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/utils/content_hash.dart';
import 'package:ocideck/widgets/dialogs/ociserve_courses_dialog.dart';
import 'package:ocideck/widgets/dialogs/ociserve_evidence.dart';
import 'package:ocideck/widgets/dialogs/ociserve_evidence_data.dart';
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
      List<OciServeEvidenceItem> evidenceItems = const [],
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
                evidenceItems: evidenceItems,
                evidenceTypes: _bhvTypes,
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

    testWidgets('clean upload without item is not yet submitted for review', (
      tester,
    ) async {
      await pumpEvidence(tester, evidenceUploads: [_cleanUpload('u1')]);
      expect(
        find.text(
          'Het bestand is ontvangen en veilig bevonden. '
          'Het is nog niet ingediend voor beoordeling.',
        ),
        findsOneWidget,
      );
      expect(find.text('Geaccepteerd'), findsNothing);
      expect(find.textContaining('Soort:'), findsNothing);
    });

    testWidgets('shows the review status of the submitted evidence item', (
      tester,
    ) async {
      await pumpEvidence(
        tester,
        evidenceUploads: [_cleanUpload('u1')],
        evidenceItems: [_item('u1', 'ingediend')],
      );
      expect(find.text('Ingediend'), findsOneWidget);
      expect(
        find.text('Ingediend. Een beoordelaar kijkt ernaar.'),
        findsOneWidget,
      );
      expect(find.text('Soort: BHV-certificaat'), findsOneWidget);
    });

    testWidgets('shows the reviewer note when more evidence is requested', (
      tester,
    ) async {
      await pumpEvidence(
        tester,
        evidenceUploads: [_cleanUpload('u1')],
        evidenceItems: [
          _item('u1', 'aanvulling_gevraagd', note: 'Pagina 2 ontbreekt'),
        ],
      );
      expect(find.text('Aanvulling gevraagd'), findsOneWidget);
      expect(
        find.text('Aanvulling gevraagd: Pagina 2 ontbreekt'),
        findsOneWidget,
      );
    });

    testWidgets('shows an accepted item and a rejected one without reason', (
      tester,
    ) async {
      await pumpEvidence(
        tester,
        evidenceUploads: [_cleanUpload('u1'), _cleanUpload('u2')],
        evidenceItems: [_item('u1', 'geaccepteerd'), _item('u2', 'afgewezen')],
      );
      expect(
        find.text('Geaccepteerd. Het bewijsstuk is goedgekeurd.'),
        findsOneWidget,
      );
      expect(
        find.text('Afgekeurd. De beoordelaar heeft geen reden opgegeven.'),
        findsOneWidget,
      );
    });

    testWidgets('ignores an item that belongs to another upload', (
      tester,
    ) async {
      await pumpEvidence(
        tester,
        evidenceUploads: [_cleanUpload('u1')],
        evidenceItems: [_item('andere', 'geaccepteerd')],
      );
      expect(find.text('Geaccepteerd'), findsNothing);
      expect(
        find.textContaining('nog niet ingediend voor beoordeling'),
        findsOneWidget,
      );
    });

    testWidgets('shows portfolio section as unavailable', (tester) async {
      await pumpEvidence(tester);
      expect(find.text('Externe portefeuille'), findsOneWidget);
      expect(find.text('Portefeuille koppelen'), findsOneWidget);
    });
  });

  group('OciServeEvidenceData', () {
    Future<OciServeEvidenceData> load(OciServeNotifier Function() make) {
      final container = ProviderContainer(
        overrides: [ociServeProvider.overrideWith(make)],
      );
      addTearDown(container.dispose);
      return OciServeEvidenceData.load(
        container.read(ociServeProvider.notifier),
        organizationId: 'org',
        participantId: 'participant-1',
      );
    }

    test('loads uploads, badges, types and submitted items together', () async {
      final data = await load(
        () => _ItemsNotifier(items: [_item('e1', 'ingediend')]),
      );
      expect(data.uploads.single.id, 'e1');
      expect(data.qualifications.single.id, 'q1');
      expect(data.types.single.title, 'BHV-certificaat');
      expect(data.items.single.uploadId, 'e1');
    });

    test('keeps uploads and badges when the items cannot be read', () async {
      final data = await load(() => _ItemsNotifier(itemsFail: true));
      expect(data.uploads, hasLength(1));
      expect(data.qualifications, hasLength(1));
      expect(data.types, isEmpty);
      expect(data.items, isEmpty);
    });

    test('keeps uploads and badges when the types cannot be read', () async {
      final data = await load(() => _ItemsNotifier(typesFail: true));
      expect(data.uploads, hasLength(1));
      expect(data.types, isEmpty);
      expect(data.items, isEmpty);
    });

    test('fails when the uploads themselves cannot be read', () async {
      expect(
        load(() => _ItemsNotifier(uploadsFail: true)),
        throwsA(isA<StateError>()),
      );
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
    final pdf = Uint8List.fromList(List<int>.generate(64, (i) => i));
    Future<({String name, Uint8List bytes})?> pickPdf() async =>
        (name: 'bhv.pdf', bytes: pdf);

    /// Opent de dialoog rechtstreeks, zodat de bestandskiezer en de wachttijd
    /// van de controle te vervangen zijn. `result.value` houdt bij wat de
    /// dialoog teruggaf: `true` na een geslaagde aanlevering.
    Future<ValueNotifier<bool?>> pumpSubmit(
      WidgetTester tester, {
      _SubmitNotifier? notifier,
      int maxPolls = 3,
    }) async {
      // Met de soortkeuze is de eerste stap hoger geworden.
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final result = ValueNotifier<bool?>(null);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ociServeProvider.overrideWith(() => notifier ?? _SubmitNotifier()),
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
                    onPressed: () async {
                      result.value = await showDialog<bool>(
                        context: context,
                        builder: (_) => OciServeEvidenceSubmit(
                          organizationId: 'org',
                          participantId: 'participant-1',
                          badgeTitle: 'BHV',
                          pollInterval: Duration.zero,
                          maxPolls: maxPolls,
                          pickFile: pickPdf,
                        ),
                      );
                    },
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
      return result;
    }

    // De Stepper bouwt de knoppen van alle stappen; alleen die van de actieve
    // stap is aan te raken.
    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text('Volgende').hitTestable());
      await tester.pumpAndSettle();
    }

    Future<void> chooseType(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('evidence-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BHV-certificaat').last);
      await tester.pumpAndSettle();
    }

    Future<void> walkToConsent(WidgetTester tester) async {
      await chooseType(tester);
      await next(tester);
      await tester.tap(find.text('Bestand kiezen'));
      await tester.pumpAndSettle();
      await next(tester);
      await next(tester);
    }

    /// De server controleert en de aanlevering loopt via wachten op de status.
    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.text('Aanleveren').hitTestable());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
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

    testWidgets('asks for a type before continuing', (tester) async {
      await pumpSubmit(tester);
      await next(tester);
      expect(find.text('Kies de soort bewijs die u aanlevert.'), findsOne);
      expect(find.text('Kies een bestand om aan te leveren.'), findsNothing);
    });

    testWidgets('explains when the organisation has no evidence types', (
      tester,
    ) async {
      await pumpSubmit(tester, notifier: _SubmitNotifier(types: const []));
      expect(
        find.textContaining('Er zijn geen soorten bewijs beschikbaar'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('evidence-type')), findsNothing);
    });

    testWidgets('says so when the evidence types cannot be loaded', (
      tester,
    ) async {
      await pumpSubmit(tester, notifier: _SubmitNotifier(typesFail: true));
      expect(
        find.text('De soorten bewijs konden niet worden geladen.'),
        findsOneWidget,
      );
    });

    testWidgets('shows file error when continuing without file', (
      tester,
    ) async {
      await pumpSubmit(tester);
      await chooseType(tester);
      await next(tester);
      // Try to continue without a file.
      await next(tester);
      expect(find.text('Kies een bestand om aan te leveren.'), findsOneWidget);
    });

    testWidgets('cancel closes the dialog', (tester) async {
      await pumpSubmit(tester);
      await tester.tap(find.text('Annuleren').first);
      await tester.pumpAndSettle();
      expect(find.text('Bewijs aanleveren'), findsNothing);
    });

    testWidgets('uploads the file and then creates the evidence item', (
      tester,
    ) async {
      final notifier = _SubmitNotifier(statuses: ['uploaded', 'clean']);
      final result = await pumpSubmit(tester, notifier: notifier);
      await walkToConsent(tester);
      await submit(tester);

      expect(notifier.slotRequests, hasLength(1));
      final request = notifier.slotRequests.single;
      expect(request.filename, 'bhv.pdf');
      expect(request.declaredType, 'application/pdf');
      expect(request.declaredSize, pdf.length);
      expect(request.declaredHash, sha256Hex(pdf));
      expect(notifier.uploads.single.id, 'slot-1');
      expect(notifier.uploads.single.bytes, pdf);
      expect(notifier.detailPolls, 2);
      expect(notifier.created, hasLength(1));
      final created = notifier.created.single;
      expect(created.typeId, 'type-bhv');
      expect(created.uploadId, 'slot-1');
      expect(created.participantId, 'participant-1');
      expect(created.validUntil, isNull);
      expect(created.key, isNotEmpty);
      expect(result.value, isTrue);
      expect(find.text('Bewijs aanleveren'), findsNothing);
    });

    testWidgets('never creates an item for a rejected upload', (tester) async {
      final notifier = _SubmitNotifier(statuses: ['rejected']);
      final result = await pumpSubmit(tester, notifier: notifier);
      await walkToConsent(tester);
      await submit(tester);

      expect(
        find.text(
          'Het bestand is geweigerd bij de controle. Kies een ander bestand.',
        ),
        findsOneWidget,
      );
      expect(notifier.created, isEmpty);
      expect(result.value, isNull);

      // Een geweigerd slot is niet te hergebruiken: de nieuwe poging vraagt
      // een nieuw slot aan.
      notifier.statuses = ['clean'];
      await submit(tester);
      expect(notifier.slotRequests, hasLength(2));
      expect(notifier.created, hasLength(1));
      expect(notifier.created.single.uploadId, 'slot-2');
      expect(result.value, isTrue);
    });

    testWidgets('keeps the slot while the check is still running', (
      tester,
    ) async {
      final notifier = _SubmitNotifier(statuses: ['uploaded']);
      final result = await pumpSubmit(tester, notifier: notifier, maxPolls: 2);
      await walkToConsent(tester);
      await submit(tester);

      expect(
        find.text(
          'Het bestand wordt nog gecontroleerd. '
          'Probeer het over enkele minuten opnieuw.',
        ),
        findsOneWidget,
      );
      expect(notifier.detailPolls, 2);
      expect(notifier.created, isEmpty);
      expect(result.value, isNull);

      // Dezelfde upload telt niet dubbel: geen tweede slot, geen tweede upload.
      notifier.statuses = ['clean'];
      await submit(tester);
      expect(notifier.slotRequests, hasLength(1));
      expect(notifier.uploads, hasLength(1));
      expect(notifier.created.single.uploadId, 'slot-1');
      expect(result.value, isTrue);
    });

    testWidgets('retries a failed item creation with the same key', (
      tester,
    ) async {
      final notifier = _SubmitNotifier(statuses: ['clean'], createFailures: 1);
      final result = await pumpSubmit(tester, notifier: notifier);
      await walkToConsent(tester);
      await submit(tester);

      expect(
        find.text('Het aanleveren is mislukt. Probeer het opnieuw.'),
        findsOneWidget,
      );
      expect(result.value, isNull);

      await submit(tester);
      expect(notifier.slotRequests, hasLength(1));
      expect(notifier.created, hasLength(2));
      expect(notifier.created.first.key, notifier.created.last.key);
      expect(result.value, isTrue);
    });

    testWidgets('reports a failure to reserve the upload slot', (tester) async {
      final notifier = _SubmitNotifier(slotFails: true);
      final result = await pumpSubmit(tester, notifier: notifier);
      await walkToConsent(tester);
      await submit(tester);

      expect(
        find.text('Het aanleveren is mislukt. Probeer het opnieuw.'),
        findsOneWidget,
      );
      expect(notifier.created, isEmpty);
      expect(result.value, isNull);
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
  Future<List<OciServeEvidenceType>> evidenceTypes(
    String organizationId,
  ) async => const [
    OciServeEvidenceType(
      id: 'type-bhv',
      slug: 'bhv-certificaat',
      title: 'BHV-certificaat',
    ),
  ];

  @override
  Future<List<OciServeEvidenceItem>> evidenceItems({
    required String organizationId,
    required String participantId,
  }) async => const [];

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

// ---------------------------------------------------------------------------
// Hulpen voor het aanleverpad
// ---------------------------------------------------------------------------

const _bhvTypes = [
  OciServeEvidenceType(
    id: 'type-bhv',
    slug: 'bhv-certificaat',
    title: 'BHV-certificaat',
  ),
];

EvidenceUpload _cleanUpload(String id) => EvidenceUpload.fromJson({
  'id': id,
  'filename': '$id.pdf',
  'declared_type': 'application/pdf',
  'declared_size': 1024,
  'declared_hash': 'h',
  'status': 'clean',
  'created_at': '2026-09-01T10:00:00Z',
});

OciServeEvidenceItem _item(String uploadId, String status, {String? note}) =>
    OciServeEvidenceItem(
      id: 'item-$uploadId',
      evidenceTypeId: 'type-bhv',
      status: OciServeEvidenceContentStatus.parse(status),
      createdAt: DateTime.utc(2026, 9, 2),
      uploadId: uploadId,
      reviewNote: note,
    );

/// Legt vast wat het aanleverpad bij de server doet. `statuses` is wat de
/// controle van de upload achtereenvolgens meldt; de laatste herhaalt zich.
class _SubmitNotifier extends _EvidenceTestNotifier {
  _SubmitNotifier({
    this.statuses = const ['clean'],
    this.types = _bhvTypes,
    this.typesFail = false,
    this.slotFails = false,
    this.createFailures = 0,
  });

  List<String> statuses;
  final List<OciServeEvidenceType> types;
  final bool typesFail;
  final bool slotFails;
  int createFailures;

  final slotRequests = <EvidenceUploadRequest>[];
  final uploads = <({String id, Uint8List bytes})>[];
  final created =
      <
        ({
          String typeId,
          String uploadId,
          String participantId,
          String key,
          DateTime? validUntil,
        })
      >[];
  int detailPolls = 0;

  EvidenceUpload _upload(String id, String status) => EvidenceUpload.fromJson({
    'id': id,
    'filename': 'bhv.pdf',
    'declared_type': 'application/pdf',
    'declared_size': 64,
    'declared_hash': 'h',
    'status': status,
    'created_at': '2026-09-01T10:00:00Z',
  });

  @override
  Future<List<OciServeEvidenceType>> evidenceTypes(
    String organizationId,
  ) async {
    if (typesFail) throw StateError('geen verbinding');
    return types;
  }

  @override
  Future<EvidenceUpload> requestEvidenceSlot({
    required String organizationId,
    required EvidenceUploadRequest request,
  }) async {
    if (slotFails) throw StateError('geen verbinding');
    slotRequests.add(request);
    return _upload('slot-${slotRequests.length}', 'pending');
  }

  @override
  Future<EvidenceUpload> uploadEvidenceContent({
    required String organizationId,
    required String evidenceId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploads.add((id: evidenceId, bytes: bytes));
    return _upload(evidenceId, 'uploaded');
  }

  @override
  Future<EvidenceUpload> evidenceDetail({
    required String organizationId,
    required String evidenceId,
  }) async {
    final index = detailPolls < statuses.length
        ? detailPolls
        : statuses.length - 1;
    detailPolls++;
    return _upload(evidenceId, statuses[index]);
  }

  @override
  Future<OciServeEvidenceItem> createEvidenceItem({
    required String organizationId,
    required String participantId,
    required String evidenceTypeId,
    required String uploadId,
    required String idempotencyKey,
    DateTime? declaredValidUntil,
  }) async {
    created.add((
      typeId: evidenceTypeId,
      uploadId: uploadId,
      participantId: participantId,
      key: idempotencyKey,
      validUntil: declaredValidUntil,
    ));
    if (createFailures > 0) {
      createFailures--;
      throw StateError('geen verbinding');
    }
    return OciServeEvidenceItem(
      id: 'item-1',
      evidenceTypeId: evidenceTypeId,
      status: OciServeEvidenceContentStatus.ingediend,
      createdAt: DateTime.utc(2026, 9, 2),
      uploadId: uploadId,
    );
  }
}

/// Een bewijsscherm waarvan de aparte onderdelen stuk kunnen gaan.
class _ItemsNotifier extends _EvidenceTestNotifier {
  _ItemsNotifier({
    this.items = const [],
    this.itemsFail = false,
    this.typesFail = false,
    this.uploadsFail = false,
  });

  final List<OciServeEvidenceItem> items;
  final bool itemsFail;
  final bool typesFail;
  final bool uploadsFail;

  @override
  Future<List<EvidenceUpload>> listEvidence({
    required String organizationId,
    required String participantId,
  }) async {
    if (uploadsFail) throw StateError('geen verbinding');
    return super.listEvidence(
      organizationId: organizationId,
      participantId: participantId,
    );
  }

  @override
  Future<List<OciServeEvidenceType>> evidenceTypes(
    String organizationId,
  ) async {
    if (typesFail) throw StateError('geen verbinding');
    return super.evidenceTypes(organizationId);
  }

  @override
  Future<List<OciServeEvidenceItem>> evidenceItems({
    required String organizationId,
    required String participantId,
  }) async {
    if (itemsFail) throw StateError('geen verbinding');
    return items;
  }
}
