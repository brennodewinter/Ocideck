import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_intake.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_intake_respondent.dart';

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

OciServeHttpResponse _json(
  Object value, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) => OciServeHttpResponse(
  statusCode: statusCode,
  body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
  headers: headers,
);

Map<String, Object?> _snapshot() => {
  'format': 'ociserve-intake-form/1',
  'title': 'Enquête',
  'purposes': const ['onderzoek'],
  'privacy_text': 'Wij bewaren je antwoorden zorgvuldig.',
  'retention': const {'draft_days': 30, 'submitted_days': 365},
  'correction_policy': const {'allowed': true, 'deadline_days': 14},
  'definition': const {'questions': <Object?>[]},
};

Map<String, Object?> _form() => {
  'form_id': 'form-1',
  'form_ref': 'pub-ref-9',
  'name': 'Enquête',
  'operational_status': 'open',
  'active_version': 2,
  'versions': [
    {
      'version': 2,
      'sha256': 'a' * 64,
      'published_at': '2026-10-01T09:00:00Z',
      'active': true,
    },
    {
      'version': 1,
      'sha256': 'b' * 64,
      'published_at': '2026-09-01T09:00:00Z',
      'active': false,
    },
  ],
  'created_at': '2026-09-01T09:00:00Z',
};

Map<String, Object?> _submissionDetail({String state = 'submitted'}) => {
  'submission_id': 'sub-1',
  'state': state,
  'revision': 1,
  'handled': false,
  'created_at': '2026-10-01T09:00:00Z',
  'submitted_at': '2026-10-02T09:00:00Z',
  'revisions': [
    {
      'revision': 1,
      'submitted_at': '2026-10-02T09:00:00Z',
      'sha256': 'c' * 64,
      'size': 12,
    },
  ],
};

const _grant = IntakeGrant(
  token: 'grant-token-secret',
  expiresIn: Duration(minutes: 15),
  purpose: IntakePurpose.resume,
  locator: 'locator-1',
);

Matcher _serveCode(String code) =>
    isA<OciServeException>().having((error) => error.code, 'code', code);

