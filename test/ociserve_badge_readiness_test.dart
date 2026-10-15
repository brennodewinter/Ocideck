// #2422: het badge-leesmodel — vaardigheden, hun versies en per badge wat de
// cursist nog nodig heeft.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';

class _Request {
  _Request(this.method, this.url);
  final String method;
  final Uri url;
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
    requests.add(_Request(method, url));
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

  test('vaardigheden lezen geeft de organisatielijst', () async {
    transport.responses.add(
      _json({
        'skills': [
          {'id': 'skill-1', 'slug': 'bhv', 'title': 'BHV'},
          {'id': 'skill-2', 'slug': 'ehbo', 'title': 'EHBO'},
        ],
      }),
    );

    final skills = await gateway.organizationSkills(
      accessToken: 'access',
      organizationId: 'org',
    );

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/organizations/org/skills');
    expect(skills.map((s) => s.id), ['skill-1', 'skill-2']);
    expect(skills.first.title, 'BHV');
  });

  test('versies van een vaardigheid leveren de vertaalsleutel', () async {
    transport.responses.add(
      _json({
        'versions': [
          {'id': 'version-1', 'version': 1},
          {'id': 'version-2', 'version': 2},
        ],
      }),
    );

    final versions = await gateway.skillVersions(
      accessToken: 'access',
      organizationId: 'org',
      skillId: 'skill-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(
      request.url.path,
      '/api/v1/organizations/org/skills/skill-1/versions',
    );
    expect(versions.map((v) => v.id), ['version-1', 'version-2']);
  });

  test('badge-readiness leest eisen en klaar-status', () async {
    transport.responses.add(
      _json({
        'skill_id': 'skill-1',
        'skill_title': 'BHV',
        'kwalificatiesoort': 'bekwaamheid',
        'validity_months': 12,
        'requirements': [
          {'kind': 'course', 'title': 'Basiscursus', 'met': true},
          {
            'kind': 'evidence',
            'title': 'Certificaat',
            'evidence_type': 'bhv-certificaat',
            'min_assurance': 'kopie_beoordeeld',
            'met': false,
          },
          {
            'kind': 'exam',
            'title': 'Eindtoets',
            'blueprint_id': 'bp-1',
            'met': false,
          },
        ],
        'ready': false,
      }),
    );

    final model = await gateway.badgeReadiness(
      accessToken: 'access',
      organizationId: 'org',
      participantId: 'p1',
      skillId: 'skill-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(
      request.url.path,
      '/api/v1/organizations/org/participants/p1/skills/skill-1/badge-readiness',
    );
    expect(model.skillTitle, 'BHV');
    expect(model.kwalificatiesoort, 'bekwaamheid');
    expect(model.validityMonths, 12);
    expect(model.ready, isFalse);
    expect(model.requirements, hasLength(3));
    final evidence = model.requirements[1];
    expect(evidence.kind, 'evidence');
    expect(evidence.evidenceType, 'bhv-certificaat');
    expect(evidence.minAssurance, 'kopie_beoordeeld');
    expect(evidence.met, isFalse);
    expect(model.requirements[0].met, isTrue);
    expect(model.requirements[2].blueprintId, 'bp-1');
  });

  test('badge-readiness zonder skill_id is een contractbreuk', () async {
    transport.responses.add(_json({'skill_title': 'BHV', 'ready': false}));

    await expectLater(
      gateway.badgeReadiness(
        accessToken: 'access',
        organizationId: 'org',
        participantId: 'p1',
        skillId: 'skill-1',
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
}
