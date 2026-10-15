// #2425: uitnodigingsregistratie — publieke preview (zonder token),
// registratie met idempotentie-sleutel, en de aangemelde acceptatie. De
// generieke 400 (anti-enumeratie) en 429 moeten als statuscode overeind
// blijven voor de producttekst in de UI.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

  test('preview stuurt nummer en code zonder token, geeft het adres', () async {
    transport.responses.add(_json({'invited_email': 'cursist@example.org'}));

    final email = await gateway.invitationRegistrationPreview(
      invitationId: 'inv-1',
      secret: 'code-1',
    );

    final request = transport.requests.single;
    expect(request.url.path, '/api/v1/invitation-registration-preview');
    expect(request.headers.containsKey('authorization'), isFalse);
    final sent = jsonDecode(utf8.decode(request.body!)) as Map;
    expect(sent['invitation_id'], 'inv-1');
    expect(sent['secret'], 'code-1');
    expect(email, 'cursist@example.org');
  });

  test('registratie stuurt de velden met idempotentie-sleutel', () async {
    transport.responses.add(
      _json({
        'organization_id': 'org-1',
        'account_id': 'acc-1',
        'membership_id': 'mem-1',
        'role': 'participant',
      }, statusCode: 201),
    );

    final result = await gateway.invitationRegister(
      invitationId: 'inv-1',
      secret: 'code-1',
      displayName: 'Cursist',
      password: 'zeer-geheim-wachtwoord',
      idempotencyKey: 'key-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/invitation-registrations');
    expect(request.headers['idempotency-key'], 'key-1');
    expect(request.headers.containsKey('authorization'), isFalse);
    final sent = jsonDecode(utf8.decode(request.body!)) as Map;
    expect(sent['display_name'], 'Cursist');
    expect(sent.containsKey('password'), isTrue);
    expect(result.organizationId, 'org-1');
    expect(result.role, 'participant');
  });

  test('acceptatie stuurt het token en accepteert op de identiteit', () async {
    transport.responses.add(
      _json({
        'organization_id': 'org-2',
        'account_id': 'acc-1',
        'membership_id': 'mem-2',
        'role': 'participant',
      }, statusCode: 201),
    );

    final result = await gateway.invitationAccept(
      accessToken: 'access',
      invitationId: 'inv-1',
      secret: 'code-1',
      idempotencyKey: 'key-2',
    );

    final request = transport.requests.single;
    expect(request.url.path, '/api/v1/invitation-acceptances');
    expect(request.headers['authorization'], 'Bearer access');
    expect(request.headers['idempotency-key'], 'key-2');
    expect(result.organizationId, 'org-2');
  });

  test('de generieke 400 en 429 blijven als statuscode leesbaar', () async {
    transport.responses.add(
      _json({
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
      }, statusCode: 400),
    );
    transport.responses.add(
      _json({
        'type': 'about:blank',
        'title': 'Too Many Requests',
        'status': 429,
      }, statusCode: 429),
    );

    await expectLater(
      () => gateway.invitationRegistrationPreview(
        invitationId: 'inv-1',
        secret: 'fout',
      ),
      throwsA(
        isA<OciServeException>().having((e) => e.statusCode, 'status', 400),
      ),
    );
    await expectLater(
      () => gateway.invitationRegistrationPreview(
        invitationId: 'inv-1',
        secret: 'fout',
      ),
      throwsA(
        isA<OciServeException>().having((e) => e.statusCode, 'status', 429),
      ),
    );
  });
}
