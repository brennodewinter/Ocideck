import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_exam.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/utils/zip_encryption.dart';

import 'support/ociserve_aes_fixture.dart';

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

OciServeHttpResponse _json(Object value, {int statusCode = 200}) =>
    OciServeHttpResponse(
      statusCode: statusCode,
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
    'downloads the authenticated account avatar with a strict cap',
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

      expect(
        await gateway.accountAvatar(accessToken: 'access', avatarHash: hash),
        bytes,
      );
      expect(transport.requests.single.url.path, '/api/v1/me/avatar');
      expect(transport.caps.single, 5 * 1024 * 1024);
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
    'opens a short-lived session and accepts only its exact AES profile',
    () async {
      final bytes = ociServeAesPackage({
        'lesson.md': utf8.encode('---\nmarp: true\n---\n# Lesson'),
      });
      final digest = sha256.convert(bytes);
      transport.responses.addAll([
        _json({
          'id': 'session-1',
          'package_password': testOciServePackagePassword,
          'package_url':
              '/api/v1/organizations/org/me/lesson-playback-sessions/session-1/package',
          'package_profile': ociServeAesPackageProfile,
          'expires_at': '2099-01-01T00:00:00Z',
          'digest': digest.toString(),
        }, statusCode: 201),
        OciServeHttpResponse(
          statusCode: 200,
          body: bytes,
          headers: {
            'digest': 'sha-256=:${base64.encode(digest.bytes)}:',
            'x-ociserve-package-profile': ociServeAesPackageProfile,
            'cache-control': 'private, no-store',
            'etag': '"one"',
          },
        ),
      ]);

      final grant = await gateway.startLessonSession(
        accessToken: 'access',
        organizationId: 'org',
        versionId: 'v1',
        lessonId: 'l1',
      );
      final package = await gateway.lessonSessionPackage(
        accessToken: 'access',
        organizationId: 'org',
        grant: grant,
      );

      expect(package.bytes, bytes);
      expect(package.sha256, digest.toString());
      expect(grant.packagePassword, testOciServePackagePassword);
      expect(
        transport.requests.first.url.path,
        '/api/v1/organizations/org/me/course-versions/v1/lessons/l1/playback-sessions',
      );
      expect(transport.requests.first.method, 'POST');
      expect(transport.requests.first.headers['idempotency-key'], isNotEmpty);
      expect(
        transport.requests.last.url.path,
        '/api/v1/organizations/org/me/lesson-playback-sessions/session-1/package',
      );
    },
  );

  test('refuses plaintext even when both digests match', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final digest = sha256.convert(bytes);
    final grant = OciServeLessonSessionGrant(
      id: 'session-1',
      packagePassword: testOciServePackagePassword,
      packageProfile: ociServeAesPackageProfile,
      packageUrl: Uri.parse(
        '/api/v1/organizations/org/me/lesson-playback-sessions/session-1/package',
      ),
      expiresAt: DateTime.utc(2099),
      digestSha256: digest.toString(),
    );
    transport.responses.add(
      OciServeHttpResponse(
        statusCode: 200,
        body: bytes,
        headers: {
          'digest': 'sha-256=:${base64.encode(digest.bytes)}:',
          'x-ociserve-package-profile': ociServeAesPackageProfile,
          'cache-control': 'private, no-store',
        },
      ),
    );

    await expectLater(
      gateway.lessonSessionPackage(
        accessToken: 'access',
        organizationId: 'org',
        grant: grant,
      ),
      throwsA(
        isA<OciServeException>().having(
          (error) => error.code,
          'code',
          'package_profile_refused',
        ),
      ),
    );
  });

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

  test(
    'formal exam answer binds challenge, revision and idempotency key',
    () async {
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          headers: const {'cache-control': 'private, no-store'},
          body: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'attempt_id': 'attempt-1',
                'attempt_item_id': 'item-1',
                'revision': 5,
                'accepted_at': '2026-09-12T10:00:00Z',
              }),
            ),
          ),
        ),
      );
      final item = OciServeCurrentExamItem(
        attemptId: 'attempt-1',
        attemptItemId: 'item-1',
        position: 0,
        question: 'Vraag?',
        options: const [OciServeExamOption(id: 'a', text: 'A')],
        revision: 4,
        challenge: 'AAAAAAAAAAAAAAAAAAAAAA',
        challengeExpiresAt: DateTime.utc(2026, 9, 12, 10, 5),
      );

      await gateway.answerExamItem(
        accessToken: 'access',
        organizationId: 'org',
        item: item,
        answerData: const {'selected_option_id': 'a'},
        idempotencyKey: 'answer-request-1',
      );

      final request = transport.requests.single;
      expect(request.method, 'PUT');
      expect(request.headers['idempotency-key'], 'answer-request-1');
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      expect(body['challenge'], item.challenge);
      expect(body['revision'], 4);
      expect(body, isNot(contains('correct')));
    },
  );

  test('formal exam responses must be no-store', () async {
    transport.responses.add(
      _json({
        'exam_sessions': <Object?>[],
        'server_time': '2026-09-12T10:00:00Z',
      }),
    );

    await expectLater(
      gateway.examSessions(accessToken: 'access', organizationId: 'org'),
      throwsA(
        isA<OciServeException>().having(
          (error) => error.code,
          'code',
          'exam_cache_policy_refused',
        ),
      ),
    );
  });

  test('requests and preserves every personal-data category', () async {
    transport.responses.add(
      _json({
        'participant_id': 'participant-1',
        'generated_at': '2026-09-09T10:00:00Z',
        'data': {
          'participant': {'display_name': 'Lerende'},
          'future_category': [
            {'future_field': true},
          ],
        },
      }),
    );

    final value = await gateway.privacyData(
      accessToken: 'access',
      organizationId: 'org',
    );

    expect(value.participantId, 'participant-1');
    expect(value.data, contains('future_category'));
    expect(
      transport.requests.single.url.path,
      '/api/v1/organizations/org/me/privacy-data',
    );
    expect(transport.requests.single.method, 'GET');
    expect(transport.caps.single, 32 * 1024 * 1024);
  });

  test('refuses personal data without a generation timestamp', () async {
    transport.responses.add(
      _json({'participant_id': 'participant-1', 'data': <String, Object?>{}}),
    );

    await expectLater(
      gateway.privacyData(accessToken: 'access', organizationId: 'org'),
      throwsA(
        isA<OciServeException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

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
