// #2423: de portefeuille-import — sessie aanmaken, teruglezen, selectie
// delen, bewijssoortversies ophalen en een bewijsstuk intrekken. Plus de
// publieke-link-fetch als derde-partij-egress.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_portfolio_import.dart';
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
  bool lastTrustedInternal = true;

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
    lastTrustedInternal = trustedInternal;
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

  test('import-sessie aanmaken post de gevonden items met sleutel', () async {
    transport.responses.add(_json({'import_id': 'imp-1'}, statusCode: 201));

    final id = await gateway.createPortfolioImport(
      accessToken: 'access',
      organizationId: 'org',
      participantId: 'p1',
      items: const [
        PortfolioImportItemInput(
          issuerId: 'https://roc.example',
          title: 'BHV',
          credentialId: 'cred-1',
        ),
      ],
      idempotencyKey: 'import-key-1',
    );

    expect(id, 'imp-1');
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.path,
      '/api/v1/organizations/org/participants/p1/portfolio-imports',
    );
    expect(request.headers['idempotency-key'], 'import-key-1');
    final sent = jsonDecode(utf8.decode(request.body!)) as Map;
    expect(sent['items'], hasLength(1));
    expect(sent['items'][0]['issuer_id'], 'https://roc.example');
  });

  test('import-sessie teruglezen geeft de items', () async {
    transport.responses.add(
      _json({
        'import_id': 'imp-1',
        'status': 'open',
        'items': [
          {'id': 'item-1', 'title': 'BHV', 'issuer_id': 'https://roc.example'},
          {
            'id': 'item-2',
            'title': 'EHBO',
            'issuer_id': 'https://roc.example',
            'selected': true,
          },
        ],
      }),
    );

    final session = await gateway.portfolioImport(
      accessToken: 'access',
      organizationId: 'org',
      participantId: 'p1',
      importId: 'imp-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(
      request.url.path,
      '/api/v1/organizations/org/participants/p1/portfolio-imports/imp-1',
    );
    expect(session.items, hasLength(2));
    expect(session.items[1].selected, isTrue);
  });

  test('select deelt alleen de gekozen items met soort én versie', () async {
    transport.responses.add(
      _json({
        'created_item_ids': ['ei-1'],
      }),
    );

    final created = await gateway.selectPortfolioItems(
      accessToken: 'access',
      organizationId: 'org',
      participantId: 'p1',
      importId: 'imp-1',
      selectedItemIds: const ['item-1'],
      evidenceTypeId: 'type-1',
      evidenceTypeVersionId: 'tv-1',
      idempotencyKey: 'select-key-1',
    );

    expect(created, ['ei-1']);
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.path,
      '/api/v1/organizations/org/participants/p1/portfolio-imports/imp-1/select',
    );
    final sent = jsonDecode(utf8.decode(request.body!)) as Map;
    expect(sent['selected_item_ids'], ['item-1']);
    expect(sent['evidence_type_id'], 'type-1');
    expect(sent['evidence_type_version_id'], 'tv-1');
  });

  test('bewijssoortversies geven id en versienummer', () async {
    transport.responses.add(
      _json({
        'versions': [
          {'id': 'tv-1', 'version': 1},
          {'id': 'tv-2', 'version': 2},
        ],
      }),
    );

    final versions = await gateway.evidenceTypeVersions(
      accessToken: 'access',
      organizationId: 'org',
      evidenceTypeId: 'type-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(
      request.url.path,
      '/api/v1/organizations/org/evidence-types/type-1/versions',
    );
    expect(versions.map((v) => v.version), [1, 2]);
  });

  test('intrekken post met sleutel en leest het bijgewerkte stuk', () async {
    transport.responses.add(
      _json({
        'id': 'ei-1',
        'participant_id': 'p1',
        'evidence_type_id': 'type-1',
        'evidence_type_version_id': 'tv-1',
        'content_status': 'ingetrokken',
        'created_at': '2026-09-01T10:00:00Z',
      }),
    );

    final item = await gateway.withdrawEvidenceItem(
      accessToken: 'access',
      organizationId: 'org',
      participantId: 'p1',
      evidenceItemId: 'ei-1',
      idempotencyKey: 'wd-1',
    );

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.path,
      '/api/v1/organizations/org/participants/p1/evidence-items/ei-1/withdraw',
    );
    expect(request.headers['idempotency-key'], 'wd-1');
    expect(item.status.name, 'ingetrokken');
  });

  group('publieke verificatielink', () {
    test('haalt zonder token op en markeert de host als extern', () async {
      transport.responses.add(
        _json({
          'id': 'https://badges.example/cred/1',
          'name': 'BHV',
          'issuer': 'https://roc.example',
        }),
      );

      final decoded = await gateway.fetchPortfolioDocument(
        Uri.parse('https://badges.example/cred/1'),
      );

      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.url.host, 'badges.example');
      // Geen eigen token naar een derde — dat zou credentials lekken.
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(transport.lastTrustedInternal, isFalse);
      expect((decoded as Map)['name'], 'BHV');
    });

    test('weigert een niet-HTTPS link voordat hij vertrekt', () async {
      await expectLater(
        gateway.fetchPortfolioDocument(Uri.parse('http://x.example/a')),
        throwsA(isA<OciServeException>()),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('portfolioItemsFromJson', () {
    test('leest een Open Badges 3-credential', () {
      final items = portfolioItemsFromJson({
        'id': 'https://badges.example/cred/1',
        'issuer': {'id': 'https://roc.example'},
        'validFrom': '2026-01-01T00:00:00Z',
        'validUntil': '2028-01-01T00:00:00Z',
        'credentialSubject': {
          'achievement': {'name': 'BHV'},
        },
      });

      expect(items, hasLength(1));
      expect(items.single.title, 'BHV');
      expect(items.single.issuerId, 'https://roc.example');
      expect(items.single.issuedAt, isNotNull);
      expect(items.single.validUntil, isNotNull);
      expect(items.single.rawCredential, isNotNull);
    });

    test('leest een export met een credentials-lijst', () {
      final items = portfolioItemsFromJson({
        'credentials': [
          {'issuer': 'https://roc.example', 'name': 'BHV'},
          {'issuer': 'https://roc.example', 'name': 'EHBO'},
        ],
      });

      expect(items.map((i) => i.title), ['BHV', 'EHBO']);
    });

    test('een object zonder issuer of titel levert niets', () {
      expect(portfolioItemsFromJson({'name': 'geen issuer'}), isEmpty);
      expect(portfolioItemsFromJson('plain text'), isEmpty);
      expect(portfolioItemsFromJson(null), isEmpty);
    });
  });
}
