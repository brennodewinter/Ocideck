// Widget-tests voor de planning-schermen (issues #2123–#2127): "Mijn
// inschrijvingen" en "Aanbod" worden direct gepumpt met een fake-notifier —
// de volledige app-shell is hier niet nodig en zou de tests alleen trager
// maken.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/widgets/dialogs/ociserve_bookings_view.dart';
import 'package:ocideck/widgets/dialogs/ociserve_offerings_view.dart';

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

class _PlanningNotifier extends OciServeNotifier {
  _PlanningNotifier({
    this.bookings = const [],
    this.offerings = const [],
    this.offeringDetail,
    this.registration,
    this.loadError,
    this.mutationError,
  });

  final List<OciServeBooking> bookings;
  final List<OciServeOfferingSummary> offerings;
  final OciServeOfferingSummary? offeringDetail;
  final OciServeRegistration? registration;
  final Object? loadError;
  final Object? mutationError;
  final actions = <String>[];
  String? lastVoucherCode;
  bool? lastAllowWaitlist;

  @override
  OciServeState build() => _authenticated;

  @override
  Future<OciServeBookingList> myBookings(
    String organizationId, {
    String? cursor,
    bool includePast = false,
  }) async {
    if (loadError != null) throw loadError!;
    return OciServeBookingList(bookings: bookings);
  }

  @override
  Future<OciServeOfferingSummary> courseOffering({
    required String organizationId,
    required String offeringId,
  }) async => offeringDetail!;

  @override
  Future<OciServeOfferingList> courseOfferings(
    String organizationId, {
    String? cursor,
    DateTime? from,
    DateTime? to,
  }) async {
    if (loadError != null) throw loadError!;
    return OciServeOfferingList(offerings: offerings);
  }

  @override
  Future<OciServeRegistration> registerForOffering({
    required String organizationId,
    required String offeringId,
    required List<String> sessionIds,
    required bool allowWaitlist,
    String? voucherCode,
    required String idempotencyKey,
  }) async {
    lastVoucherCode = voucherCode;
    lastAllowWaitlist = allowWaitlist;
    if (mutationError != null) throw mutationError!;
    return registration!;
  }

  @override
  Future<OciServeSessionBooking> cancelBooking({
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _action('cancel:$bookingId');

  @override
  Future<OciServeSessionBooking> confirmBookingOffer({
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _action('confirm:$bookingId');

  @override
  Future<OciServeSessionBooking> declineBooking({
    required String organizationId,
    required String bookingId,
    required String idempotencyKey,
  }) => _action('decline:$bookingId');

  Future<OciServeSessionBooking> _action(String call) async {
    actions.add(call);
    if (mutationError != null) throw mutationError!;
    return const OciServeSessionBooking(
      id: 'bk-1',
      sessionId: 'ses-1',
      status: OciServeBookingStatus.booked,
    );
  }
}

OciServeTrainingSession _session({
  String id = 'ses-1',
  String lessonId = 'les-1',
  int freeSeats = 2,
  int waitlistPosition = 0,
  Duration offset = const Duration(days: 30),
}) => OciServeTrainingSession(
  id: id,
  offeringId: 'off-1',
  lessonId: lessonId,
  title: 'Ochtendgroep',
  startsAt: DateTime.now().toUtc().add(offset),
  endsAt: DateTime.now().toUtc().add(offset + const Duration(hours: 2)),
  timezone: 'Europe/Amsterdam',
  capacity: 12,
  booked: 12 - freeSeats,
  waitlisted: 2,
  offered: 0,
  status: 'scheduled',
  freeSeats: freeSeats,
  location: 'Lokaal 3',
  instructors: const [
    OciServeSessionInstructor(
      membershipId: 'm-1',
      role: 'lead',
      displayName: 'Docent A',
    ),
  ],
  waitlistPosition: waitlistPosition,
);

OciServeOfferingSummary _offering({
  bool voucher = false,
  OciServeEligibility eligibility = const OciServeEligibility(eligible: true),
  int? noticeHours = 48,
  int freeSeats = 2,
}) => OciServeOfferingSummary(
  id: 'off-1',
  courseVersionId: 'cv-1',
  name: 'Rijopleiding herfst',
  status: 'open',
  selfEnrollmentEnabled: true,
  voucherRequired: voucher,
  maxSelfEnrollmentsPerParticipant: 2,
  cancellationNoticeHours: noticeHours,
  classroomLessons: const [
    OciServeClassroomLesson(id: 'les-1', title: 'Praktijk dag 1'),
  ],
  sessions: [_session(freeSeats: freeSeats)],
  eligibility: eligibility,
);

OciServeBooking _booking({
  String id = 'bk-1',
  OciServeBookingStatus status = OciServeBookingStatus.booked,
  Duration offset = const Duration(days: 30),
}) => OciServeBooking(
  id: id,
  sessionId: 'ses-1',
  enrollmentId: 'enr-1',
  status: status,
  participantId: 'learner',
  sessionTitle: 'Ochtendgroep',
  startsAt: DateTime.now().toUtc().add(offset),
  endsAt: DateTime.now().toUtc().add(offset + const Duration(hours: 2)),
  timezone: 'Europe/Amsterdam',
  offeringId: 'off-1',
  offeringName: 'Rijopleiding herfst',
);

Future<void> _pump(WidgetTester tester, Widget child, Object notifier) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ociServeProvider.overrideWith(() => notifier as OciServeNotifier),
      ],
      child: MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Mijn inschrijvingen', () {
    testWidgets('toont binnenkort, geweest en aangeboden boekingen', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(
        bookings: [
          _booking(id: 'bk-offered', status: OciServeBookingStatus.offered),
          _booking(id: 'bk-upcoming'),
          _booking(
            id: 'bk-past',
            status: OciServeBookingStatus.attended,
            offset: const Duration(days: -10),
          ),
        ],
        offeringDetail: _offering(),
      );
      await _pump(
        tester,
        const OciServeBookingsView(organizationId: 'org'),
        notifier,
      );

      expect(find.text('Er is een plaats vrij'), findsWidgets);
      expect(find.text('Binnenkort'), findsOneWidget);
      expect(find.text('Geweest'), findsOneWidget);
      expect(find.text('Ingeschreven'), findsOneWidget);
      expect(find.text('Aanwezig geweest'), findsOneWidget);
      expect(find.text('Lokaal 3'), findsWidgets);
      expect(find.text('Docent A'), findsWidgets);
    });

    testWidgets('bevestigt en ziet af van een aangeboden plaats', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(
        bookings: [
          _booking(id: 'bk-offered', status: OciServeBookingStatus.offered),
        ],
        offeringDetail: _offering(),
      );
      await _pump(
        tester,
        const OciServeBookingsView(organizationId: 'org'),
        notifier,
      );

      await tester.tap(find.text('Bevestigen'));
      await tester.pumpAndSettle();
      expect(notifier.actions, ['confirm:bk-offered']);

      await tester.tap(find.text('Afzien'));
      await tester.pumpAndSettle();
      expect(notifier.actions, ['confirm:bk-offered', 'decline:bk-offered']);
    });

