// Tests for the production Matrix egress transports (P-D). The web half is driven
// fully with an injected `MockClient` (no network); the io half's SSRF guard
// branches are exercised by misconfigured servers that fail before any socket
// opens — mirroring `git_transport_test.dart`. The real pinned socket path is
// integration territory, as with every dart:io egress in this codebase.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/collab/matrix_http_transport_io.dart';
import 'package:ocideck/collab/matrix_http_transport_web.dart';
import 'package:ocideck/models/matrix_settings.dart';

void main() {
  const server = MatrixServer(
    homeserverUrl: 'https://hs.example',
    userId: '@a:hs.example',
  );

  group('BrowserMatrixHttpTransport (web)', () {
    test('returns the status and UTF-8 body', () async {
      final client = MockClient((req) async {
        expect(req.followRedirects, isFalse);
        expect(req.headers['x-test'], 'yes');
        // A real homeserver sends UTF-8 bytes; the transport must decode them as
        // UTF-8 (not http's latin1 default), which this asserts via the é.
        return http.Response.bytes(utf8.encode('{"ok":true,"n":"café"}'), 200);
      });
      final transport = BrowserMatrixHttpTransport(server, client: client);
      final res = await transport.send(
        method: 'GET',
        url: Uri.parse('https://hs.example/_matrix/client/v3/sync'),
        headers: {'x-test': 'yes'},
      );
      expect(res.status, 200);
      expect(res.body, '{"ok":true,"n":"café"}');
    });

    test('maps a transport failure to a network error', () async {
      final client = MockClient((req) async {
        throw http.ClientException('boom');
      });
      final transport = BrowserMatrixHttpTransport(server, client: client);
      await expectLater(
        () => transport.send(
          method: 'GET',
          url: Uri.parse('https://hs.example/x'),
        ),
        throwsA(
          isA<MatrixException>().having(
            (e) => e.kind,
            'kind',
            MatrixErrorKind.network,
          ),
        ),
      );
    });
  });

  group('PinnedMatrixHttpTransport (io) — SSRF guard', () {
    Matcher throwsConfig() => throwsA(
      isA<MatrixException>().having(
        (e) => e.kind,
        'kind',
        MatrixErrorKind.config,
      ),
    );

    test('refuses an unconfigured homeserver before any socket', () {
      final t = PinnedMatrixHttpTransport(
        const MatrixServer(homeserverUrl: '', userId: ''),
      );
      expect(
        () => t.send(method: 'GET', url: Uri.parse('https://hs.example/x')),
        throwsConfig(),
      );
    });

    test(
      'refuses a plaintext (non-loopback) homeserver — token would leak',
      () {
        final t = PinnedMatrixHttpTransport(
          const MatrixServer(
            homeserverUrl: 'http://hs.example',
            userId: '@a:hs',
          ),
        );
        expect(
          () => t.send(method: 'GET', url: Uri.parse('http://hs.example/x')),
          throwsConfig(),
        );
      },
    );

    test('refuses a request that falls outside the configured origin', () {
      final t = PinnedMatrixHttpTransport(server);
      expect(
        () => t.send(method: 'GET', url: Uri.parse('https://evil.example/x')),
        throwsConfig(),
      );
    });

    test(
      'sends over a pinned socket to a trusted-internal loopback server',
      () async {
        // A real send exercises the pinned dart:io path: resolve loopback (allowed
        // as trusted-internal), pin, no redirects, read + cap the body.
        final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => http.close(force: true));
        http.listen((req) async {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write('{"user_id":"@a:hs"}');
          await req.response.close();
        });
        final base = 'http://127.0.0.1:${http.port}';
        final t = PinnedMatrixHttpTransport(
          MatrixServer(
            homeserverUrl: base,
            userId: '@a:hs',
            trustedInternal: true,
          ),
        );
        final res = await t.send(
          method: 'GET',
          url: Uri.parse('$base/_matrix/client/v3/account/whoami'),
        );
        expect(res.status, 200);
        expect(res.body, '{"user_id":"@a:hs"}');
      },
    );
  });
}
