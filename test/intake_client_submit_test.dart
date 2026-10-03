// De client van het inzendprotocol, het deel dat een inzending verstuurt (INTAKE_PROTOCOL.md §4.3):
// wat de server krijgt en wat niet, en wat de client gelooft van wat de server terugzegt.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/intake/intake_client.dart';
import 'package:ocideck/services/form/intake/intake_http.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/fake_intake_server.dart';
import 'support/intake_test_form.dart';

const String _sid = 'bcdefghijklmnopqrstuvwxyza';
final String _secret = 'ma' * 26;

late FakeIntakeServer _server;
late IntakeTestOrganiser _organiser;
late Uint8List _sealed;

Future<IntakeSubmitResult> _submit({
  Uint8List? sealed,
  String sid = _sid,
  InviteLink? invite,
  Duration? timeout,
}) => IntakeClient(_server, timeout: timeout).submit(
  invite: invite ?? _organiser.invite(),
  sid: sid,
  sealed: sealed ?? _sealed,
  withdrawalSecret: _secret,
);

IntakeFailed _failed(IntakeSubmitResult r) {
  expect(r, isA<IntakeFailed>());
  return r as IntakeFailed;
}

IntakeSubmitted _submitted(IntakeSubmitResult r) {
  expect(
    r,
    isA<IntakeSubmitted>(),
    reason: r is IntakeFailed ? '${r.problem} ${r.error?.code}' : '',
  );
  return r as IntakeSubmitted;
}