void main() {
  late _FakeTransport transport;
  late OciServeGateway gateway;
  late IntakeRespondentClient respondent;

  setUp(() {
    transport = _FakeTransport();
    gateway = OciServeGateway(
      settings: const OciServeSettings(
        enabled: true,
        baseUrl: 'https://serve.example',
      ),
      transport: transport,
    );
    respondent = IntakeRespondentClient(
      baseUrl: 'https://serve.example',
      transport: transport,
    );
  });

  group('organisator', () {
    test('lijst van formulieren stuurt filters en bewaart de ETag', () async {
      transport.responses.add(
        _json(
          {
            'items': [
              {
                'form_id': 'form-1',
                'name': 'Enquête',
                'operational_status': 'open',
                'active_version': 2,
                'my_grant': 'beheerder',
              },
            ],
            'next_cursor': 'page-2',
          },
          headers: const {'etag': '"list-1"'},
        ),
      );

      final page = await gateway.intakeForms(
        accessToken: 'access',
        organizationId: 'org',
        status: IntakeOperationalStatus.open,
      );

      final request = transport.requests.single;
      expect(request.url.path, '/api/v1/organizations/org/intake-forms');
      expect(request.url.queryParameters['operational_status'], 'open');
      expect(request.headers['authorization'], 'Bearer access');
      expect(page!.etag, '"list-1"');
      expect(page.value.items.single.myGrant, IntakeGrantRole.beheerder);
      expect(page.value.nextCursor, 'page-2');
    });

    test('304 op een lijst levert null, geen parsefout', () async {
      transport.responses.add(
        OciServeHttpResponse(statusCode: 304, body: Uint8List(0)),
      );

      final page = await gateway.intakeForms(
        accessToken: 'access',
        organizationId: 'org',
        ifNoneMatch: '"list-1"',
      );

      expect(page, isNull);
      expect(transport.requests.single.headers['if-none-match'], '"list-1"');
    });

    test('aanmaken stuurt snapshot en idempotency-key, leest 201', () async {
      transport.responses.add(_json(_form(), statusCode: 201));

      final form = await gateway.createIntakeForm(
        accessToken: 'access',
        organizationId: 'org',
        name: 'Enquête',
        snapshot: IntakeFormSnapshot.fromJson(_snapshot()),
        idempotencyKey: 'key-1',
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.headers['idempotency-key'], 'key-1');
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      expect(body['name'], 'Enquête');
      expect(body['snapshot']['format'], 'ociserve-intake-form/1');
      expect(form.formRef, 'pub-ref-9');
      expect(form.versions, hasLength(2));
    });

    test('200 in plaats van 201 op aanmaken is een contractbreuk', () async {
      transport.responses.add(_json(_form()));

      await expectLater(
        gateway.createIntakeForm(
          accessToken: 'access',
          organizationId: 'org',
          name: 'Enquête',
          snapshot: IntakeFormSnapshot.fromJson(_snapshot()),
          idempotencyKey: 'key-1',
        ),
        throwsA(_serveCode('invalid_response')),
      );
    });

    test('statuswijziging draagt If-Match en leest IntakeForm terug', () async {
      transport.responses.add(_json(_form()));

      final form = await gateway.patchIntakeFormStatus(
        accessToken: 'access',
        organizationId: 'org',
        formId: 'form-1',
        status: IntakeOperationalStatus.closed,
        ifMatch: '"form-etag"',
      );

      final request = transport.requests.single;
      expect(request.method, 'PATCH');
      expect(request.headers['if-match'], '"form-etag"');
      expect(jsonDecode(utf8.decode(request.body!)), {
        'operational_status': 'closed',
      });
      expect(form.formId, 'form-1');
    });

    test(
      'een verloren race (412) komt als http_error met status terug',
      () async {
        transport.responses.add(
          _json({
            'type': 'https://example.invalid/precondition',
            'detail': 'ETag klopt niet',
          }, statusCode: 412),
        );

        await expectLater(
          gateway.patchIntakeFormStatus(
            accessToken: 'access',
            organizationId: 'org',
            formId: 'form-1',
            status: IntakeOperationalStatus.paused,
            ifMatch: '"stale"',
          ),
          throwsA(
            isA<OciServeException>()
                .having((e) => e.code, 'code', 'http_error')
                .having((e) => e.statusCode, 'statusCode', 412)
                .having(
                  (e) => e.problem?.detail,
                  'problem.detail',
                  'ETag klopt niet',
                ),
          ),
        );
      },
    );

    test('versie publiceren leest 201 met sha en snapshot', () async {
      transport.responses.add(
        _json({
          'version': 3,
          'sha256': 'd' * 64,
          'published_at': '2026-10-05T09:00:00Z',
          'snapshot': _snapshot(),
        }, statusCode: 201),
      );

      final version = await gateway.publishIntakeFormVersion(
        accessToken: 'access',
        organizationId: 'org',
        formId: 'form-1',
        snapshot: IntakeFormSnapshot.fromJson(_snapshot()),
        idempotencyKey: 'key-2',
      );

      expect(
        transport.requests.single.url.path,
        '/api/v1/organizations/org/intake-forms/form-1/versions',
      );
      expect(transport.requests.single.headers['idempotency-key'], 'key-2');
      expect(version.version, 3);
      expect(version.snapshot.title, 'Enquête');
    });

    test('inboxfilter state + handled gaan in de query', () async {
      transport.responses.add(
        _json({
          'items': [
            {
              'submission_id': 'sub-1',
              'state': 'submitted',
              'revision': 1,
              'handled': false,
              'submitted_at': '2026-10-02T09:00:00Z',
            },
          ],
          'next_cursor': null,
        }),
      );

      final page = await gateway.intakeSubmissions(
        accessToken: 'access',
        organizationId: 'org',
        formId: 'form-1',
        state: IntakeSubmissionState.submitted,
        handled: false,
      );

      final query = transport.requests.single.url.queryParameters;
      expect(query['state'], 'submitted');
      expect(query['handled'], 'false');
      expect(page!.value.items.single.submissionId, 'sub-1');
    });

    test(
      'revisie-content eist Digest én bytes gelijk aan de metadata',
      () async {
        final bytes = Uint8List.fromList(utf8.encode('inzendpakket'));
        final digest = sha256.convert(bytes);
        transport.responses.add(
          OciServeHttpResponse(
            statusCode: 200,
            body: bytes,
            headers: {'digest': 'sha-256=:${base64.encode(digest.bytes)}:'},
          ),
        );

        final received = await gateway.intakeRevisionContent(
          accessToken: 'access',
          organizationId: 'org',
          formId: 'form-1',
          submissionId: 'sub-1',
          revision: 1,
          expectedSha256: digest.toString(),
        );

        expect(received, bytes);
        expect(transport.caps.single, 120 * 1024 * 1024);
      },
    );

    test('een afwijkende Digest is een harde fout, geen retry', () async {
      final bytes = Uint8List.fromList(utf8.encode('inzendpakket'));
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: bytes,
          headers: {
            'digest': 'sha-256=:${base64.encode(sha256.convert([0]).bytes)}:',
          },
        ),
      );

      await expectLater(
        gateway.intakeRevisionContent(
          accessToken: 'access',
          organizationId: 'org',
          formId: 'form-1',
          submissionId: 'sub-1',
          revision: 1,
          expectedSha256: sha256.convert(bytes).toString(),
        ),
        throwsA(_serveCode('intake_digest_mismatch')),
      );
      expect(transport.requests, hasLength(1));
    });

    test(
      'open-correction stuurt deadline/reason en leest het detail',
      () async {
        transport.responses.add(
          _json(_submissionDetail(state: 'correction_open')),
        );

        final detail = await gateway.openIntakeCorrection(
          accessToken: 'access',
          organizationId: 'org',
          formId: 'form-1',
          submissionId: 'sub-1',
          deadlineAt: DateTime.utc(2026, 11, 1),
          reason: ' aanvulling gevraagd ',
          idempotencyKey: 'key-3',
        );

        final request = transport.requests.single;
        expect(
          request.url.path,
          endsWith('/intake-forms/form-1/submissions/sub-1/open-correction'),
        );
        expect(request.headers['idempotency-key'], 'key-3');
        final body = jsonDecode(utf8.decode(request.body!)) as Map;
        expect(body['deadline_at'], '2026-11-01T00:00:00.000Z');
        expect(body['reason'], 'aanvulling gevraagd');
        expect(detail.state, IntakeSubmissionState.correctionOpen);
      },
    );

    test('mark-handled stuurt alleen de vlag', () async {
      transport.responses.add(_json(_submissionDetail()..['handled'] = true));

      final detail = await gateway.markIntakeHandled(
        accessToken: 'access',
        organizationId: 'org',
        formId: 'form-1',
        submissionId: 'sub-1',
        handled: true,
        idempotencyKey: 'key-4',
      );

      expect(jsonDecode(utf8.decode(transport.requests.single.body!)), {
        'handled': true,
      });
      expect(detail.handled, isTrue);
    });

    test('purge accepteert alleen een lege 202', () async {
      transport.responses.add(
        OciServeHttpResponse(statusCode: 202, body: Uint8List(0)),
      );

      await gateway.purgeIntakeSubmission(
        accessToken: 'access',
        organizationId: 'org',
        formId: 'form-1',
        submissionId: 'sub-1',
        idempotencyKey: 'key-5',
      );

      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.headers['idempotency-key'], 'key-5');
    });

    test('een 202 met body op purge is een contractbreuk', () async {
      transport.responses.add(
        _json(const {'unexpected': true}, statusCode: 202),
      );

      await expectLater(
        gateway.purgeIntakeSubmission(
          accessToken: 'access',
          organizationId: 'org',
          formId: 'form-1',
          submissionId: 'sub-1',
          idempotencyKey: 'key-5',
        ),
        throwsA(_serveCode('invalid_response')),
      );
    });

    test('429 met Retry-After komt als probleemdetails door', () async {
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 429,
          body: Uint8List.fromList(
            utf8.encode(jsonEncode({'type': 'about:blank'})),
          ),
          headers: const {'retry-after': '30'},
        ),
      );

      await expectLater(
        gateway.intakeForms(accessToken: 'access', organizationId: 'org'),
        throwsA(
          isA<OciServeException>().having(
            (e) => e.problem?.retryAfter,
            'problem.retryAfter',
            const Duration(seconds: 30),
          ),
        ),
      );
    });
  });

  group('respondent', () {
    test(
      'het publieke formulier gaat zonder enige credential over de lijn',
      () async {
        transport.responses.add(
          _json({
            'form_ref': 'pub-ref-9',
            'version': 2,
            'accepting': true,
            'operational_status': 'open',
            'snapshot': _snapshot(),
          }),
        );

        final form = await respondent.publicForm('pub-ref-9');

        expect(form.snapshot.correctionDeadlineDays, 14);
        expect(
          transport.requests.single.url.path,
          '/api/v1/intake/forms/pub-ref-9',
        );
        expect(
          transport.requests.single.headers,
          isNot(contains('authorization')),
        );
      },
    );

    test('challenge voor start vereist form_ref, anders clientfout', () async {
      await expectLater(
        respondent.requestChallenge(
          purpose: IntakePurpose.start,
          email: 'deelnemer@example.nl',
        ),
        throwsA(_serveCode('invalid_request')),
      );
      expect(transport.requests, isEmpty);
    });

    test('challenge voor resume vereist locator en geeft 202 terug', () async {
      transport.responses.add(
        _json({
          'challenge_id': 'chal-1',
          'expires_in': 600,
          'resend_after': 60,
        }, statusCode: 202),
      );

      final challenge = await respondent.requestChallenge(
        purpose: IntakePurpose.resume,
        email: 'deelnemer@example.nl',
        locator: 'locator-1',
      );

      final request = transport.requests.single;
      expect(request.url.path, '/api/v1/intake/challenges');
      final body = jsonDecode(utf8.decode(request.body!)) as Map;
      expect(body['purpose'], 'resume');
      expect(body['locator'], 'locator-1');
      expect(body, isNot(contains('form_ref')));
      expect(challenge.expiresIn, const Duration(minutes: 10));
    });

    test('challenge die 200 antwoordt in plaats van 202 faalt', () async {
      transport.responses.add(
        _json({
          'challenge_id': 'chal-1',
          'expires_in': 600,
          'resend_after': 60,
        }),
      );

      await expectLater(
        respondent.requestChallenge(
          purpose: IntakePurpose.start,
          email: 'deelnemer@example.nl',
          formRef: 'pub-ref-9',
        ),
        throwsA(_serveCode('invalid_response')),
      );
    });

    test('verify stuurt de code in de body, nooit in de URL', () async {
      transport.responses.add(
        _json({
          'grant': 'grant-token-secret',
          'expires_in': 900,
          'purpose': 'resume',
          'locator': 'locator-1',
          'state': 'draft',
        }),
      );

      final grant = await respondent.verifyChallenge(
        challengeId: 'chal-1',
        code: ' 123456 ',
      );

      final request = transport.requests.single;
      expect(request.url.path, '/api/v1/intake/challenges/chal-1/verify');
      expect(request.url.toString(), isNot(contains('123456')));
      expect(jsonDecode(utf8.decode(request.body!)), {'code': '123456'});
      expect(grant.token, 'grant-token-secret');
      expect(grant.state, IntakeSubmissionState.draft);
    });

    test('de grant reist als Bearer-header, niet in de URL of query', () async {
      transport.responses.add(
        _json(
          {
            'locator': 'locator-1',
            'state': 'draft',
            'revision': 0,
            'draft_present': true,
            'allowed_actions': ['draft_put', 'submit'],
          },
          headers: const {'etag': '"sub-etag"'},
        ),
      );

      final page = await respondent.submission(grant: _grant);

      final request = transport.requests.single;
      expect(request.url.path, '/api/v1/intake/submissions/locator-1');
      expect(request.url.toString(), isNot(contains('grant-token-secret')));
      expect(request.headers['authorization'], 'Bearer grant-token-secret');
      expect(page!.value.draftPresent, isTrue);
      expect(page.etag, '"sub-etag"');
    });

    test('304 op de eigen inzending levert null', () async {
      transport.responses.add(
        OciServeHttpResponse(statusCode: 304, body: Uint8List(0)),
      );

      final page = await respondent.submission(
        grant: _grant,
        ifNoneMatch: '"sub-etag"',
      );

      expect(page, isNull);
      expect(transport.requests.single.headers['if-none-match'], '"sub-etag"');
    });

    test(
      'draft-upload vergelijkt de ontvangen digest met de verzonden bytes',
      () async {
        final bytes = utf8.encode('antwoorden');
        transport.responses.add(
          _json({
            'sha256': sha256.convert(bytes).toString(),
            'size': bytes.length,
          }),
        );

        final receipt = await respondent.putDraft(grant: _grant, bytes: bytes);

        final request = transport.requests.single;
        expect(request.method, 'PUT');
        expect(request.headers['content-type'], 'application/octet-stream');
        expect(receipt.size, bytes.length);
      },
    );

    test('een verzwijgde server (foute digest) is een harde fout', () async {
      transport.responses.add(_json({'sha256': 'e' * 64, 'size': 10}));

      await expectLater(
        respondent.putDraft(grant: _grant, bytes: utf8.encode('antwoorden')),
        throwsA(_serveCode('intake_digest_mismatch')),
      );
      expect(transport.requests, hasLength(1));
    });

    test('een leeg ontwerp of >120 MiB gaat de lijn niet op', () async {
      await expectLater(
        respondent.putDraft(grant: _grant, bytes: const []),
        throwsA(_serveCode('package_too_large')),
      );
      expect(transport.requests, isEmpty);
    });

    test(
      'submit stuurt idempotency-key en verifieert revisie-digest',
      () async {
        final bytes = utf8.encode('pakket');
        final digest = sha256.convert(bytes).toString();
        transport.responses.add(
          _json({
            'revision': 2,
            'submitted_at': '2026-10-05T09:00:00Z',
            'sha256': digest,
            'size': bytes.length,
          }, statusCode: 201),
        );

        final receipt = await respondent.submit(
          grant: _grant,
          idempotencyKey: 'sub-key-1',
          expectedSha256: digest,
          expectedSize: bytes.length,
        );

        final request = transport.requests.single;
        expect(request.url.path, endsWith('/submissions/locator-1/submit'));
        expect(request.headers['idempotency-key'], 'sub-key-1');
        expect(receipt.revision, 2);
      },
    );

    test('submit-weigert een ontboeke digest ook als de rest klopt', () async {
      transport.responses.add(
        _json({
          'revision': 2,
          'submitted_at': '2026-10-05T09:00:00Z',
          'sha256': 'f' * 64,
          'size': 6,
        }, statusCode: 201),
      );

      await expectLater(
        respondent.submit(
          grant: _grant,
          idempotencyKey: 'sub-key-1',
          expectedSha256: sha256.convert(utf8.encode('pakket')).toString(),
          expectedSize: 6,
        ),
        throwsA(_serveCode('intake_digest_mismatch')),
      );
    });

    test('withdraw eist dat de server withdrawn rapporteert', () async {
      transport.responses.add(_json({'state': 'submitted'}));

      await expectLater(
        respondent.withdraw(grant: _grant, idempotencyKey: 'wd-1'),
        throwsA(_serveCode('invalid_response')),
      );
    });

    test('withdraw slaagt met state withdrawn', () async {
      transport.responses.add(_json({'state': 'withdrawn'}));

      final receipt = await respondent.withdraw(
        grant: _grant,
        idempotencyKey: 'wd-1',
      );

      expect(receipt.state, IntakeSubmissionState.withdrawn);
      expect(
        transport.requests.single.url.path,
        endsWith('/submissions/locator-1/withdraw'),
      );
    });

    test('401 op een grant-route wordt unauthorized', () async {
      transport.responses.add(
        _json(const {'detail': 'grant verlopen'}, statusCode: 401),
      );

      await expectLater(
        respondent.submission(grant: _grant),
        throwsA(_serveCode('unauthorized')),
      );
    });

    test('http als uitnodigingshost faalt voor het transport', () {
      expect(
        () => IntakeRespondentClient(baseUrl: 'http://serve.example'),
        throwsA(_serveCode('https_required')),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('fail-closed modellen', () {
    test('onbekende velden weigert elke parser', () {
      expect(
        () => IntakeChallenge.fromJson({
          'challenge_id': 'c',
          'expires_in': 1,
          'resend_after': 1,
          'extra': true,
        }),
        throwsFormatException,
      );
      expect(
        () => IntakeSubmissionSummary.fromJson(
          _submissionDetail()
            ..remove('created_at')
            ..remove('revisions')
            ..remove('correction_deadline')
            ..['surprise'] = 'x',
        ),
        throwsFormatException,
      );
    });

    test('onbekende enumwaarden weigeren in plaats van te raden', () {
      final formJson = _form()..['operational_status'] = 'hibernating';
      expect(() => IntakeForm.fromJson(formJson), throwsFormatException);

      expect(
        () => IntakeRespondentSubmission.fromJson({
          'locator': 'l',
          'state': 'archived',
          'revision': 0,
          'draft_present': false,
          'allowed_actions': const [],
        }),
        throwsFormatException,
      );

      expect(
        () => IntakeRespondentSubmission.fromJson({
          'locator': 'l',
          'state': 'draft',
          'revision': 0,
          'draft_present': false,
          'allowed_actions': const ['teleport'],
        }),
        throwsFormatException,
      );

      final summary = {
        'form_id': 'f',
        'name': 'n',
        'operational_status': 'open',
        'active_version': 1,
        'my_grant': 'eigenaar',
      };
      expect(() => IntakeFormSummary.fromJson(summary), throwsFormatException);

      expect(
        () => IntakeGrant.fromJson({
          'grant': 't',
          'expires_in': 1,
          'purpose': 'impersonate',
          'locator': 'l',
        }),
        throwsFormatException,
      );
    });

    test('een snapshot zonder strikt subobject of foute deadline faalt', () {
      expect(
        () => IntakeFormSnapshot.fromJson(
          _snapshot()
            ..['retention'] = const {
              'draft_days': 30,
              'submitted_days': 365,
              'bonus': 1,
            },
        ),
        throwsFormatException,
      );
      expect(
        () => IntakeFormSnapshot.fromJson(
          _snapshot()
            ..['correction_policy'] = const {
              'allowed': true,
              'deadline_days': 'veertien',
            },
        ),
        throwsFormatException,
      );
      expect(
        () => IntakeFormSnapshot.fromJson(_snapshot()..['format'] = 'other/9'),
        throwsFormatException,
      );
    });

    test('sha256-velden eisen exact 64 hextekens', () {
      expect(
        () => IntakeDraftReceipt.fromJson(const {'sha256': 'abc', 'size': 1}),
        throwsFormatException,
      );
      expect(
        IntakeDraftReceipt.fromJson({'sha256': 'a' * 64, 'size': 1}).sha256,
        'a' * 64,
      );
    });
  });
}
