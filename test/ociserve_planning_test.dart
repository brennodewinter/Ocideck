import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';

class _Request {
  _Request(this.method, this.url, this.headers, this.body);
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int>? body;
}

class _FakeTransport implements OciServeHttpTransport {
  final responses = <OciServeHttpResponse>[];
  final requests = <_Request>[];

  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 0,
    Duration timeout = Duration.zero,
  }) async {
    requests.add(_Request(method, url, headers, body));
    return responses.removeAt(0);
  }
}

OciServeHttpResponse _json(
  Object value, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) => OciServeHttpResponse(
  statusCode: statusCode,
  body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
  headers: headers,
);

Map<String, Object?> _offeringJson() => {
  'id': 'off-1',
  'course_version_id': 'cv-1',
  'name': 'Rijopleiding herfst',
  'status': 'open',
  'self_enrollment_enabled': true,
  'voucher_required': true,
  'max_self_enrollments_per_participant': 2,
  'image_hash': 'a' * 64,
  'enrollment_opens_at': '2026-08-01T00:00:00Z',
  'enrollment_closes_at': '2026-11-01T00:00:00Z',
  'cancellation_notice_hours': 48,
  'classroom_lessons': [
    {'id': 'les-1', 'title': 'Praktijk dag 1'},
  ],
  'sessions': [
    {
      'id': 'ses-1',
      'course_offering_id': 'off-1',
      'lesson_id': 'les-1',
      'title': 'Ochtendgroep',
      'starts_at': '2026-10-02T08:00:00Z',
      'ends_at': '2026-10-02T10:00:00Z',
      'timezone': 'Europe/Amsterdam',
      'location': 'Lokaal 3',
      'capacity': 12,
      'booked': 10,
      'waitlisted': 2,
      'offered': 0,
      'status': 'scheduled',
      'free_seats': 2,
      'waitlist_position': 0,
      'instructors': [
        {'membership_id': 'm-1', 'role': 'lead', 'display_name': 'Docent A'},
      ],
    },
  ],
  'eligibility': {
    'eligible': false,
    'outcomes': [
      {
        'requirement_id': 'req-1',
        'kind': 'qualification',
        'target_id': 'skill-1',
        'label': 'Basisdiploma',
        'status': 'expires_before_start',
        'reason': 'diploma verloopt 2026-09-30',
      },
    ],
  },
};