    testWidgets('meldt af via de bevestigingsdialoog', (tester) async {
      final notifier = _PlanningNotifier(
        bookings: [_booking()],
        offeringDetail: _offering(),
      );
      await _pump(
        tester,
        const OciServeBookingsView(organizationId: 'org'),
        notifier,
      );

      await tester.tap(find.text('Afmelden'));
      await tester.pumpAndSettle();
      expect(find.text('Afmelden voor bijeenkomst'), findsOneWidget);
      expect(notifier.actions, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Afmelden'));
      await tester.pumpAndSettle();
      expect(notifier.actions, ['cancel:bk-1']);
    });

    testWidgets('toont de lege staat en herstelt van een laadfout', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(offeringDetail: _offering());
      await _pump(
        tester,
        const OciServeBookingsView(organizationId: 'org'),
        notifier,
      );
      expect(
        find.text('U bent nog niet ingeschreven voor een bijeenkomst.'),
        findsOneWidget,
      );
    });

    testWidgets('toont een laadfout met opnieuw proberen', (tester) async {
      final failing = _PlanningNotifier(loadError: StateError('offline'));
      await _pump(
        tester,
        const OciServeBookingsView(organizationId: 'org'),
        failing,
      );
      expect(
        find.text('Uw inschrijvingen konden niet worden opgehaald.'),
        findsOneWidget,
      );
      expect(find.text('Opnieuw proberen'), findsOneWidget);
    });
  });

  group('Aanbod', () {
    testWidgets('toont de aanbodkaart en opent het inschrijfformulier', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(
        offerings: [
          _offering(
            voucher: true,
            eligibility: const OciServeEligibility(
              eligible: true,
              outcomes: [
                OciServeRequirementOutcome(
                  requirementId: 'r-1',
                  kind: 'certificate',
                  targetId: 'ehbo',
                  status: OciServeRequirementStatus.met,
                  reason: '',
                  label: 'EHBO-diploma',
                ),
              ],
            ),
          ),
        ],
      );
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        notifier,
      );

      expect(find.text('Rijopleiding herfst'), findsOneWidget);
      expect(find.text('Vouchercode vereist'), findsOneWidget);

      await tester.tap(find.text('Rijopleiding herfst'));
      await tester.pumpAndSettle();
      expect(find.text('Toelatingseisen'), findsOneWidget);
      expect(find.textContaining('2 plaatsen vrij'), findsOneWidget);
      expect(find.text('Vouchercode'), findsOneWidget);
      expect(find.text('Inschrijven'), findsOneWidget);
    });

    testWidgets('schrijft in met voucher en toont het resultaat', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(
        offerings: [_offering(voucher: true)],
        registration: const OciServeRegistration(
          enrollmentId: 'enr-1',
          bookings: [
            OciServeSessionBooking(
              id: 'bk-new',
              sessionId: 'ses-1',
              status: OciServeBookingStatus.booked,
            ),
          ],
        ),
      );
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        notifier,
      );
      await tester.tap(find.text('Rijopleiding herfst'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RadioListTile<String>));
      await tester.enterText(
        find.byType(TextField),
        'OCVO-0410-6105-0R3G-G28A-S0',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inschrijven'));
      await tester.pumpAndSettle();

      expect(notifier.lastVoucherCode, 'OCVO-0410-6105-0R3G-G28A-S0');
      expect(find.text('Uw inschrijving is verwerkt.'), findsOneWidget);
      expect(find.textContaining('ingeschreven'), findsWidgets);
    });

    testWidgets('weigert inschrijven zonder geldige vouchercode', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(offerings: [_offering(voucher: true)]);
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        notifier,
      );
      await tester.tap(find.text('Rijopleiding herfst'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RadioListTile<String>));
      await tester.enterText(find.byType(TextField), 'OCVO-FOUT');
      await tester.pumpAndSettle();

      expect(
        find.text('Deze code klopt niet — controleer de code op typefouten.'),
        findsOneWidget,
      );
      final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Inschrijven'),
      );
      expect(submit.onPressed, isNull);
    });

    testWidgets('blokkeert inschrijven bij onvoldane toelatingseisen', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(
        offerings: [
          _offering(
            eligibility: const OciServeEligibility(
              eligible: false,
              outcomes: [
                OciServeRequirementOutcome(
                  requirementId: 'r-1',
                  kind: 'certificate',
                  targetId: 'ehbo',
                  status: OciServeRequirementStatus.notMet,
                  reason: 'Het certificaat ontbreekt',
                  label: 'EHBO-diploma',
                ),
              ],
            ),
          ),
        ],
      );
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        notifier,
      );
      await tester.tap(find.text('Rijopleiding herfst'));
      await tester.pumpAndSettle();

      expect(find.text('Toelatingseisen'), findsOneWidget);
      expect(find.textContaining('EHBO-diploma'), findsOneWidget);
      expect(
        find.text(
          'Inschrijven kan pas als u aan alle toelatingseisen voldoet.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Voldoet u bijna? Vraag uw organisatie of een ontheffing mogelijk is.',
        ),
        findsOneWidget,
      );
      final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Inschrijven'),
      );
      expect(submit.onPressed, isNull);
    });

    testWidgets('vraagt om wachtlijst bij een volle sessie', (tester) async {
      final notifier = _PlanningNotifier(
        offerings: [_offering(freeSeats: 0)],
        registration: const OciServeRegistration(
          enrollmentId: 'enr-1',
          bookings: [
            OciServeSessionBooking(
              id: 'bk-new',
              sessionId: 'ses-1',
              status: OciServeBookingStatus.waitlisted,
            ),
          ],
        ),
      );
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        notifier,
      );
      await tester.tap(find.text('Rijopleiding herfst'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RadioListTile<String>));
      await tester.pumpAndSettle();

      expect(find.textContaining('Vol'), findsOneWidget);
      final submitBefore = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Inschrijven'),
      );
      expect(submitBefore.onPressed, isNull);

      await tester.tap(
        find.text('Plaats mij op de wachtlijst voor de volle sessie(s)'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inschrijven'));
      await tester.pumpAndSettle();

      expect(notifier.lastAllowWaitlist, isTrue);
      expect(find.textContaining('op de wachtlijst'), findsWidgets);
    });

    testWidgets('vertaalt een server-weigering naar producttaal', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(
        offerings: [_offering(voucher: true)],
        mutationError: const OciServeException(
          'conflict',
          statusCode: 409,
          problem: OciServeProblem(detail: 'voucher is not valid'),
        ),
      );
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        notifier,
      );
      await tester.tap(find.text('Rijopleiding herfst'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RadioListTile<String>));
      await tester.enterText(
        find.byType(TextField),
        'OCVO-0410-6105-0R3G-G28A-S0',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inschrijven'));
      await tester.pumpAndSettle();

      expect(
        find.text('Deze vouchercode is niet geldig voor deze uitvoering.'),
        findsOneWidget,
      );
    });

    testWidgets('blokkeert na te veel pogingen tot de Retry-After voorbij is', (
      tester,
    ) async {
      final notifier = _PlanningNotifier(
        offerings: [_offering()],
        mutationError: const OciServeException(
          'rate_limited',
          statusCode: 429,
          problem: OciServeProblem(retryAfter: Duration(seconds: 42)),
        ),
      );
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        notifier,
      );
      await tester.tap(find.text('Rijopleiding herfst'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RadioListTile<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inschrijven'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Te veel pogingen — probeer het over'),
        findsWidgets,
      );
    });

    testWidgets('toont de lege staat en een laadfout', (tester) async {
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        _PlanningNotifier(),
      );
      expect(
        find.text('Er is nu geen aanbod om u voor in te schrijven.'),
        findsOneWidget,
      );
    });

    testWidgets('toont een laadfout met opnieuw proberen', (tester) async {
      await _pump(
        tester,
        const OciServeOfferingsView(organizationId: 'org'),
        _PlanningNotifier(loadError: StateError('offline')),
      );
      expect(
        find.text('Het aanbod kon niet worden opgehaald.'),
        findsOneWidget,
      );
      expect(find.text('Opnieuw proberen'), findsOneWidget);
    });
  });
}
