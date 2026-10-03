// De client van het inzendprotocol, het deel dat een uitnodiging opent (INTAKE_PROTOCOL.md §3,
// §4.1, §4.2): wat hij van de server gelooft, en in welke volgorde hij het toetst.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/intake/intake_client.dart';
import 'package:ocideck/services/form/intake/intake_http.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/fake_intake_server.dart';
import 'support/intake_test_form.dart';

final DateTime now = DateTime.utc(2026, 11, 3);

IntakeFailed failed(IntakeOpenResult r) {
  expect(r, isA<IntakeFailed>());
  return r as IntakeFailed;
}

IntakeOpened opened(IntakeOpenResult r) {
  expect(
    r,
    isA<IntakeOpened>(),
    reason: r is IntakeFailed ? '${r.problem}' : '',
  );
  return r as IntakeOpened;
}

void main() {
  group('een uitnodiging openen', () {
    test(
      'geeft elk sjabloon waarvan de bundel is geloofd, met zijn formulier',
      () async {
        final f = await serverWith(['nl', 'en']);
        final r = opened(
          await IntakeClient(f.server).openInvitation(
            f.organiser.invite(),
            pins: const FormBundlePins(),
            now: now,
          ),
        );
        expect(r.variants.map((v) => v.spec.lang), ['nl', 'en']);
        expect(r.variants.map((v) => v.spec.id), ['kook', 'kook']);
        expect(r.variants[0].template, templateIn('nl'));
        expect(r.variants[0].verified.owner.name, 'Indo IT Kookboek-team');
        expect(
          r.variants[0].verified.fingerprint,
          f.organiser.signing.fingerprint,
        );
        expect((jsonDecode(r.variants[0].bundleText) as Map)['fid'], kTestFid);
        expect(r.state, IntakeFormState.open);
        expect(r.info.protocol, 1);
        expect(r.info.maxPackageBytes, 60 * 1024 * 1024);
        expect(r.invite.fid, kTestFid);
      },
    );

    test(
      'vraagt eerst de server en dan het formulier, zonder iets mee te sturen',
      () async {
        final f = await serverWith(['nl']);
        await IntakeClient(f.server).openInvitation(
          f.organiser.invite(),
          pins: const FormBundlePins(),
          now: now,
        );
        expect(f.server.requests.map((r) => '${r.method} ${r.target}'), [
          'GET /v1/info',
          'GET /v1/forms/$kTestFid',
        ]);
        for (final request in f.server.requests) {
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'intake.example.org');
          expect(
            request.url.hasFragment,
            isFalse,
            reason: 'het fragment gaat nooit naar de server',
          );
          expect(request.headers.keys.map((k) => k.toLowerCase()), ['accept']);
          expect(request.body, isEmpty);
        }
      },
    );

    test(
      'de bundels van verschillende talen hebben elk hun volgnummer, en de pins nemen het hoogste',
      () async {
        final f = await serverWith([]);
        f.server.publish(kTestFid, [
          await f.organiser.variant(templateIn('nl'), seq: 3),
          await f.organiser.variant(templateIn('en'), seq: 4),
          await f.organiser.variant(templateIn('de'), seq: 5),
        ]);
        final r = opened(
          await IntakeClient(f.server).openInvitation(
            f.organiser.invite(),
            pins: const FormBundlePins(),
            now: now,
          ),
        );
        expect(r.variants, hasLength(3));
        expect(r.pins.seqFor(kTestFid, f.organiser.signing.fingerprint), 5);
      },
    );

    test(
      'toetst elke bundel aan de pins van vóór het antwoord: een lagere volgorde in dezelfde reeks is geen terugval',
      () async {
        final f = await serverWith([]);
        // Het hoogste volgnummer staat vóór het lagere.
        f.server.publish(kTestFid, [
          await f.organiser.variant(templateIn('en'), seq: 6),
          await f.organiser.variant(templateIn('nl'), seq: 4),
        ]);
        final r = opened(
          await IntakeClient(f.server).openInvitation(
            f.organiser.invite(),
            pins: const FormBundlePins(),
            now: now,
          ),
        );
        expect(r.variants.map((v) => v.spec.lang), ['en', 'nl']);
        expect(r.pins.seqFor(kTestFid, f.organiser.signing.fingerprint), 6);
      },
    );

    test(
      'een bundel onder het volgnummer dat de invuller al zag valt af, de andere blijft',
      () async {
        final f = await serverWith([]);
        f.server.publish(kTestFid, [
          await f.organiser.variant(templateIn('nl'), seq: 4),
          await f.organiser.variant(templateIn('en'), seq: 6),
        ]);
        final fp = f.organiser.signing.fingerprint;
        final seen = const FormBundlePins().accepting(
          (await verifyFormBundle(
                    f.server.forms[kTestFid]!.variants[1].bundleText,
                    templateText: templateIn('en'),
                    fingerprint: fp,
                    now: now,
                  )
                  as FormBundleVerified)
              .bundle,
          fp,
        );
        final r = opened(
          await IntakeClient(
            f.server,
          ).openInvitation(f.organiser.invite(), pins: seen, now: now),
        );
        // Gezien: 6. De bundel met 4 is een terugval; die met 6 is gelijk en dus goed.
        expect(r.variants.map((v) => v.spec.lang), ['en']);
      },
    );

    test(
      'een sluitende server wordt gemeld, de bundels blijven geloofd',
      () async {
        final f = await serverWith(['nl'], state: IntakeFormState.closed);
        final r = opened(
          await IntakeClient(f.server).openInvitation(
            f.organiser.invite(),
            pins: const FormBundlePins(),
            now: now,
          ),
        );
        expect(r.state, IntakeFormState.closed);
        expect(r.variants, hasLength(1));
      },
    );

    group('wat de bundel zegt', () {
      Future<IntakeFailed> open(
        FakeIntakeServer server,
        InviteLink invite, {
        FormBundlePins pins = const FormBundlePins(),
      }) async => failed(
        await IntakeClient(server).openInvitation(invite, pins: pins, now: now),
      );

      test(
        'een andere vingerafdruk dan de uitnodiging noemt: niets wordt geloofd',
        () async {
          final f = await serverWith(['nl']);
          final other = await IntakeTestOrganiser.create();
          final r = await open(
            f.server,
            f.organiser.invite(fingerprint: other.signing.fingerprint),
          );
          expect(r.problem, IntakeProblem.bundleRefused);
          expect(r.bundleIssue, FormBundleIssue.fingerprintMismatch);
        },
      );

      test(
        'een bundel van een ander, met de vingerafdruk van die ander',
        () async {
          // De server publiceert een bundel die een vreemde tekende; de uitnodiging noemt de vreemde
          // niet, dus de vingerafdruk past niet.
          final f = await serverWith([]);
          final stranger = await IntakeTestOrganiser.create();
          f.server.publish(kTestFid, [
            await stranger.variant(templateIn('nl')),
          ]);
          final r = await open(f.server, f.organiser.invite());
          expect(r.bundleIssue, FormBundleIssue.fingerprintMismatch);
        },
      );

      test('een sjabloon dat niet is wat de bundel ondertekende', () async {
        final f = await serverWith([]);
        f.server.publish(kTestFid, [
          await f.organiser.variant(
            templateIn('nl'),
            templateOverride: templateIn(
              'nl',
            ).replaceAll('Naam', 'Geboortedatum'),
          ),
        ]);
        final r = await open(f.server, f.organiser.invite());
        expect(r.bundleIssue, FormBundleIssue.templateMismatch);
      });

      test('een bundel voor het adres van een andere server', () async {
        final f = await serverWith([]);
        f.server.publish(kTestFid, [
          await f.organiser.variant(
            templateIn('nl'),
            host: 'elders.example.org',
          ),
        ]);
        final r = await open(f.server, f.organiser.invite());
        expect(r.bundleIssue, FormBundleIssue.hostMismatch);
      });

      test('een verlopen bundel', () async {
        final f = await serverWith([]);
        f.server.publish(kTestFid, [
          await f.organiser.variant(
            templateIn('nl'),
            expires: '2026-11-02',
            now: DateTime.utc(2026, 10, 1),
          ),
        ]);
        final r = await open(f.server, f.organiser.invite());
        expect(r.bundleIssue, FormBundleIssue.expired);
      });

      test('een bundel onder het volgnummer dat de invuller al zag', () async {
        final f = await serverWith([]);
        f.server.publish(kTestFid, [
          await f.organiser.variant(templateIn('nl'), seq: 2),
        ]);
        final fp = f.organiser.signing.fingerprint;
        final seen = const FormBundlePins().accepting(
          (await verifyFormBundle(
                    (await f.organiser.variant(
                      templateIn('nl'),
                      seq: 9,
                    )).bundleText,
                    templateText: templateIn('nl'),
                    fingerprint: fp,
                    now: now,
                  )
                  as FormBundleVerified)
              .bundle,
          fp,
        );
        final r = await open(f.server, f.organiser.invite(), pins: seen);
        expect(r.bundleIssue, FormBundleIssue.rollback);
      });

      test(
        'een bundel voor een ander formulier van dezelfde organisator is niet dit formulier',
        () async {
          final f = await serverWith([]);
          f.server.publish(kTestFid, [
            await f.organiser.variant(
              templateIn('nl'),
              fid: 'nvqwy3dpoixxg5dfonzgc3tjnq',
            ),
          ]);
          final r = await open(f.server, f.organiser.invite());
          expect(r.problem, IntakeProblem.bundleRefused);
          expect(r.bundleIssue, FormBundleIssue.templateMismatch);
        },
      );

      test('een bundel die niet slaagt valt af en de andere blijft', () async {
        final f = await serverWith([]);
        f.server.publish(kTestFid, [
          await f.organiser.variant(
            templateIn('nl'),
            expires: '2020-01-01',
            now: DateTime.utc(2019, 12, 1),
          ),
          await f.organiser.variant(templateIn('en')),
        ]);
        final r = opened(
          await IntakeClient(f.server).openInvitation(
            f.organiser.invite(),
            pins: const FormBundlePins(),
            now: now,
          ),
        );
        expect(r.variants.map((v) => v.spec.lang), ['en']);
      });

      test(
        'zonder een geloofde bundel noemt de weigering de reden van de eerste',
        () async {
          final f = await serverWith([]);
          f.server.publish(kTestFid, [
            await f.organiser.variant(
              templateIn('nl'),
              expires: '2020-01-01',
              now: DateTime.utc(2019, 12, 1),
            ),
            await f.organiser.variant(
              templateIn('en'),
              templateOverride: templateIn('en').replaceAll('Naam', 'x'),
            ),
          ]);
          final r = await open(f.server, f.organiser.invite());
          expect(r.bundleIssue, FormBundleIssue.expired);
        },
      );
    });

    group('wat de server zegt', () {
      Future<IntakeFailed> open(
        FakeIntakeServer server, [
        InviteLink? invite,
      ]) async => failed(
        await IntakeClient(server).openInvitation(
          invite ?? (await IntakeTestOrganiser.create()).invite(),
          pins: const FormBundlePins(),
          now: now,
        ),
      );

      test('een server die te nieuw is', () async {
        final f = await serverWith(['nl']);
        f.server.protocol = 2;
        final r = await open(f.server, f.organiser.invite());
        expect(r.problem, IntakeProblem.serverTooNew);
        expect(
          f.server.requests,
          hasLength(1),
          reason: 'het formulier wordt dan niet eens gevraagd',
        );
      });

      test('een server die te oud is', () async {
        final f = await serverWith(['nl']);
        f.server.protocol = 0;
        final r = await open(f.server, f.organiser.invite());
        expect(r.problem, IntakeProblem.serverTooOld);
      });

      test('een adres dat geen inzendserver is', () async {
        final f = await serverWith(['nl']);
        f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
          200,
          '<html>Welkom</html>',
        );
        expect(
          (await open(f.server, f.organiser.invite())).problem,
          IntakeProblem.notIntakeServer,
        );
        f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
          200,
          '{"protocol":"x"}',
        );
        expect(
          (await open(f.server, f.organiser.invite())).problem,
          IntakeProblem.notIntakeServer,
        );
      });

      test(
        'een weigering met een code van het protocol, met de zin van de server',
        () async {
          final server = FakeIntakeServer(); // niets gepubliceerd
          final r = await open(server);
          expect(r.problem, IntakeProblem.serverRefused);
          expect(r.error!.code, IntakeErrorCode.formUnknown);
          expect(r.error!.message, 'Fout: form-unknown');
          expect(server.requests, hasLength(2));
        },
      );

      test(
        'een pagina van een proxy als antwoord geeft toch een fout, via de status',
        () async {
          final f = await serverWith(['nl']);
          f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
            502,
            '<html>Bad gateway</html>',
          );
          final r = await open(f.server, f.organiser.invite());
          expect(r.problem, IntakeProblem.serverRefused);
          expect(r.error!.code, IntakeErrorCode.serverError);
          expect(r.error!.message, isEmpty);
        },
      );

      test(
        'een verzoek om later terug te komen, begrensd tot een dag',
        () async {
          final f = await serverWith(['nl']);
          Future<Duration?> retry(String header) async {
            f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
              429,
              IntakeError(
                IntakeErrorCode.rateLimited,
                'Rustig aan.',
              ).toJsonText(),
              headers: {'retry-after': header},
            );
            final r = await open(f.server, f.organiser.invite());
            expect(r.error!.code, IntakeErrorCode.rateLimited);
            return r.retryAfter;
          }

          expect(await retry('120'), const Duration(minutes: 2));
          expect(await retry(' 5 '), const Duration(seconds: 5));
          expect(await retry('0'), Duration.zero);
          expect(await retry('86400'), const Duration(days: 1));
          expect(await retry('86401'), const Duration(days: 1));
          expect(await retry('999999999'), const Duration(days: 1));
          expect(await retry('-1'), isNull);
          expect(await retry('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
          expect(await retry('x'), isNull);
        },
      );

      test(
        'een formulier dat niet te lezen is, met wat eraan mankeert',
        () async {
          final f = await serverWith(['nl']);
          f.server.overrides['/v1/forms/$kTestFid'] = FakeIntakeServer.raw(
            200,
            '{"state":"open","variants":[]}',
          );
          final r = await open(f.server, f.organiser.invite());
          expect(r.problem, IntakeProblem.formMalformed);
          expect(r.formIssue, IntakeFormIssue.noVariants);
        },
      );

      test('een antwoord dat geen UTF-8 is, is geen formulier', () async {
        final f = await serverWith(['nl']);
        f.server.overrides['/v1/forms/$kTestFid'] = IntakeHttpResponse(
          statusCode: 200,
          body: Uint8List.fromList([0x7b, 0xff, 0xfe, 0x7d]),
        );
        final r = await open(f.server, f.organiser.invite());
        expect(r.problem, IntakeProblem.formMalformed);
        expect(r.formIssue, IntakeFormIssue.notAForm);
      });

      for (final failure in IntakeHttpFailure.values) {
        test(
          'een verzoek dat mislukt (${failure.name}) is "geen antwoord"',
          () async {
            final f = await serverWith(['nl']);
            f.server.failWith = failure;
            final r = await open(f.server, f.organiser.invite());
            expect(r.problem, IntakeProblem.unreachable);
            expect(r.http, failure);
          },
        );
      }

      test('de server kan ook halverwege wegvallen', () async {
        final f = await serverWith(['nl']);
        f.server.overrides['/v1/forms/$kTestFid'] = FakeIntakeServer.raw(
          200,
          '{}',
        );
        // Het antwoord is te groot voor wat de client vroeg: de HTTP-laag meldt dat.
        f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
          200,
          'x' * (64 * 1024 + 1),
        );
        final r = await open(f.server, f.organiser.invite());
        expect(r.problem, IntakeProblem.unreachable);
        expect(r.http, IntakeHttpFailure.responseTooLarge);
      });
    });

    test(
      'vraagt de server om hooguit 64 KiB en het formulier om hooguit wat een formulier mag zijn',
      () async {
        final f = await serverWith(['nl']);
        final spy = _Spy(f.server);
        await IntakeClient(spy).openInvitation(
          f.organiser.invite(),
          pins: const FormBundlePins(),
          now: now,
        );
        expect(spy.maxFor('/v1/info'), 64 * 1024);
        expect(spy.maxFor('/v1/forms/$kTestFid'), kIntakeMaxFormBytes + 1024);
      },
    );

    test(
      'geeft de HTTP-laag de tijd die hij kreeg, en anders dertig seconden',
      () async {
        final f = await serverWith(['nl']);
        final spy = _Spy(f.server);
        await IntakeClient(
          spy,
          timeout: const Duration(seconds: 7),
        ).openInvitation(
          f.organiser.invite(),
          pins: const FormBundlePins(),
          now: now,
        );
        expect(spy.timeouts, [
          const Duration(seconds: 7),
          const Duration(seconds: 7),
        ]);
        final other = _Spy(f.server);
        await IntakeClient(other).openInvitation(
          f.organiser.invite(),
          pins: const FormBundlePins(),
          now: now,
        );
        expect(other.timeouts, [
          const Duration(seconds: 30),
          const Duration(seconds: 30),
        ]);
      },
    );

    test('een poort in het adres blijft staan in het doel', () async {
      final organiser = await IntakeTestOrganiser.create();
      final server = FakeIntakeServer(host: 'intake.example.org:8443');
      server.publish(kTestFid, [
        await organiser.variant(
          templateIn('nl'),
          host: 'intake.example.org:8443',
        ),
      ]);
      final r = opened(
        await IntakeClient(server).openInvitation(
          organiser.invite(host: 'intake.example.org:8443'),
          pins: const FormBundlePins(),
          now: now,
        ),
      );
      expect(r.variants, hasLength(1));
      expect(server.requests.first.url.port, 8443);
    });
  });
}

/// Een [IntakeHttp] die doorgeeft en noteert wat de client vroeg.
class _Spy implements IntakeHttp {
  _Spy(this.inner);

  final IntakeHttp inner;
  final Map<String, int> _max = {};
  final List<Duration> timeouts = [];

  /// De begrenzing waarmee [path] is gevraagd.
  int? maxFor(String path) => _max[path];

  @override
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  }) {
    _max[url.path] = maxResponseBytes;
    timeouts.add(timeout);
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