void main() {
  late _FakeTransport transport;
  late OciServeGateway gateway;

  setUp(() {
    transport = _FakeTransport();
    gateway = OciServeGateway(
      settings: const OciServeSettings(
        enabled: true,
        baseUrl: 'https://learn.example',
      ),
      transport: transport,
    );
  });

  test('self-aanbod volgt de me-route en parseert uitvoeringen', () async {
    transport.responses.add(
      _json({
        'offerings': [_offeringJson()],
        'next_cursor': 'c2',
      }),
    );

    final page = await gateway.myCourseOfferings(
      accessToken: 'access',
      organizationId: 'org',
      from: DateTime.utc(2026, 10),
      to: DateTime.utc(2026, 11),
    );

    final request = transport.requests.single;
    expect(request.url.path, '/api/v1/organizations/org/me/course-offerings');
    expect(request.url.queryParameters['from'], isNotNull);
    expect(request.headers['authorization'], 'Bearer access');

    expect(page.nextCursor, 'c2');
    final offering = page.offerings.single;
    expect(offering.id, 'off-1');
    expect(offering.voucherRequired, isTrue);
    expect(offering.cancellationNoticeHours, 48);
    expect(offering.sessions.single.freeSeats, 2);
    expect(offering.sessions.single.instructors.single.displayName, 'Docent A');
    expect(offering.eligibility.eligible, isFalse);
    expect(
      offering.eligibility.outcomes.single.status,
      OciServeRequirementStatus.expiresBeforeStart,
    );
    expect(
      offering.cancellationDeadline(offering.sessions.single),
      DateTime.utc(2026, 9, 30, 8),
    );
  });

  test('een uitvoering zonder id wordt niet stil geaccepteerd', () async {
    transport.responses.add(
      _json({
        'offerings': [<String, Object?>{}],
      }),
    );

    await expectLater(
      gateway.myCourseOfferings(accessToken: 'access', organizationId: 'org'),
      throwsA(
        isA<OciServeException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test(
    'inschrijven stuurt sessies, wachtlijst en voucher idempotent',
    () async {
      transport.responses.add(
        _json({
          'enrollment_id': 'enr-1',
          'bookings': [
            {'id': 'b-1', 'session_id': 'ses-1', 'status': 'waitlisted'},
            {'id': 'b-2', 'session_id': 'ses-2', 'status': 'booked'},
          ],
        }, statusCode: 201),
      );

      final result = await gateway.registerForOffering(
        accessToken: 'access',
        organizationId: 'org',
        offeringId: 'off-1',
        sessionIds: const ['ses-1', 'ses-2'],
        allowWaitlist: true,
        voucherCode: 'OCVO-XXXX-XXXX-XXXX-XXXX-XX',
        idempotencyKey: 'key-1',
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/api/v1/organizations/org/me/course-offerings/off-1/registrations',
      );
      expect(request.headers['idempotency-key'], 'key-1');
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      expect(body['session_ids'], ['ses-1', 'ses-2']);
      expect(body['allow_waitlist'], true);
      expect(body['voucher_code'], 'OCVO-XXXX-XXXX-XXXX-XXXX-XX');
      expect(result.enrollmentId, 'enr-1');
      expect(result.bookings.first.status, OciServeBookingStatus.waitlisted);
      expect(result.bookings.last.status, OciServeBookingStatus.booked);
    },
  );

  test('boekingen lezen ook de PascalCase-kernvelden van de server', () async {
    // MyBooking heeft geen json-tags op de ingebedde Go-struct: ID/SessionID/
    // Status gaan PascalCase over de draad, de join-velden snake_case.
    transport.responses.add(
      _json({
        'bookings': [
          {
            'ID': 'b-1',
            'SessionID': 'ses-1',
            'EnrollmentID': 'enr-1',
            'Status': 'offered',
            'ParticipantID': 'p-1',
            'session_title': 'Ochtendgroep',
            'starts_at': '2026-10-02T08:00:00Z',
            'ends_at': '2026-10-02T10:00:00Z',
            'timezone': 'Europe/Amsterdam',
            'offering_id': 'off-1',
            'offering_name': 'Rijopleiding herfst',
          },
        ],
      }),
    );

    final page = await gateway.myBookings(
      accessToken: 'access',
      organizationId: 'org',
      includePast: true,
    );

    expect(
      transport.requests.single.url.path,
      '/api/v1/organizations/org/me/bookings',
    );
    expect(
      transport.requests.single.url.queryParameters['include_past'],
      'true',
    );
    final booking = page.bookings.single;
    expect(booking.id, 'b-1');
    expect(booking.status, OciServeBookingStatus.offered);
    expect(booking.offeringName, 'Rijopleiding herfst');
  });

  test('afmelden, bevestigen en afzien zijn idempotent', () async {
    transport.responses.addAll([
      _json({'id': 'b-1', 'session_id': 's-1', 'status': 'cancelled'}),
      _json({'id': 'b-2', 'session_id': 's-2', 'status': 'booked'}),
      _json({'id': 'b-3', 'session_id': 's-3', 'status': 'cancelled'}),
    ]);

    await gateway.cancelMyBooking(
      accessToken: 'access',
      organizationId: 'org',
      bookingId: 'b-1',
      idempotencyKey: 'cancel-1',
    );
    await gateway.confirmMyBookingOffer(
      accessToken: 'access',
      organizationId: 'org',
      bookingId: 'b-2',
      idempotencyKey: 'confirm-1',
    );
    final declined = await gateway.declineMyBooking(
      accessToken: 'access',
      organizationId: 'org',
      bookingId: 'b-3',
      idempotencyKey: 'decline-1',
    );

    final paths = transport.requests.map((r) => r.url.path).toList();
    expect(paths, [
      '/api/v1/organizations/org/me/bookings/b-1/cancel',
      '/api/v1/organizations/org/me/bookings/b-2/confirm',
      '/api/v1/organizations/org/me/bookings/b-3/decline',
    ]);
    expect(transport.requests[0].headers['idempotency-key'], 'cancel-1');
    expect(transport.requests[1].headers['idempotency-key'], 'confirm-1');
    expect(transport.requests[2].headers['idempotency-key'], 'decline-1');
    expect(declined.status, OciServeBookingStatus.cancelled);
  });

  test('een 409 met probleemdetail blijft leesbaar voor producttaal', () async {
    transport.responses.add(
      _json({
        'type': 'about:blank',
        'status': 409,
        'detail': 'planning: session overlaps an existing booking',
      }, statusCode: 409),
    );

    final error = await gateway
        .registerForOffering(
          accessToken: 'access',
          organizationId: 'org',
          offeringId: 'off-1',
          sessionIds: const ['ses-1'],
          allowWaitlist: false,
          idempotencyKey: 'key-1',
        )
        .then<OciServeException>((_) => throw StateError('expected error'))
        .catchError((Object e) => e as OciServeException);

    expect(error.statusCode, 409);
    expect(error.isPlanningConflict('overlaps an existing booking'), isTrue);
    expect(error.isPlanningConflict('session is full'), isFalse);
  });

  test('Retry-After op 429 wordt meegegeven aan de caller', () async {
    transport.responses.add(
      _json(
        {
          'type': 'about:blank',
          'status': 429,
          'detail': 'too many voucher attempts',
        },
        statusCode: 429,
        headers: {'retry-after': '30'},
      ),
    );

    final error = await gateway
        .myCourseOfferings(accessToken: 'access', organizationId: 'org')
        .then<OciServeException>((_) => throw StateError('expected error'))
        .catchError((Object e) => e as OciServeException);

    expect(error.problem?.retryAfter, const Duration(seconds: 30));
  });
}
