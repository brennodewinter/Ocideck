import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ociserve_file_contract/ociserve_file_contract.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_public_http_factory.dart';

const id = '12345678-1234-4234-8234-123456789abc';
final secret = base64Url.encode(List.filled(32, 3)).replaceAll('=', '');
String link([String host = 'files.example']) =>
    'https://$host$shareLandingPath#$id.$secret';
Map<String, Object?> entry({String kind = 'file', int size = 3}) => {
  'id': id,
  'name': 'notities.md',
  'kind': kind,
  'size': size,
  'etag': '"v1"',
  'content_type': 'text/markdown',
};
Map<String, Object?> share({String? url}) => {
  'id': id,
  'root_id': id,
  'expires_at': '2099-01-01T00:00:00Z',
  'status': 'active',
  'password_protected': true,
  'revision': 2,
  'link': ?url,
};
OciServeHttpResponse json(Object value, {int status = 200}) =>
    OciServeHttpResponse(
      statusCode: status,
      body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
    );

class Transport implements OciServeHttpTransport, OciServeClosableTransport {
  final responses = <OciServeHttpResponse>[];
  final urls = <Uri>[];
  final headersSent = <Map<String, String>>[];
  final bodies = <List<int>?>[];
  final caps = <int>[];
  bool closed = false;
  Completer<OciServeHttpResponse>? pending;
  @override
  void close() => closed = true;
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
    urls.add(url);
    headersSent.add(headers);
    bodies.add(body);
    caps.add(maxResponseBytes);
    expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
    return pending?.future ?? Future.value(responses.removeAt(0));
  }
}

Matcher code(String value) =>
    isA<OciServeException>().having((e) => e.code, 'code', value);
