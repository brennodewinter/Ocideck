import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/git_transport_io.dart';
import 'package:ocideck/services/git/git_transport_web.dart';
// ignore: unused_import — GitResponse is part of the transport contract under test.
import 'package:ocideck/services/git/git_transport.dart';

const _config = GitRepoConfig(
  baseUrl: 'https://git.example.org',
  owner: 'librekat',
  repo: 'decks',
);

Uri _api(String path) => Uri.parse('https://git.example.org/$path');

void main() {
  group('BrowserGitTransport token handling', () {
    test(
      'never routes a credentialed request through the fetch-proxy',
      () async {
        final seen = <Uri>[];
        final client = MockClient((req) async {
          seen.add(req.url);
          // Simulate the browser refusing the direct read (CORS): a transport
          // failure, not an HTTP status.
          throw http.ClientException('CORS', req.url);
        });
        final transport = BrowserGitTransport(_config, client: client);

        await expectLater(
          transport.get(
            _api('api/v1/repos/librekat/decks'),
            headers: const {'Authorization': 'token s3cret'},
            maxBytes: 1024,
          ),
          throwsA(
            isA<GitForgeException>().having(
              (e) => e.kind,
              'kind',
              GitForgeError.network,
            ),
          ),
        );
        // Exactly one attempt: the direct one. The proxy was never tried, so the
        // token never reached it.
        expect(seen, hasLength(1));
        expect(seen.single.path, contains('api/v1/repos'));
        expect(seen.single.toString(), isNot(contains('fetch-proxy')));
      },
    );

    test('points at CORS when a credentialed direct read fails', () async {
      final client = MockClient((req) async {
        throw http.ClientException('CORS', req.url);
      });
      final transport = BrowserGitTransport(_config, client: client);
      try {
        await transport.get(
          _api('api/v1/repos/librekat/decks'),
          headers: const {'Authorization': 'token s3cret'},
          maxBytes: 1024,
        );
        fail('should have thrown');
      } on GitForgeException catch (e) {
        expect(e.message, contains('CORS'));
      }
    });

    test('recognises credential headers case-insensitively', () async {
      final seen = <Uri>[];
      final client = MockClient((req) async {
        seen.add(req.url);
        throw http.ClientException('CORS', req.url);
      });
      final transport = BrowserGitTransport(_config, client: client);
      for (final header in const [
        'authorization',
        'AUTHORIZATION',
        'Private-Token',
        'private-token',
      ]) {
        seen.clear();
        try {
          await transport.get(
            _api('api/v1/repos/librekat/decks'),
            headers: {header: 'secret'},
            maxBytes: 1024,
          );
        } on GitForgeException {
          // Expected: the direct read fails and the proxy is off-limits.
        }
        expect(seen, hasLength(1), reason: header);
      }
    });

    test('falls back to the proxy when there is no credential', () async {
      final seen = <Uri>[];
      final client = MockClient((req) async {
        seen.add(req.url);
        if (req.url.toString().contains('fetch-proxy')) {
          return http.Response('ok', 200);
        }
        throw http.ClientException('CORS', req.url);
      });
      final transport = BrowserGitTransport(_config, client: client);

      final response = await transport.get(
        _api('api/v1/repos/librekat/decks'),
        headers: const {},
        maxBytes: 1024,
      );
      expect(response.status, 200);
      expect(seen, hasLength(2));
      expect(seen.last.toString(), contains('fetch-proxy'));
    });
  });

  group('BrowserGitTransport limits', () {
    test(
      'an http status comes back rather than triggering the proxy',
      () async {
        final seen = <Uri>[];
        final client = MockClient((req) async {
          seen.add(req.url);
          return http.Response('nope', 404);
        });
        final transport = BrowserGitTransport(_config, client: client);

        final response = await transport.get(
          _api('api/v1/repos/librekat/decks'),
          headers: const {},
          maxBytes: 1024,
        );
        // The server answered: it was reachable, so the proxy adds nothing.
        expect(response.status, 404);
        expect(seen, hasLength(1));
      },
    );

    test('enforces the byte cap', () async {
      final client = MockClient(
        (req) async => http.Response.bytes(Uint8List(4096), 200),
      );
      final transport = BrowserGitTransport(_config, client: client);
      await expectLater(
        transport.get(_api('blob'), headers: const {}, maxBytes: 1024),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.tooLarge,
          ),
        ),
      );
    });

    test('refuses http unless the server is trusted-internal', () async {
      final client = MockClient((req) async => http.Response('ok', 200));
      const plain = GitRepoConfig(
        baseUrl: 'http://git.internal',
        owner: 'o',
        repo: 'r',
      );
      await expectLater(
        BrowserGitTransport(plain, client: client).get(
          Uri.parse('http://git.internal/x'),
          headers: const {},
          maxBytes: 8,
        ),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.config,
          ),
        ),
      );

      final ok = await BrowserGitTransport(
        plain.copyWith(trustedInternal: true),
        client: client,
      ).get(Uri.parse('http://git.internal/x'), headers: const {}, maxBytes: 8);
      expect(ok.status, 200);
    });

    test('refuses an unconfigured repo before touching the network', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('ok', 200);
      });
      await expectLater(
        BrowserGitTransport(
          const GitRepoConfig(baseUrl: '', owner: '', repo: ''),
          client: client,
        ).get(_api('x'), headers: const {}, maxBytes: 8),
        throwsA(isA<GitForgeException>()),
      );
      expect(called, isFalse);
    });
  });

  group('PinnedGitTransport guards (before any DNS)', () {
    test('refuses an unconfigured repo', () async {
      await expectLater(
        PinnedGitTransport(
          const GitRepoConfig(baseUrl: '', owner: '', repo: ''),
        ).get(_api('x'), headers: const {}, maxBytes: 8),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.config,
          ),
        ),
      );
    });

    test(
      'refuses http unless trusted-internal, so the token stays encrypted',
      () async {
        await expectLater(
          PinnedGitTransport(
            const GitRepoConfig(
              baseUrl: 'http://git.internal',
              owner: 'o',
              repo: 'r',
            ),
          ).get(
            Uri.parse('http://git.internal/x'),
            headers: const {},
            maxBytes: 8,
          ),
          throwsA(
            isA<GitForgeException>()
                .having((e) => e.kind, 'kind', GitForgeError.config)
                .having((e) => e.message, 'message', contains('token')),
          ),
        );
      },
    );

    test('refuses a uri that leaves the configured origin', () async {
      // A pinned client must never be pointed at another host: that is what the
      // pin is for.
      await expectLater(
        PinnedGitTransport(_config).get(
          Uri.parse('https://elders.example/x'),
          headers: const {},
          maxBytes: 8,
        ),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.config,
          ),
        ),
      );
    });

    test('refuses an unparseable base url', () async {
      await expectLater(
        PinnedGitTransport(
          const GitRepoConfig(baseUrl: 'not a url', owner: 'o', repo: 'r'),
        ).get(_api('x'), headers: const {}, maxBytes: 8),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.config,
          ),
        ),
      );
    });
  });
}
