// #2427: het agenda-abonnement — uitgeven/roteren geeft de eenmalige URL
// (met bearer-token) plus verloopdatum; intrekken is een DELETE. Geen enkel
// foutpad mag de token-URL in een log of exception laten lekken.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';

class _Request {
  _Request(this.method, this.url, this.headers);
  final String method;
  final Uri url;
  final Map<String, String> headers;
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
    requests.add(_Request(method, url, headers));
    return responses.removeAt(0);
  }
}

OciServeHttpResponse _json(Object body, {int statusCode = 200}) =>
    OciServeHttpResponse(
      statusCode: statusCode,
      body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );

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

  test(
    'uitgeven post met idempotentie-sleutel en maakt de URL absoluut',
    () async {
      transport.responses.add(
        _json({
          'url': '/api/v1/organizations/org/me/calendar.ics?token=geheim123',
          'expires_at': '2027-01-01T00:00:00Z',
        }, statusCode: 201),
      );

      final result = await gateway.issueCalendarSubscription(
        accessToken: 'access',
        organizationId: 'org',
        idempotencyKey: 'key-1',
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/api/v1/organizations/org/me/calendar-subscription',
      );
      expect(request.headers['idempotency-key'], 'key-1');
      expect(
        result.feedUrl.toString(),
        'https://learn.example/api/v1/organizations/org/me/calendar.ics?token=geheim123',
      );
      expect(result.expiresAt, DateTime.utc(2027));
    },
  );

  test('intrekken is een DELETE zonder body', () async {
    transport.responses.add(
      OciServeHttpResponse(statusCode: 204, body: Uint8List(0)),
    );

    await gateway.revokeCalendarSubscription(
      accessToken: 'access',
      organizationId: 'org',
    );

    final request = transport.requests.single;
    expect(request.method, 'DELETE');
    expect(
      request.url.path,
      '/api/v1/organizations/org/me/calendar-subscription',
    );
  });

  test(
    'een verstoorde serverfout lekt de token-URL niet in de exception',
    () async {
      // De server antwoordt met een probleemdetail dat toevallig een pad met
      // token bevat; de exception mag alleen de code/probleem bevatten — en de
      // request-URL van de gateway bevat nooit het feed-token.
      transport.responses.add(
        _json({
          'type': 'about:blank',
          'title': 'Internal Server Error',
          'status': 500,
        }, statusCode: 500),
      );

      await expectLater(
        () => gateway.issueCalendarSubscription(
          accessToken: 'access',
          organizationId: 'org',
          idempotencyKey: 'key-1',
        ),
        throwsA(
          isA<OciServeException>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains('token')),
          ),
        ),
      );
    },
  );

  test('een afwijkend 201-antwoord faalt als ongeldig antwoord', () async {
    transport.responses.add(_json({'url': ''}, statusCode: 201));

    expect(
      () => gateway.issueCalendarSubscription(
        accessToken: 'access',
        organizationId: 'org',
        idempotencyKey: 'key-1',
      ),
      throwsA(isA<OciServeException>()),
    );
  });
}