void main() {
  test('public native transport cancels pending and future requests', () async {
    final transport = createPublicOciServeHttpTransport();
    (transport as OciServeClosableTransport).close();
    await expectLater(
      transport.send(
        method: 'GET',
        url: Uri.parse(
          'https://files.example/api/v1/public/file-shares/invalid',
        ),
        trustedInternal: false,
      ),
      throwsA(
        isA<OciServeTransportException>().having(
          (e) => e.code,
          'code',
          'cancelled',
        ),
      ),
    );
  });

  test(
    'canonical capability links reject ambiguous origins, versions and secret encodings',
    () {
      expect(
        FileShareLink.parse(link()).origin.toString(),
        'https://files.example',
      );
      for (final bad in [
        link().replaceFirst('https:', 'http:'),
        link().replaceFirst('files.example', 'u:p@files.example'),
        link().replaceFirst('/open#', '/open?q=1#'),
        link().replaceFirst('/open#', '/open/v2#'),
        link().replaceFirst(secret, '$secret='),
        link().replaceFirst(id, '../x'),
        '${link()}.extra',
      ]) {
        expect(
          () => FileShareLink.parse(bad),
          throwsFormatException,
          reason: 'malformed share',
        );
      }
      expect(FileShareLink.parse(link()).toString(), isNot(contains(secret)));
    },
  );
  test('expiry uses instants and password validation counts UTF-8 bytes', () {
    final now = DateTime.utc(2026, 11, 26);
    expect(() => validateShareExpiry(now, now), throwsFormatException);
    expect(
      () => validateShareExpiry(now.add(const Duration(days: 91)), now),
      throwsFormatException,
    );
    validateShareExpiry(now.add(const Duration(days: 7)), now);
    validateSharePassword('éééé');
    expect(() => validateSharePassword('x' * 7), throwsFormatException);
    expect(() => validateSharePassword('é' * 129), throwsFormatException);
    expect(
      DateTime.parse('2026-12-01T18:00:00+01:00').toUtc(),
      DateTime.utc(2026, 12, 1, 17),
    );
  });
  test(
    'tenant listing preserves cursor and downloads require the displayed version and size',
    () async {
      final t = Transport();
      final api = OciServeGateway(
        settings: const OciServeSettings(
          enabled: true,
          baseUrl: 'https://files.example',
        ),
        transport: t,
      );
      t.responses.add(
        json({
          'folder': entry(kind: 'directory'),
          'items': [entry()],
          'breadcrumbs': [
            {'id': 'root', 'name': ''},
          ],
          'next_cursor': 'é a&b',
        }),
      );
      final page = await api.files(
        accessToken: 'account-token',
        organizationId: id,
        cursor: 'é a&b',
      );
      expect(t.urls.last.queryParameters['cursor'], 'é a&b');
      expect(t.headersSent.last['authorization'], 'Bearer account-token');
      t.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: Uint8List.fromList([35, 32, 65]),
          headers: {'content-type': 'text/markdown', 'etag': '"v1"'},
        ),
      );
      expect(
        await api.fileContent(
          accessToken: 'account-token',
          organizationId: id,
          entry: page.items.single,
        ),
        [35, 32, 65],
      );
      expect(t.caps.last, maxFileBytes);
      expect(t.headersSent.last['if-match'], '"v1"');
      t.responses.add(
        OciServeHttpResponse(
          statusCode: 200,
          body: Uint8List(2),
          headers: {'content-type': 'text/markdown'},
        ),
      );
      await expectLater(
        api.fileContent(
          accessToken: 'account-token',
          organizationId: id,
          entry: page.items.single,
        ),
        throwsA(code('file_changed')),
      );
      final before = t.urls.length;
      await expectLater(
        api.fileContent(
          accessToken: 't',
          organizationId: id,
          entry: CatalogEntry.fromJson(entry(size: maxFileBytes + 1)),
        ),
        throwsA(code('response_too_large')),
      );
      expect(t.urls, hasLength(before));
    },
  );
  test(
    'create/retry and rotation send one idempotency key, revision and UTC expiry',
    () async {
      final t = Transport();
      final api = OciServeGateway(
        settings: const OciServeSettings(
          enabled: true,
          baseUrl: 'https://files.example',
        ),
        transport: t,
      );
      t.responses.add(json(share(url: link())));
      final result = await api.createFileShare(
        accessToken: 't',
        organizationId: id,
        fileId: id,
        requestKey: 'same-key',
        password: 'canary-password',
      );
      expect(t.headersSent.last['idempotency-key'], 'same-key');
      expect(result.toString(), isNot(contains(secret)));
      expect(t.urls.last.toString(), isNot(contains('canary-password')));
      t.responses.add(json(share(url: link())));
      await api.updateFileShare(
        accessToken: 't',
        organizationId: id,
        share: result,
        rotate: true,
      );
      expect(t.headersSent.last['if-match'], '"2"');
      expect(jsonDecode(utf8.decode(t.bodies.last!)), {'rotate_link': true});
      t.responses.add(json(share(url: link('other.example'))));
      await expectLater(
        api.createFileShare(
          accessToken: 't',
          organizationId: id,
          fileId: id,
          requestKey: 'same-key',
        ),
        throwsA(code('invalid_response')),
      );
    },
  );
  test(
    'public grants are origin scoped and never use the signed-in account protocol',
    () async {
      final t = Transport();
      t.responses.addAll([
        json({'grant': 'canary-grant', 'expires_at': '2099-01-01T00:00:00Z'}),
        json({
          'node': entry(kind: 'directory'),
          'items': [entry()],
        }),
        json({}, status: 404),
      ]);
      final public = OciServePublicFiles(
        FileShareLink.parse(link()),
        transport: t,
      );
      await public.unlock(password: 'canary-password');
      expect(t.headersSent.first['authorization'], isNull);
      final body = jsonDecode(utf8.decode(t.bodies.first!)) as Map;
      expect(body['token'], secret);
      expect(body['password'], 'canary-password');
      expect(body['browser'], false);
      final page = await public.browse();
      expect(t.headersSent.last['authorization'], 'Bearer canary-grant');
      await expectLater(
        public.download(page.items.single),
        throwsA(code('share_unavailable')),
      );
      expect(
        t.urls.every(
          (u) =>
              u.origin == 'https://files.example' &&
              u.path.startsWith('/api/v1/public/file-shares/'),
        ),
        true,
      );
      expect(
        t.urls.every((u) => !u.hasFragment && !u.toString().contains(secret)),
        true,
      );
      public.close();
      expect(t.closed, true);
      await expectLater(public.browse(), throwsA(code('cancelled')));
    },
  );
  test(
    'unlock can retry password and rate-limit without retaining problem details',
    () async {
      final t = Transport()
        ..responses.addAll([
          json({'detail': 'canary-password'}, status: 401),
          json({}, status: 429),
        ]);
      final public = OciServePublicFiles(
        FileShareLink.parse(link()),
        transport: t,
      );
      await expectLater(
        public.unlock(),
        throwsA(code('share_password_required')),
      );
      await expectLater(
        public.unlock(password: 'canary-password'),
        throwsA(code('share_rate_limited')),
      );
    },
  );
  test('closing an in-flight unlock cannot resurrect its grant', () async {
    final t = Transport()..pending = Completer();
    final public = OciServePublicFiles(
      FileShareLink.parse(link()),
      transport: t,
    );
    final future = public.unlock();
    public.close();
    t.pending!.complete(
      json({'grant': 'canary-grant', 'expires_at': '2099-01-01T00:00:00Z'}),
    );
    await expectLater(future, throwsA(code('cancelled')));
    await expectLater(public.browse(), throwsA(code('cancelled')));
  });
  test(
    'provider features and effective tenant permissions drive client actions',
    () {
      final account = OciServeAccount.fromJson({
        'account': {'id': 'a'},
        'provider_features': {
          'passwordless_enrollable': true,
          'passkey_management_url': 'https://id.example/account',
        },
        'memberships': [
          {
            'organization_id': id,
            'organization_name': 'Team',
            'status': 'active',
            'effective_capabilities': ['content:create', 'content:edit'],
          },
        ],
      });
      expect(account.passwordlessEnrollable, true);
      expect(account.passkeyManagementUrl!.host, 'id.example');
      expect(account.memberships.single.canShareFiles, true);
      expect(account.memberships.single.name, 'Team');
      expect(
        OciServeAccount.fromJson({'id': 'old'}).passwordlessEnrollable,
        false,
      );
    },
  );
}
