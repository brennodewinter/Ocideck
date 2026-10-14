import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_evidence_item.dart';
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
        mutation: OciServeExamAnswerMutation.fromItem(
          organizationId: 'org',
          item: item,
          answerData: const {'selected_option_id': 'a'},
          idempotencyKey: 'answer-request-1',
        ),
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

  group('examenuitslagen', () {
    OciServeHttpResponse noStore(Object value) => OciServeHttpResponse(
      statusCode: 200,
      headers: const {'cache-control': 'private, no-store'},
      body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
    );

    test(
      'lezen van de eigen uitslagroute, zonder cijfers vóór vrijgave',
      () async {
        transport.responses.add(
          noStore({
            'results': [
              {
                'attempt_id': 'a1',
                'exam_session_id': 's1',
                'title': 'Theorie',
                'status': 'scored',
              },
              {
                'attempt_id': 'a2',
                'exam_session_id': 's2',
                'title': 'Praktijk',
                'status': 'released',
                'released_at': '2026-09-12T11:00:00Z',
                'total_items': 4,
                'correct_items': 3,
                'percentage': 75,
                'passed': false,
              },
            ],
            'server_time': '2026-09-12T12:00:00Z',
          }),
        );

        final list = await gateway.examResults(
          accessToken: 'access',
          organizationId: 'org',
        );

        expect(transport.requests.single.method, 'GET');
        expect(
          transport.requests.single.url.path,
          endsWith('/organizations/org/me/exam-results'),
        );
        expect(list.results.first.released, isFalse);
        expect(list.results.first.percentage, isNull);
        expect(list.results.last.passed, isFalse);
        expect(list.results.last.percentage, 75.0);
      },
    );

    test('een antwoord zonder no-store wordt geweigerd', () async {
      transport.responses.add(
        _json({'results': <Object?>[], 'server_time': '2026-09-12T12:00:00Z'}),
      );

      await expectLater(
        gateway.examResults(accessToken: 'access', organizationId: 'org'),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'exam_cache_policy_refused',
          ),
        ),
      );
    });

    test(
      'cijfers bij een niet-vrijgegeven poging zijn een contractbreuk',
      () async {
        transport.responses.add(
          noStore({
            'results': [
              {
                'attempt_id': 'a1',
                'exam_session_id': 's1',
                'title': 'Theorie',
                'status': 'scored',
                'percentage': 100,
                'passed': true,
              },
            ],
            'server_time': '2026-09-12T12:00:00Z',
          }),
        );

        await expectLater(
          gateway.examResults(accessToken: 'access', organizationId: 'org'),
          throwsA(
            isA<OciServeException>().having(
              (error) => error.code,
              'code',
              'invalid_response',
            ),
          ),
        );
      },
    );
  });

  group('bewijs aanleveren', () {
    Map<String, Object?> typeJson(String id, String title, String status) => {
      'id': id,
      'slug': title.toLowerCase(),
      'title': title,
      'status': status,
      'created_at': '2026-09-01T10:00:00Z',
      'updated_at': '2026-09-01T10:00:00Z',
    };

    Map<String, Object?> itemJson({String status = 'ingediend'}) => {
      'id': 'item-1',
      'participant_id': 'p1',
      'evidence_type_id': 'type-1',
      'content_status': status,
      'upload_id': 'upload-1',
      'declared_valid_until': '2028-01-31T00:00:00Z',
      'review_note': status == 'afgewezen' ? 'Onleesbaar' : null,
      'created_at': '2026-09-02T10:00:00Z',
    };

    test('toont alleen gepubliceerde bewijssoorten', () async {
      transport.responses.add(
        _json({
          'evidence_types': [
            typeJson('type-1', 'BHV', 'published'),
            typeJson('type-2', 'Concept', 'draft'),
            typeJson('type-3', 'Oud', 'archived'),
          ],
        }),
      );

      final types = await gateway.evidenceTypes(
        accessToken: 'access',
        organizationId: 'org',
      );

      expect(transport.requests.single.method, 'GET');
      expect(
        transport.requests.single.url.path,
        '/api/v1/organizations/org/evidence-types',
      );
      expect(types.map((type) => type.title), ['BHV']);
    });

    test('een bewijssoort zonder titel is een contractbreuk', () async {
      transport.responses.add(
        _json({
          'evidence_types': [typeJson('type-1', '', 'published')],
        }),
      );

      await expectLater(
        gateway.evidenceTypes(accessToken: 'access', organizationId: 'org'),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    });

    test('een lijst zonder evidence_types is een contractbreuk', () async {
      transport.responses.add(_json({'types': <Object?>[]}));

      await expectLater(
        gateway.evidenceTypes(accessToken: 'access', organizationId: 'org'),
        throwsA(isA<OciServeException>()),
      );
    });

    test('dient een schone upload in met idempotentiesleutel', () async {
      transport.responses.add(_json(itemJson(), statusCode: 201));

      final item = await gateway.createEvidenceItem(
        accessToken: 'access',
        organizationId: 'org',
        participantId: 'p1',
        evidenceTypeId: 'type-1',
        uploadId: 'upload-1',
        idempotencyKey: 'key-1',
        declaredValidUntil: DateTime.utc(2028, 1, 31),
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/api/v1/organizations/org/participants/p1/evidence-items',
      );
      expect(request.headers['idempotency-key'], 'key-1');
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      expect(body['evidence_type_id'], 'type-1');
      expect(body['upload_id'], 'upload-1');
      expect(body['declared_valid_until'], '2028-01-31T00:00:00.000Z');
      expect(item.id, 'item-1');
      expect(item.status, OciServeEvidenceContentStatus.ingediend);
      expect(item.uploadId, 'upload-1');
    });

    test('laat de einddatum weg als die niet is opgegeven', () async {
      transport.responses.add(_json(itemJson(), statusCode: 201));

      await gateway.createEvidenceItem(
        accessToken: 'access',
        organizationId: 'org',
        participantId: 'p1',
        evidenceTypeId: 'type-1',
        uploadId: 'upload-1',
        idempotencyKey: 'key-1',
      );

      final body =
          jsonDecode(utf8.decode(transport.requests.single.body!)) as Map;
      expect(body.containsKey('declared_valid_until'), isFalse);
    });

    test('een onbekende beoordelingsstatus is een contractbreuk', () async {
      transport.responses.add(_json(itemJson(status: 'raar'), statusCode: 201));

      await expectLater(
        gateway.createEvidenceItem(
          accessToken: 'access',
          organizationId: 'org',
          participantId: 'p1',
          evidenceTypeId: 'type-1',
          uploadId: 'upload-1',
          idempotencyKey: 'key-1',
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

    test('leest de eigen bewijsstukken met hun beoordeling', () async {
      transport.responses.add(
        _json({
          'evidence_items': [itemJson(), itemJson(status: 'afgewezen')],
        }),
      );

      final items = await gateway.evidenceItems(
        accessToken: 'access',
        organizationId: 'org',
        participantId: 'p1',
      );

      expect(transport.requests.single.method, 'GET');
      expect(
        transport.requests.single.url.path,
        '/api/v1/organizations/org/participants/p1/evidence-items',
      );
      expect(items, hasLength(2));
      expect(items.last.status, OciServeEvidenceContentStatus.afgewezen);
      expect(items.last.reviewNote, 'Onleesbaar');
      expect(items.first.declaredValidUntil, DateTime.utc(2028, 1, 31));
    });

    test('een lijst zonder evidence_items is een contractbreuk', () async {
      transport.responses.add(_json({'items': <Object?>[]}));

      await expectLater(
        gateway.evidenceItems(
          accessToken: 'access',
          organizationId: 'org',
          participantId: 'p1',
        ),
        throwsA(isA<OciServeException>()),
      );
    });
  });

  test('204 current item means only that all questions are answered', () async {
    transport.responses.add(
      OciServeHttpResponse(
        statusCode: 204,
        headers: const {'cache-control': 'private, no-store'},
        body: Uint8List(0),
      ),
    );

    final item = await gateway.currentExamItem(
      accessToken: 'access',
      organizationId: 'org',
      attemptId: 'attempt-1',
    );

    expect(item, isNull);
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

  test(
    'preserves privacy-data contract version and omission reasons',
    () async {
      transport.responses.add(
        _json({
          'schema_version': 'privacy-data/v2',
          'participant_id': 'participant-1',
          'generated_at': '2026-09-24T10:00:00Z',
          'data': {
            'evidence_uploads': [
              {'uploaded_by_subject': null},
            ],
          },
          'omissions': [
            {
              'path': '/data/evidence_uploads/0/uploaded_by_subject',
              'reason': 'third_party_data',
            },
          ],
        }),
      );

      final value = await gateway.privacyData(
        accessToken: 'access',
        organizationId: 'org',
      );

      expect(value.schemaVersion, 'privacy-data/v2');
      expect(value.omissions, hasLength(1));
      expect(
        value.omissions.single.path,
        '/data/evidence_uploads/0/uploaded_by_subject',
      );
      expect(value.omissions.single.reason, 'third_party_data');
    },
  );

  test('keeps a legacy privacy-data response compatible', () async {
    transport.responses.add(
      _json({
        'participant_id': 'participant-1',
        'generated_at': '2026-09-24T10:00:00Z',
        'data': <String, Object?>{},
      }),
    );

    final value = await gateway.privacyData(
      accessToken: 'access',
      organizationId: 'org',
    );

    expect(value.schemaVersion, 'privacy-data/v1');
    expect(value.omissions, isEmpty);
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