void main() {
  setUp(() async {
    final f = await serverWith(['nl']);
    _server = f.server;
    _organiser = f.organiser;
    _sealed = await sealedSubmission(_organiser);
  });

  group('een inzending versturen', () {
    test(
      'de server bewaart de bytes en antwoordt met een aankomstbericht dat erover gaat',
      () async {
        final r = _submitted(await _submit());
        expect(r.alreadyHeld, isFalse);
        expect(r.note.sid, _sid);
        expect(r.note.at, '2026-11-03T09:30:12Z');
        expect(r.note.ciphertextSha256, sha256Hex(_sealed));
        expect(r.note.contact, 'redactie@example.org');
        expect(_server.submissions[_sid]!.bytes, _sealed);
      },
    );

    test(
      'stuurt een PUT met de kopen van het protocol, en niets anders',
      () async {
        await _submit();
        final request = _server.requests.single;
        expect(request.method, 'PUT');
        expect(request.target, '/v1/submissions/$_sid');
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'intake.example.org');
        expect(request.headers, {
          'accept': 'application/json',
          'content-type': 'application/octet-stream',
          'intake-form': kTestFid,
          'intake-token': kTestInvite,
          'intake-withdrawal': withdrawalSecretHash(_secret),
        });
        expect(request.body, _sealed);
      },
    );

    test('het geheim zelf gaat nergens heen, alleen zijn hash', () async {
      await _submit();
      final request = _server.requests.single;
      final seen = [
        request.url.toString(),
        ...request.headers.values,
        utf8.decode(request.body, allowMalformed: true),
      ].join('\n');
      expect(seen, isNot(contains(_secret)));
      expect(request.headers['intake-withdrawal'], hasLength(64));
    });

    test(
      'een herhaling met dezelfde bytes is veilig: hetzelfde bericht, en de server heeft hem al',
      () async {
        final first = _submitted(await _submit());
        final again = _submitted(await _submit());
        expect(again.alreadyHeld, isTrue);
        expect(again.note.at, first.note.at);
        expect(again.note.ciphertextSha256, first.note.ciphertextSha256);
        expect(_server.submissions, hasLength(1));
      },
    );

    test(
      'een ander pakket onder hetzelfde nummer wordt geweigerd, en overschrijft niets',
      () async {
        await _submit();
        final other = await sealedSubmission(
          _organiser,
          answer: 'Iemand anders',
        );
        final r = _failed(await _submit(sealed: other));
        expect(r.problem, IntakeProblem.serverRefused);
        expect(r.error!.code, IntakeErrorCode.submissionConflict);
        expect(_server.submissions[_sid]!.bytes, _sealed);
      },
    );

    test(
      'een andere uitnodigingstoken: de uitnodiging is niet geldig',
      () async {
        final wrong = InviteLink(
          shellBase: 'https://forms.example.org',
          fid: kTestFid,
          apiHost: 'intake.example.org',
          fingerprint: _organiser.signing.fingerprint,
          token: newInviteToken(Random(5)),
        );
        final r = _failed(await _submit(invite: wrong));
        expect(r.error!.code, IntakeErrorCode.inviteInvalid);
        expect(_server.submissions, isEmpty);
      },
    );

    test('een ingetrokken token: niemand kan meer sturen', () async {
      _server.publish(kTestFid, _server.forms[kTestFid]!.variants, token: null);
      expect(
        _failed(await _submit()).error!.code,
        IntakeErrorCode.inviteInvalid,
      );
    });

    test('een formulier dat gesloten is', () async {
      _server.publish(
        kTestFid,
        _server.forms[kTestFid]!.variants,
        state: IntakeFormState.closed,
      );
      expect(_failed(await _submit()).error!.code, IntakeErrorCode.formClosed);
      expect(_server.submissions, isEmpty);
    });

    test('een formulier dat niet bestaat', () async {
      _server.forms.clear();
      expect(_failed(await _submit()).error!.code, IntakeErrorCode.formUnknown);
    });

    test('een pakket boven wat de server toestaat', () async {
      _server.maxPackageBytes = _sealed.length - 1;
      expect(_failed(await _submit()).error!.code, IntakeErrorCode.tooLarge);
      _server.maxPackageBytes = _sealed.length;
      _submitted(await _submit());
    });

    test('een drukke server, met wanneer terug te komen', () async {
      _server.rateLimited = 1;
      _server.retryAfter = const Duration(seconds: 90);
      final r = _failed(await _submit());
      expect(r.error!.code, IntakeErrorCode.rateLimited);
      expect(r.retryAfter, const Duration(seconds: 90));
      // De tweede poging slaagt.
      _submitted(await _submit());
    });

    for (final failure in IntakeHttpFailure.values) {
      test(
        'een verzoek dat mislukt (${failure.name}) is "geen antwoord"',
        () async {
          _server.failWith = failure;
          final r = _failed(await _submit());
          expect(r.problem, IntakeProblem.unreachable);
          expect(r.http, failure);
        },
      );
    }

    test(
      'na een verbindingsfout kan hij worden herhaald met dezelfde bytes, en komt hij één keer aan',
      () async {
        _server.failWith = IntakeHttpFailure.timeout;
        _failed(await _submit());
        _server.failWith = null;
        final r = _submitted(await _submit());
        expect(r.alreadyHeld, isFalse);
        expect(_server.submissions, hasLength(1));
      },
    );

    group('wat de server terugzegt', () {
      Future<IntakeFailed> withAnswer(int status, String body) async {
        _server.overrides['/v1/submissions/$_sid'] = FakeIntakeServer.raw(
          status,
          body,
        );
        return _failed(await _submit());
      }

      test('een bericht over een ander inzendnummer', () async {
        final note = IntakeArrivalNote(
          sid: 'mfrggzdfmztwq2lknnwg23tpoa',
          at: '2026-11-03T09:30:12Z',
          ciphertextSha256: sha256Hex(_sealed),
          contact: 'x@example.org',
        );
        expect(
          (await withAnswer(201, note.toJsonText())).problem,
          IntakeProblem.noteMismatch,
        );
      });

      test('een bericht over andere bytes', () async {
        final note = IntakeArrivalNote(
          sid: _sid,
          at: '2026-11-03T09:30:12Z',
          ciphertextSha256: 'ab' * 32,
          contact: 'x@example.org',
        );
        expect(
          (await withAnswer(200, note.toJsonText())).problem,
          IntakeProblem.noteMismatch,
        );
        expect(
          (await withAnswer(201, note.toJsonText())).problem,
          IntakeProblem.noteMismatch,
        );
      });

      test('een antwoord dat geen bericht is', () async {
        for (final body in [
          '',
          'ok',
          '<html></html>',
          '{}',
          '[]',
          '{"sid":"x"}',
        ]) {
          expect(
            (await withAnswer(201, body)).problem,
            IntakeProblem.noteMismatch,
            reason: body,
          );
        }
      });

      test('een 2xx die geen 200 of 201 is, is geen aankomst', () async {
        final good = IntakeArrivalNote(
          sid: _sid,
          at: '2026-11-03T09:30:12Z',
          ciphertextSha256: sha256Hex(_sealed),
          contact: 'x@example.org',
        ).toJsonText();
        for (final status in [202, 204, 301, 302]) {
          final r = await withAnswer(status, good);
          expect(r.problem, IntakeProblem.serverRefused, reason: '$status');
        }
      });

      test('een proxy die antwoordt in plaats van de server', () async {
        final r = await withAnswer(502, '<html>Bad gateway</html>');
        expect(r.problem, IntakeProblem.serverRefused);
        expect(r.error!.code, IntakeErrorCode.serverError);
      });
    });

    test(
      'geeft de HTTP-laag tien minuten voor een upload, of wat de client kreeg',
      () async {
        final spy = _TimeoutSpy(_server);
        await IntakeClient(spy).submit(
          invite: _organiser.invite(),
          sid: _sid,
          sealed: _sealed,
          withdrawalSecret: _secret,
        );
        await IntakeClient(spy, timeout: const Duration(seconds: 42)).submit(
          invite: _organiser.invite(),
          sid: 'cdefghijklmnopqrstuvwxyzab',
          sealed: _sealed,
          withdrawalSecret: _secret,
        );
        expect(spy.timeouts, [
          const Duration(minutes: 10),
          const Duration(seconds: 42),
        ]);
        expect(spy.maxima, [64 * 1024, 64 * 1024]);
      },
    );

    test('een poort in het adres blijft staan', () async {
      final server = FakeIntakeServer(host: 'intake.example.org:8443');
      server.publish(kTestFid, [
        await _organiser.variant(
          templateIn('nl'),
          host: 'intake.example.org:8443',
        ),
      ]);
      final r = await IntakeClient(server).submit(
        invite: _organiser.invite(host: 'intake.example.org:8443'),
        sid: _sid,
        sealed: _sealed,
        withdrawalSecret: _secret,
      );
      expect(r, isA<IntakeSubmitted>());
      expect(server.requests.single.url.port, 8443);
    });
  });
}

class _TimeoutSpy implements IntakeHttp {
  _TimeoutSpy(this.inner);

  final IntakeHttp inner;
  final List<Duration> timeouts = [];
  final List<int> maxima = [];

  @override
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  }) {
    timeouts.add(timeout);
    maxima.add(maxResponseBytes);
    return inner.send(
      method: method,
      url: url,
      headers: headers,
      body: body,
      maxResponseBytes: maxResponseBytes,
      timeout: timeout,
    );
  }
}
