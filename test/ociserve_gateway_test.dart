import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
  final caps = <int>[];

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
    caps.add(maxResponseBytes);
    return responses.removeAt(0);
  }
}

OciServeHttpResponse _json(Object value) => OciServeHttpResponse(
  statusCode: 200,
  body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
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
    'bootstrap requires the explicit native client id and discovers OIDC',
    () async {
      transport.responses.addAll([
        _json({
          'oidc_issuer': 'https://id.example',
          'ocideck_native_client_id': 'desktop-id',
        }),
        _json({
          'issuer': 'https://id.example',
          'authorization_endpoint': 'https://id.example/authorize',
          'token_endpoint': 'https://id.example/token',
          'jwks_uri': 'https://id.example/jwks',
          'id_token_signing_alg_values_supported': ['RS256'],
        }),
      ]);

      final installation = await gateway.installation();
      final oidc = await gateway.discoverOidc(installation);

      expect(installation.clientId, 'desktop-id');
      expect(oidc.jwksUri.path, '/jwks');
      expect(transport.requests.first.url.path, '/api/v1/installation');
      expect(
        transport.requests.last.url.path,
        '/.well-known/openid-configuration',
      );
    },
  );

  test('parses course manifests into typed lesson feed items', () async {
    transport.responses.add(
      _json({
        'courses': [
          {
            'course_version_id': 'v1',
            'course_id': 'c1',
            'course_slug': 'intro',
            'title': 'Intro course',
            'image_hash': 'a' * 64,
            'version': 3,
            'enrolled_at': '2026-09-06T10:00:00Z',
            'lessons': [
              {'id': 'l1', 'title': 'Start', 'order': 1},
            ],
          },
        ],
      }),
    );

    final feed = await gateway.learningFeed(
      accessToken: 'access',
      organizationId: 'org',
    );

    expect(feed.single.versionId, 'v1');
    expect(feed.single.lessonId, 'l1');
    expect(feed.single.courseTitle, 'Intro course');
    expect(feed.single.courseImageHash, 'a' * 64);
    expect(feed.single.lessonOrder, 1);
    expect(
      transport.requests.single.url.path,
      '/api/v1/organizations/org/me/learning-feed',
    );
  });

  test(
    'downloads only the feed-named course image and verifies its hash',
    () async {
      final bytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        1,
      ]);
      final hash = sha256.convert(bytes).toString();
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: bytes,
          headers: {'content-type': 'image/png'},
        ),
      );

      final image = await gateway.courseImage(
        accessToken: 'access',
        organizationId: 'org',
        imageHash: hash,
      );

      expect(image, bytes);
      expect(
        transport.requests.single.url.path,
        '/api/v1/organizations/org/assets/$hash',
      );
      expect(
        transport.requests.single.headers['authorization'],
        'Bearer access',
      );
      expect(transport.caps.single, 64 * 1024 * 1024);
    },
  );

  test(
    'refuses a course image whose bytes do not match the feed hash',
    () async {
      final bytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        1,
      ]);
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: bytes,
          headers: {'content-type': 'image/png'},
        ),
      );

      await expectLater(
        gateway.courseImage(
          accessToken: 'access',
          organizationId: 'org',
          imageHash: 'b' * 64,
        ),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'image_digest_mismatch',
          ),
        ),
      );
    },
  );

  test(
    'package requires play-only policy and matching sha-256 Digest',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: bytes,
          headers: {
            'digest': 'sha-256=:${base64.encode(sha256.convert(bytes).bytes)}:',
            'x-ociserve-playback-policy': 'play-only',
            'etag': '"one"',
          },
        ),
      );

      final package = await gateway.lessonPackage(
        accessToken: 'access',
        organizationId: 'org',
        versionId: 'v1',
        lessonId: 'l1',
      );

      expect(package.bytes, bytes);
      expect(package.sha256, sha256.convert(bytes).toString());
      expect(
        transport.requests.single.url.path,
        '/api/v1/organizations/org/me/course-versions/v1/lessons/l1/package',
      );
    },
  );

  test(
    'playback is idempotent and uses the server snapshot contract',
    () async {
      transport.responses.add(_json({}));
      final snapshot = OciServePlaybackSnapshot(
        sessionId: 'session-1',
        courseVersionId: 'v1',
        lessonId: 'l1',
        startedAt: DateTime.utc(2026, 9, 6, 10),
        completed: true,
        slideTimeMs: const {'slide-a': 1200},
      );

      await gateway.reportPlayback(
        accessToken: 'access',
        organizationId: 'org',
        snapshot: snapshot,
      );

      final request = transport.requests.single;
      expect(
        request.url.path,
        '/api/v1/organizations/org/me/playback-sessions',
      );
      expect(request.headers['idempotency-key'], 'session-1');
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      expect(body['client_session_id'], 'session-1');
      expect((body['slides'] as List).single['displayed_milliseconds'], 1200);
    },
  );

  test('HTTP base URLs fail before transport is touched', () async {
    final insecure = OciServeGateway(
      settings: const OciServeSettings(
        enabled: true,
        baseUrl: 'http://learn.example',
        trustedInternal: true,
      ),
      transport: transport,
    );

    await expectLater(
      insecure.installation(),
      throwsA(
        isA<OciServeException>().having(
          (error) => error.code,
          'code',
          'https_required',
        ),
      ),
    );
    expect(transport.requests, isEmpty);
  });
}
