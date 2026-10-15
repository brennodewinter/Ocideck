// #2429: het themaregister — lijst, detail met ETag, delen, bijwerken met
// If-Match en verwijderen. De conflictcodes (409 voor naam, ETag en
// in-gebruik) moeten als statuscode op de exception zichtbaar blijven zodat
// de UI ze in producttaal kan uitleggen.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/models/ociserve_theme.dart';
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
  Object body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) => OciServeHttpResponse(
  statusCode: statusCode,
  body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  headers: headers,
);

Map<String, Object?> _theme({String id = 't1', String name = 'Huisstijl'}) => {
  'id': id,
  'name': name,
  'definition': const {'accentColor': '#112233'},
  'is_builtin': false,
  'created_at': '2026-09-01T10:00:00Z',
  'updated_at': '2026-09-01T10:00:00Z',
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

  test('lijst leest themes en next_cursor', () async {
    transport.responses.add(
      _json({
        'themes': [_theme()],
        'next_cursor': 'page2',
      }),
    );

    final result = await gateway.themes(
      accessToken: 'access',
      organizationId: 'org',
    );

    expect(
      transport.requests.single.url.path,
      '/api/v1/organizations/org/themes',
    );
    expect(result.themes.single.name, 'Huisstijl');
    expect(result.nextCursor, 'page2');
  });

  test('detail levert de ETag-header mee voor If-Match', () async {
    transport.responses.add(_json(_theme(), headers: {'etag': '"v3"'}));

    final detail = await gateway.theme(
      accessToken: 'access',
      organizationId: 'org',
      themeId: 't1',
    );

    expect(detail.etag, '"v3"');
    expect(detail.theme.id, 't1');
  });

  test('delen post naam plus ondoorzichtige definitie met sleutel', () async {
    transport.responses.add(_json(_theme(), statusCode: 201));

    await gateway.createTheme(
      accessToken: 'access',
      organizationId: 'org',
      name: 'Huisstijl',
      definition: const {'accentColor': '#112233'},
      idempotencyKey: 'key-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.headers['idempotency-key'], 'key-1');
    final sent = jsonDecode(utf8.decode(request.body!)) as Map;
    expect(sent['name'], 'Huisstijl');
    expect(sent['definition'], {'accentColor': '#112233'});
  });

  test('bijwerken stuurt If-Match met de meegelezen ETag', () async {
    transport.responses.add(_json(_theme(), headers: {'etag': '"v4"'}));

    await gateway.updateTheme(
      accessToken: 'access',
      organizationId: 'org',
      themeId: 't1',
      name: 'Huisstijl',
      definition: const {'accentColor': '#445566'},
      ifMatch: '"v3"',
    );

    expect(transport.requests.single.headers['if-match'], '"v3"');
  });

  test('een 409 bij bijwerken komt als statuscode door naar de UI', () async {
    transport.responses.add(
      _json({
        'type': 'about:blank',
        'title': 'Conflict',
        'status': 409,
      }, statusCode: 409),
    );

    await expectLater(
      () => gateway.updateTheme(
        accessToken: 'access',
        organizationId: 'org',
        themeId: 't1',
        name: 'Huisstijl',
        definition: const {},
        ifMatch: '"v3"',
      ),
      throwsA(
        isA<OciServeException>().having((e) => e.statusCode, 'status', 409),
      ),
    );
  });

  test(
    'verwijderen is een DELETE; 409 voor in-gebruik blijft herkenbaar',
    () async {
      transport.responses.add(
        OciServeHttpResponse(statusCode: 204, body: Uint8List(0)),
      );

      await gateway.deleteTheme(
        accessToken: 'access',
        organizationId: 'org',
        themeId: 't1',
      );

      final request = transport.requests.single;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/v1/organizations/org/themes/t1');

      transport.responses.add(
        _json({
          'type': 'about:blank',
          'title': 'Conflict',
          'status': 409,
        }, statusCode: 409),
      );
      await expectLater(
        () => gateway.deleteTheme(
          accessToken: 'access',
          organizationId: 'org',
          themeId: 't1',
        ),
        throwsA(
          isA<OciServeException>().having((e) => e.statusCode, 'status', 409),
        ),
      );
    },
  );

  test(
    'een lege of jokerteken-ETag is geen If-Match voor een stille bijwerking',
    () {
      expect(themeMatchToken(null), isNull);
      expect(themeMatchToken('   '), isNull);
      expect(themeMatchToken('*'), isNull);
      expect(themeMatchToken(' "v3" '), '"v3"');
    },
  );
}
