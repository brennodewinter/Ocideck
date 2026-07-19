import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/git_transport.dart';
import 'package:ocideck/services/git/gitea_forge.dart';

const _config = GitRepoConfig(
  baseUrl: 'https://git.example.org',
  owner: 'librekat',
  repo: 'decks',
);

/// Records what the adapter asks for and replays a canned answer.
class _FakeTransport implements GitTransport {
  _FakeTransport(this.respond);

  final GitResponse Function(Uri uri) respond;
  final List<Uri> uris = <Uri>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];
  final List<List<int>> bodies = <List<int>>[];
  bool closed = false;

  @override
  Future<GitResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    return respond(uri);
  }

  @override
  Future<GitResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required List<int> body,
    required int maxBytes,
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    bodies.add(body);
    return respond(uri);
  }

  @override
  void close() => closed = true;
}

GitResponse _json(Object? body, [int status = 200]) =>
    GitResponse(status, Uint8List.fromList(utf8.encode(jsonEncode(body))));

GiteaForge _forge(_FakeTransport transport, {String token = 'pat123'}) =>
    GiteaForge(config: _config, token: token, transport: transport);

void main() {
  group('GiteaForge.headSha', () {
    test('reads the commit id off a branch', () async {
      final transport = _FakeTransport(
        (_) => _json({
          'name': 'main',
          'commit': {'id': 'abc123'},
        }),
      );
      expect(await _forge(transport).headSha('main'), 'abc123');
      expect(
        transport.uris.single.path,
        '/api/v1/repos/librekat/decks/branches/main',
      );
    });

    test('fails closed on a branch without a sha', () async {
      final transport = _FakeTransport((_) => _json({'name': 'main'}));
      await expectLater(
        _forge(transport).headSha('main'),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });

    test('fails closed when the body is not json at all', () async {
      final transport = _FakeTransport(
        (_) => GitResponse(200, Uint8List.fromList(utf8.encode('<html>nope'))),
      );
      await expectLater(
        _forge(transport).headSha('main'),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });
  });

  group('GiteaForge auth header', () {
    test('uses gitea token auth, not bearer', () async {
      final transport = _FakeTransport(
        (_) => _json({
          'commit': {'id': 'x'},
        }),
      );
      await _forge(transport).headSha('main');
      expect(transport.headers.single['Authorization'], 'token pat123');
    });

    test('sends no credential at all for a public repo', () async {
      final transport = _FakeTransport(
        (_) => _json({
          'commit': {'id': 'x'},
        }),
      );
      await _forge(transport, token: '  ').headSha('main');
      expect(transport.headers.single.containsKey('Authorization'), isFalse);
    });
  });

  group('GiteaForge.listTree non-recursive', () {
    test('maps a contents listing', () async {
      final transport = _FakeTransport(
        (_) => _json([
          {
            'path': 'decks/kwartaalcijfers/deck.md',
            'sha': 's1',
            'type': 'file',
            'size': 42,
          },
          {'path': 'decks/kwartaalcijfers/img', 'sha': 's2', 'type': 'dir'},
        ]),
      );
      final entries = await _forge(
        transport,
      ).listTree('main', 'decks/kwartaalcijfers');

      expect(entries, hasLength(2));
      expect(entries.first.type, RepoEntryType.file);
      expect(entries.first.name, 'deck.md');
      expect(entries.first.isMarkdown, isTrue);
      expect(entries.first.size, 42);
      expect(entries.last.type, RepoEntryType.dir);
      expect(transport.uris.single.queryParameters['ref'], 'main');
    });

    test('maps a symlink or submodule to other, never to file', () async {
      final transport = _FakeTransport(
        (_) => _json([
          {'path': 'decks/a/link', 'sha': 's', 'type': 'symlink'},
          {'path': 'decks/a/sub', 'sha': 's', 'type': 'submodule'},
        ]),
      );
      final entries = await _forge(transport).listTree('main', 'decks/a');
      expect(entries.map((e) => e.type), everyElement(RepoEntryType.other));
    });

    test('skips an entry whose path escapes the repo', () async {
      final transport = _FakeTransport(
        (_) => _json([
          {'path': '../../etc/passwd', 'sha': 's1', 'type': 'file'},
          {'path': '/absolute', 'sha': 's2', 'type': 'file'},
          {'path': 'decks/a/deck.md', 'sha': 's3', 'type': 'file'},
        ]),
      );
      final entries = await _forge(transport).listTree('main', 'decks/a');
      expect(entries.map((e) => e.path), ['decks/a/deck.md']);
    });

    test('skips an entry missing its path or sha', () async {
      final transport = _FakeTransport(
        (_) => _json([
          {'sha': 's1', 'type': 'file'},
          {'path': 'decks/a/x.md', 'type': 'file'},
          {'path': 'decks/a/ok.md', 'sha': 's3', 'type': 'file'},
        ]),
      );
      final entries = await _forge(transport).listTree('main', 'decks/a');
      expect(entries.map((e) => e.path), ['decks/a/ok.md']);
    });

    test('fails closed when a listing is not a json array', () async {
      final transport = _FakeTransport((_) => _json({'not': 'a list'}));
      await expectLater(
        _forge(transport).listTree('main', 'decks/a'),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });

    test('caps the entry count', () async {
      final transport = _FakeTransport(
        (_) => _json(
          List.generate(
            GiteaForge.maxListingEntries + 1,
            (i) => {'path': 'decks/a/$i.md', 'sha': '$i', 'type': 'file'},
          ),
        ),
      );
      await expectLater(
        _forge(transport).listTree('main', 'decks/a'),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.tooLarge,
          ),
        ),
      );
    });
  });

  group('GiteaForge.listTree recursive', () {
    GitResponse tree(List<Object> entries, {bool truncated = false}) =>
        _json({'truncated': truncated, 'tree': entries});

    test('filters the whole tree down to the requested prefix', () async {
      final transport = _FakeTransport(
        (_) => tree([
          {'path': 'decks/a/deck.md', 'sha': 's1', 'type': 'blob'},
          {'path': 'decks/a/img', 'sha': 's2', 'type': 'tree'},
          {'path': 'decks/b/deck.md', 'sha': 's3', 'type': 'blob'},
          {'path': 'assets/x.png', 'sha': 's4', 'type': 'blob'},
        ]),
      );
      final entries = await _forge(
        transport,
      ).listTree('main', 'decks/a', recursive: true);

      expect(entries.map((e) => e.path), ['decks/a/deck.md', 'decks/a/img']);
      expect(transport.uris.single.queryParameters['recursive'], '1');
    });

    test('an empty path returns the whole tree', () async {
      final transport = _FakeTransport(
        (_) => tree([
          {'path': 'decks/a/deck.md', 'sha': 's1', 'type': 'blob'},
          {'path': 'assets/x.png', 'sha': 's2', 'type': 'blob'},
        ]),
      );
      final entries = await _forge(
        transport,
      ).listTree('main', '', recursive: true);
      expect(entries, hasLength(2));
    });

    test(
      'a prefix never matches a sibling that merely starts the same',
      () async {
        final transport = _FakeTransport(
          (_) => tree([
            {'path': 'decks/ab/deck.md', 'sha': 's1', 'type': 'blob'},
            {'path': 'decks/a/deck.md', 'sha': 's2', 'type': 'blob'},
          ]),
        );
        final entries = await _forge(
          transport,
        ).listTree('main', 'decks/a', recursive: true);
        expect(entries.map((e) => e.path), ['decks/a/deck.md']);
      },
    );

    test('refuses a truncated tree rather than returning half of it', () async {
      final transport = _FakeTransport(
        (_) => tree([
          {'path': 'decks/a/deck.md', 'sha': 's1', 'type': 'blob'},
        ], truncated: true),
      );
      await expectLater(
        _forge(transport).listTree('main', 'decks/a', recursive: true),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.tooLarge,
          ),
        ),
      );
    });
  });

  group('GiteaForge.readBlob', () {
    test('reads raw bytes, not base64 json', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
      final transport = _FakeTransport((_) => GitResponse(200, png));
      final bytes = await _forge(transport).readBlob('main', 'assets/x.png');

      expect(bytes, png);
      expect(
        transport.uris.single.path,
        '/api/v1/repos/librekat/decks/raw/assets/x.png',
      );
      expect(transport.uris.single.queryParameters['ref'], 'main');
    });

    test('refuses a path that escapes the repo', () async {
      final transport = _FakeTransport((_) => GitResponse(200, Uint8List(0)));
      await expectLater(
        _forge(transport).readBlob('main', '../../etc/passwd'),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
      expect(transport.uris, isEmpty);
    });
  });

  group('GiteaForge ref validation', () {
    test('accepts a ref with stray whitespace by trimming it', () async {
      final transport = _FakeTransport(
        (_) => _json({
          'commit': {'id': 'x'},
        }),
      );
      expect(await _forge(transport).headSha('  main  '), 'x');
    });

    test('refuses refs that would alter the url or break git', () async {
      final transport = _FakeTransport((_) => GitResponse(200, Uint8List(0)));
      for (final ref in [
        '',
        '   ',
        '-force',
        'a..b',
        'main?x=1',
        'main#frag',
        'main&y=2',
        'main\u0000',
      ]) {
        await expectLater(
          _forge(transport).headSha(ref),
          throwsA(
            isA<GitForgeException>().having(
              (e) => e.kind,
              'kind',
              GitForgeError.malformed,
            ),
          ),
          reason: ref,
        );
      }
      expect(
        transport.uris,
        isEmpty,
        reason: 'nothing should reach the network',
      );
    });
  });

  group('GiteaForge status mapping', () {
    Future<void> expectKind(int status, GitForgeError kind) async {
      final transport = _FakeTransport((_) => _json({'x': 1}, status));
      await expectLater(
        _forge(transport).headSha('main'),
        throwsA(isA<GitForgeException>().having((e) => e.kind, 'kind', kind)),
        reason: 'status $status',
      );
    }

    test('maps the statuses a forge actually returns', () async {
      await expectKind(401, GitForgeError.auth);
      await expectKind(403, GitForgeError.auth);
      await expectKind(404, GitForgeError.notFound);
      await expectKind(409, GitForgeError.notFound);
      await expectKind(500, GitForgeError.server);
      await expectKind(418, GitForgeError.server);
    });

    test('does not promise the repo is absent on a 404', () async {
      // A forge returns 404 when the token may not see the repo, rather than
      // admitting it exists. The wording must not overstate.
      final transport = _FakeTransport((_) => _json({}, 404));
      try {
        await _forge(transport).headSha('main');
        fail('should have thrown');
      } on GitForgeException catch (e) {
        expect(e.message.toLowerCase(), contains('toegang'));
      }
    });
  });

  group('GiteaForge.probe', () {
    test('reports the default branch, emptiness and push rights', () async {
      final transport = _FakeTransport(
        (_) => _json({
          'default_branch': 'master',
          'empty': false,
          'permissions': {'admin': false, 'push': true, 'pull': true},
        }),
      );
      final probe = await _forge(transport).probe();
      expect(probe.defaultBranch, 'master');
      expect(probe.isEmpty, isFalse);
      expect(probe.canPush, isTrue);
      // De repo zelf, niet een subresource: dit is de goedkoopste aanroep die
      // alle vier de vragen beantwoordt.
      expect(transport.uris.single.path, '/api/v1/repos/librekat/decks');
    });

    test('a read-only token is reported as such', () async {
      final transport = _FakeTransport(
        (_) => _json({
          'default_branch': 'main',
          'permissions': {'push': false},
        }),
      );
      expect((await _forge(transport).probe()).canPush, isFalse);
    });

    test('missing permissions mean unknown, not "no"', () async {
      // "Wij weten het niet" en "je mag het niet" zijn verschillende
      // antwoorden; alleen het tweede mag als waarschuwing langskomen.
      final transport = _FakeTransport(
        (_) => _json({'default_branch': 'main'}),
      );
      expect((await _forge(transport).probe()).canPush, isNull);
    });

    test('an empty repo keeps the configured branch as its answer', () async {
      // Een lege Gitea-repo geeft geen default_branch mee; dan is onze eigen
      // instelling het beste dat we hebben — niet een lege string.
      final transport = _FakeTransport(
        (_) => _json({'empty': true, 'default_branch': ''}),
      );
      final probe = await _forge(transport).probe();
      expect(probe.isEmpty, isTrue);
      expect(probe.defaultBranch, _config.defaultBranch);
    });

    test('a non-JSON answer is malformed, not a crash', () async {
      final transport = _FakeTransport(
        (_) => GitResponse(200, Uint8List.fromList(utf8.encode('<html>'))),
      );
      await expectLater(
        _forge(transport).probe(),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });

    test('a 401 surfaces as an auth failure', () async {
      final transport = _FakeTransport((_) => _json({}, 401));
      await expectLater(
        _forge(transport).probe(),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.auth,
          ),
        ),
      );
    });
  });

  test('close closes the transport', () {
    final transport = _FakeTransport((_) => GitResponse(200, Uint8List(0)));
    _forge(transport).close();
    expect(transport.closed, isTrue);
  });
}
