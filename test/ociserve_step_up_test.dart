import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_step_up.dart';

const _challenge =
    'Bearer error="insufficient_user_authentication", '
    'error_description="a stronger or more recent sign-in is required", '
    'acr_values="phr mfa", max_age="300"';

OciServeStepUpRequired? _parse(String header) =>
    parseOciServeStepUpChallenge({'www-authenticate': header});

void main() {
  group('de uitdaging lezen', () {
    test('neemt acr_values en max_age over', () {
      final need = _parse(_challenge)!;
      expect(need.acrValues, ['phr', 'mfa']);
      expect(need.maxAge, const Duration(seconds: 300));
      expect(need.code, 'step_up_required');
      expect(need.statusCode, 401);
    });

    test('zoekt de header zonder letterlijke hoofdletters', () {
      expect(
        parseOciServeStepUpChallenge({'WWW-Authenticate': _challenge}),
        isNotNull,
      );
    });

    test('een uitdaging zonder parameters is er nog steeds een', () {
      // Een AMR-eis kan RFC 9470 niet uitdrukken: dan staat er alleen de fout.
      final need = _parse('Bearer error="insufficient_user_authentication"')!;
      expect(need.acrValues, isEmpty);
      expect(need.maxAge, isNull);
    });

    test('leest ook waarden zonder aanhalingstekens en met escapes', () {
      final need = _parse(
        r'Bearer error=insufficient_user_authentication, max_age=60, '
        r'acr_values="urn:x\:y"',
      )!;
      expect(need.maxAge, const Duration(seconds: 60));
      expect(need.acrValues, ['urn:x:y']);
    });

    test('een andere fout is geen stap-omhoog', () {
      expect(_parse('Bearer error="invalid_token"'), isNull);
      expect(_parse('Bearer realm="x"'), isNull);
      expect(_parse('Basic realm="x"'), isNull);
    });

    test('de fout moet een echte parameter zijn, geen tekst in een waarde', () {
      expect(
        _parse(
          'Bearer realm="a error=insufficient_user_authentication", '
          'error="invalid_token"',
        ),
        isNull,
      );
      expect(
        _parse(
          'Bearer error_description="error=insufficient_user_authentication"',
        ),
        isNull,
      );
    });

    test('zonder header, leeg of te groot is het geen uitdaging', () {
      expect(parseOciServeStepUpChallenge(const {}), isNull);
      expect(_parse(''), isNull);
      expect(_parse('$_challenge, x="${'a' * 2100}"'), isNull);
    });

    test('begrenst en controleert wat naar de provider gaat', () {
      // Een max_age buiten bereik of onleesbaar wordt genegeerd, de uitdaging
      // blijft staan.
      for (final bad in ['-1', '31622401', 'tien', '1.5', '']) {
        final need = _parse(
          'Bearer error="insufficient_user_authentication", max_age="$bad"',
        )!;
        expect(need.maxAge, isNull, reason: bad);
      }
      expect(
        _parse(
          'Bearer error="insufficient_user_authentication", max_age="31622400"',
        )!.maxAge,
        const Duration(seconds: 31622400),
      );
      // Een acr met een aanhalingsteken valt weg; de rest blijft.
      expect(
        _parse(
          r'Bearer error="insufficient_user_authentication", acr_values="a\"b c"',
        )!.acrValues,
        ['c'],
      );
      // Te veel of te lange waarden worden afgekapt.
      final many = List.generate(12, (i) => 'v$i').join(' ');
      expect(
        _parse(
          'Bearer error="insufficient_user_authentication", acr_values="$many"',
        )!.acrValues,
        hasLength(8),
      );
      expect(
        _parse(
          'Bearer error="insufficient_user_authentication", '
          'acr_values="${'a' * 257} ok"',
        )!.acrValues,
        ['ok'],
      );
    });
  });

  group('de gateway', () {
    late _Transport transport;
    late OciServeGateway gateway;

    setUp(() {
      transport = _Transport();
      gateway = OciServeGateway(
        settings: const OciServeSettings(
          enabled: true,
          baseUrl: 'https://learn.example',
        ),
        transport: transport,
      );
    });

    Future<void> report() => gateway.reportPlayback(
      accessToken: 'old',
      organizationId: 'org',
      snapshot: OciServePlaybackSnapshot(
        sessionId: 'session-1',
        courseVersionId: 'v1',
        lessonId: 'l1',
        startedAt: DateTime.utc(2026, 9, 6, 10),
        completed: true,
        slideTimeMs: const {'slide-a': 1200},
      ),
    );

    test(
      'gooit de uitdaging naar de aanroeper zolang niemand haar afhandelt',
      () {
        transport.responses.add(_unauthorized(_challenge));

        expect(
          report(),
          throwsA(
            isA<OciServeStepUpRequired>()
                .having((e) => e.acrValues, 'acrValues', ['phr', 'mfa'])
                .having(
                  (e) => e.maxAge,
                  'maxAge',
                  const Duration(seconds: 300),
                ),
          ),
        );
      },
    );

    test(
      'herhaalt het verzoek één keer met het nieuwe token en dezelfde sleutel',
      () async {
        transport.responses
          ..add(_unauthorized(_challenge))
          ..add(_ok());
        var calls = 0;
        gateway.stepUpHandler = (need) async {
          calls++;
          expect(need.maxAge, const Duration(seconds: 300));
          return 'fresh';
        };

        await report();

        expect(calls, 1);
        expect(transport.requests, hasLength(2));
        expect(transport.requests[0].headers['authorization'], 'Bearer old');
        expect(transport.requests[1].headers['authorization'], 'Bearer fresh');
        // Hetzelfde verzoek: een herhaling mag nooit een tweede boeking of
        // tweede rapport worden.
        expect(transport.requests[1].method, transport.requests[0].method);
        expect(transport.requests[1].url, transport.requests[0].url);
        expect(
          transport.requests[1].headers['idempotency-key'],
          transport.requests[0].headers['idempotency-key'],
        );
        expect(transport.requests[1].body, transport.requests[0].body);
      },
    );

    test(
      'een tweede uitdaging na de herhaling wordt een fout, geen lus',
      () async {
        transport.responses
          ..add(_unauthorized(_challenge))
          ..add(_unauthorized(_challenge));
        var calls = 0;
        gateway.stepUpHandler = (need) async {
          calls++;
          return 'fresh';
        };

        await expectLater(report(), throwsA(isA<OciServeStepUpRequired>()));

        expect(calls, 1);
        expect(transport.requests, hasLength(2));
      },
    );

    test(
      'een mislukte stap-omhoog stopt het verzoek zonder herhaling',
      () async {
        transport.responses.add(_unauthorized(_challenge));
        gateway.stepUpHandler = (_) async =>
            throw const OciServeException('authorization_timeout');

        await expectLater(
          report(),
          throwsA(
            isA<OciServeException>().having(
              (e) => e.code,
              'code',
              'authorization_timeout',
            ),
          ),
        );
        expect(transport.requests, hasLength(1));
      },
    );

    test(
      'een gewone 401 blijft "unauthorized" en roept de handler niet aan',
      () async {
        var calls = 0;
        gateway.stepUpHandler = (_) async {
          calls++;
          return 'fresh';
        };
        for (final header in [
          null,
          'Bearer error="invalid_token", error_description="expired"',
          'Bearer realm="ociserve"',
        ]) {
          transport.responses.add(_unauthorized(header));
          await expectLater(
            report(),
            throwsA(
              isA<OciServeException>()
                  .having((e) => e.code, 'code', 'unauthorized')
                  .having(
                    (e) => e is OciServeStepUpRequired,
                    'stap-omhoog',
                    false,
                  ),
            ),
          );
        }
        expect(calls, 0);
      },
    );

    test('andere statussen raken de uitdaging niet', () async {
      var calls = 0;
      gateway.stepUpHandler = (_) async {
        calls++;
        return 'fresh';
      };
      transport.responses.add(
        OciServeHttpResponse(
          statusCode: 403,
          body: Uint8List(0),
          headers: const {'www-authenticate': _challenge},
        ),
      );

      await expectLater(
        report(),
        throwsA(
          isA<OciServeException>().having((e) => e.code, 'code', 'http_error'),
        ),
      );
      expect(calls, 0);
    });
  });
}

class _Sent {
  _Sent(this.method, this.url, this.headers, this.body);
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int>? body;
}

class _Transport implements OciServeHttpTransport {
  final responses = <OciServeHttpResponse>[];
  final requests = <_Sent>[];

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
    requests.add(_Sent(method, url, headers, body));
    return responses.removeAt(0);
  }
}

OciServeHttpResponse _ok() => OciServeHttpResponse(
  statusCode: 200,
  body: Uint8List.fromList(utf8.encode('{}')),
);

OciServeHttpResponse _unauthorized(String? challenge) => OciServeHttpResponse(
  statusCode: 401,
  body: Uint8List(0),
  headers: {'www-authenticate': ?challenge},
);
