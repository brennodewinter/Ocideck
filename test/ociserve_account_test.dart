// #2428: de drie accountroutes die OciDeck miste — de login-audit, de
// les-geopend-audit en de profielfotomutaties.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

OciServeHttpResponse _empty({int statusCode = 204}) =>
    OciServeHttpResponse(statusCode: statusCode, body: Uint8List(0));

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

  test('login-audit post één keer met idempotentiesleutel', () async {
    transport.responses.add(_empty());

    await gateway.reportOciDeckLogin(
      accessToken: 'access',
      idempotencyKey: 'login-key-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/auth/ocideck-login');
    expect(request.headers['authorization'], 'Bearer access');
    expect(request.headers['idempotency-key'], 'login-key-1');
  });

  test('login-audit accepteert alleen 204', () async {
    transport.responses.add(_empty(statusCode: 200));

    await expectLater(
      gateway.reportOciDeckLogin(
        accessToken: 'access',
        idempotencyKey: 'login-key-1',
      ),
      throwsA(
        isA<OciServeException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('les-open-audit gaat naar de lesroute met de eigen sleutel', () async {
    transport.responses.add(_empty());

    await gateway.markLessonOpened(
      accessToken: 'access',
      organizationId: 'org',
      versionId: 'v1',
      lessonId: 'l1',
      idempotencyKey: 'open-key-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.path,
      '/api/v1/organizations/org/me/course-versions/v1/lessons/l1/opened',
    );
    expect(request.headers['idempotency-key'], 'open-key-1');
  });

  group('profielfoto', () {
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      1, 2, 3, 4,
    ]);

    test('stuurt de afbeelding als multipart en leest de hash', () async {
      final hash = sha256.convert(png).toString();
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: Uint8List.fromList(utf8.encode(jsonEncode({'hash': hash}))),
        ),
      );

      final returned = await gateway.replaceAccountAvatar(
        accessToken: 'access',
        bytes: png,
        contentType: 'image/png',
      );

      final request = transport.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/me/avatar');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      final sentBody = utf8.decode(request.body!, allowMalformed: true);
      expect(sentBody, contains('name="file"'));
      expect(sentBody, contains('content-type: image/png'));
      expect(returned, hash);
    });

    test(
      'weigert bytes die geen PNG/JPEG/WebP zijn vóór het versturen',
      () async {
        await expectLater(
          gateway.replaceAccountAvatar(
            accessToken: 'access',
            bytes: Uint8List.fromList(utf8.encode('not an image')),
            contentType: 'image/png',
          ),
          throwsA(
            isA<OciServeException>().having(
              (error) => error.code,
              'code',
              'invalid_avatar_image',
            ),
          ),
        );
        expect(transport.requests, isEmpty);
      },
    );

    test('weigert een verklaard type dat niet bij de bytes past', () async {
      await expectLater(
        gateway.replaceAccountAvatar(
          accessToken: 'access',
          bytes: png,
          contentType: 'image/webp',
        ),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'invalid_avatar_image',
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });

    test('een antwoord zonder geldige hash is een contractbreuk', () async {
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: Uint8List.fromList(utf8.encode(jsonEncode({'hash': 'x'}))),
        ),
      );

      await expectLater(
        gateway.replaceAccountAvatar(
          accessToken: 'access',
          bytes: png,
          contentType: 'image/png',
        ),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    });

    test('verwijderen is een kale DELETE die 204 verwacht', () async {
      transport.responses.add(_empty());

      await gateway.removeAccountAvatar(accessToken: 'access');

      final request = transport.requests.single;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/v1/me/avatar');
      expect(request.headers['authorization'], 'Bearer access');
    });
  });
}
