import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/services/openkat/openkat_rocky_client.dart';
import 'package:ocideck/services/secret_store.dart';

/// Fake transport: programmeerbaar antwoord, geen netwerk.
class _FakeTransport implements OpenKatHttpTransport {
  _FakeTransport({this.response, this.responses});

  final OpenKatHttpResult? response;
  final List<OpenKatHttpResult>? responses;
  int _i = 0;

  late Uri lastUrl;
  late Map<String, String> lastHeaders;

  @override
  Future<OpenKatHttpResult> get({
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    lastUrl = url;
    lastHeaders = headers;
    if (responses != null) {
      return responses![_i++];
    }
    return response!;
  }
}

OpenKatInstallation _inst({
  String url = 'https://openkat.example',
  bool lan = false,
}) => OpenKatInstallation.create(
  name: 'Test',
  baseUrl: url,
  trustedInternal: lan,
);

void main() {
  group('SecretStore.openKatTokenKey', () {
    test('stabiel per installatie-id', () {
      expect(SecretStore.openKatTokenKey('abc-123'), 'openkat_token::abc-123');
      expect(
        SecretStore.openKatTokenKey('abc-123'),
        isNot(SecretStore.openKatTokenKey('other')),
      );
    });

    test('botst niet met LibrePlan-sleutels', () {
      final openkat = SecretStore.openKatTokenKey('id-1');
      final libreplan = SecretStore.libreplanKey(
        'https://openkat.example',
        'user',
      );
      expect(openkat, isNot(libreplan));
    });
  });

  group('OpenKatRockyClient.canSend', () {
    test('false op web', () {
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: 'tok',
        isWeb: true,
      );
      expect(client.canSend, isFalse);
      expect(client.denialReason, 'desktop_only');
    });

    test('false zonder token', () {
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: '  ',
        isWeb: false,
      );
      expect(client.canSend, isFalse);
      expect(client.denialReason, 'token_missing');
    });

    test('false bij HTTP zonder LAN', () {
      final client = OpenKatRockyClient(
        installation: _inst(url: 'http://openkat.lan'),
        token: 'tok',
        isWeb: false,
      );
      expect(client.canSend, isFalse);
      expect(client.denialReason, 'https_required');
    });

    test('true bij HTTPS', () {
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: 'tok',
        isWeb: false,
      );
      expect(client.canSend, isTrue);
    });
  });

  group('OpenKatRockyClient.listOrganizations', () {
    test('parst lijst en stuurt Knox-header', () async {
      final transport = _FakeTransport(
        response: const OpenKatHttpResult(200, '''
          [{"id":1,"name":"Acme","code":"acme","tags":[]}]
        '''),
      );
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: 'secret-token',
        transport: transport,
        isWeb: false,
      );
      final orgs = await client.listOrganizations();
      expect(orgs, hasLength(1));
      expect(orgs.first.code, 'acme');
      expect(orgs.first.name, 'Acme');
      expect(transport.lastUrl.path, '/api/v1/organization/');
      expect(transport.lastHeaders['authorization'], 'Token secret-token');
    });

    test('401 wordt OpenKatRequestException', () async {
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: 'bad',
        transport: _FakeTransport(
          response: const OpenKatHttpResult(401, '{"detail":"no"}'),
        ),
        isWeb: false,
      );
      expect(
        () => client.listOrganizations(),
        throwsA(
          isA<OpenKatRequestException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('OpenKatRockyClient.listAggregateReports', () {
    test('filtert alleen aggregaat en sorteert op datum', () async {
      final transport = _FakeTransport(
        response: const OpenKatHttpResult(200, '''
          {
            "count": 3,
            "next": null,
            "results": [
              {
                "id": "Report|aaa",
                "name": "Oud",
                "report_type": "aggregate-organisation-report",
                "generated_at": "2026-01-01T00:00:00+00:00",
                "intput_oois": []
              },
              {
                "id": "Report|bbb",
                "name": "Asset",
                "report_type": "concatenated-report",
                "generated_at": "2026-08-01T00:00:00+00:00",
                "intput_oois": []
              },
              {
                "id": "Report|ccc",
                "name": "Nieuw",
                "report_type": "aggregate-organisation-report",
                "generated_at": "2026-08-05T00:00:00+00:00",
                "intput_oois": []
              }
            ]
          }
        '''),
      );
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: 'tok',
        transport: transport,
        isWeb: false,
      );
      final reports = await client.listAggregateReports('acme');
      expect(reports, hasLength(2));
      expect(reports.first.name, 'Nieuw');
      expect(reports.first.pk, 'ccc');
      expect(transport.lastUrl.queryParameters['organization_code'], 'acme');
    });
  });

  group('OpenKatRockyClient.fetchReportJson', () {
    test('404 → null en capability unavailable', () async {
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: 'tok',
        transport: _FakeTransport(response: const OpenKatHttpResult(404, 'no')),
        isWeb: false,
      );
      final body = await client.fetchReportJson(
        reportPk: 'ccc',
        organizationCode: 'acme',
      );
      expect(body, isNull);
      expect(client.jsonCapability, OpenKatJsonCapability.unavailable);
    });

    test('200 JSON → body en capability available', () async {
      const envelope =
          '{"organization_code":"acme","organization_name":"Acme","data":{}}';
      final client = OpenKatRockyClient(
        installation: _inst(),
        token: 'tok',
        transport: _FakeTransport(
          response: const OpenKatHttpResult(200, envelope),
        ),
        isWeb: false,
      );
      final body = await client.fetchReportJson(
        reportPk: 'ccc',
        organizationCode: 'acme',
      );
      expect(body, envelope);
      expect(client.jsonCapability, OpenKatJsonCapability.available);
    });
  });

  group('OpenKatReportRef.pk', () {
    test('stript Report|-prefix', () {
      const ref = OpenKatReportRef(
        id: 'Report|abc-def',
        name: 'x',
        reportType: kOpenKatAggregateReportType,
      );
      expect(ref.pk, 'abc-def');
    });
  });
}
