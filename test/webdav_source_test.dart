import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/utils/net_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A SecretStore whose writes always fail, to prove the notifier never lets a
/// keychain error escape as an unhandled async exception.
class _ThrowingSecretStore extends SecretStore {
  @override
  Future<void> writeWebdavPassword(String b, String u, String p) async {
    throw Exception('keychain unavailable');
  }
}

void main() {
  group('WebdavServer.uriFor containment', () {
    const server = WebdavServer(
      baseUrl: 'https://cloud.example.com',
      username: 'alice',
      rootPath: '/Presentaties',
    );

    test('builds an encoded DAV url under the user root', () {
      final uri = server.uriFor('deck.ocideck');
      expect(
        uri.toString(),
        'https://cloud.example.com/remote.php/dav/files/alice/Presentaties/deck.ocideck',
      );
    });

    test('percent-encodes spaces and unicode in path segments', () {
      final uri = server.uriFor('sub map/café.md');
      expect(uri!.path, contains('sub%20map'));
      expect(uri.path, contains('caf%C3%A9.md'));
    });

    test('marks collections with a trailing slash', () {
      final uri = server.uriFor('sub', isCollection: true);
      expect(uri.toString().endsWith('/Presentaties/sub/'), isTrue);
    });

    test('rejects parent-traversal that escapes the configured root', () {
      expect(server.uriFor('../secret.md'), isNull);
      expect(server.uriFor('../../etc/passwd'), isNull);
      expect(server.uriFor('sub/../../escape.md'), isNull);
    });

    test('allows traversal that stays within the root', () {
      expect(server.uriFor('a/b/../c.md'), isNotNull);
    });

    test('an empty root scopes to the whole user files', () {
      const root = WebdavServer(
        baseUrl: 'https://cloud.example.com',
        username: 'bob',
      );
      expect(
        root.uriFor('x.ocideck').toString(),
        'https://cloud.example.com/remote.php/dav/files/bob/x.ocideck',
      );
      // Traversal can never climb above the user's own files: leading `..`
      // collapse, so the result stays under /files/bob/ (never another user).
      final escaped = root.uriFor('../../../../etc/passwd');
      expect(escaped, isNotNull);
      expect(escaped!.path, startsWith('/remote.php/dav/files/bob/'));
      expect(escaped.path, isNot(contains('/files/alice')));
    });
  });

  group('WebdavServer.normalizeRoot', () {
    test('adds a leading slash and strips trailing slash', () {
      expect(WebdavServer.normalizeRoot('Presentaties/'), '/Presentaties');
      expect(WebdavServer.normalizeRoot('/a/b/'), '/a/b');
      expect(WebdavServer.normalizeRoot(''), '');
      expect(WebdavServer.normalizeRoot('  '), '');
    });
  });

  group('WebdavService.parseMultistatus', () {
    String body(String inner) =>
        '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">$inner</d:multistatus>';

    String response(String href, {bool collection = false, int? size}) {
      final type = collection ? '<d:collection/>' : '';
      final len = size == null ? '' : '<d:getcontentlength>$size</d:getcontentlength>';
      return '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
          '<d:resourcetype>$type</d:resourcetype>$len'
          '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
    }

    test('filters the collection itself and returns children relative to root', () {
      final xml = body(
        // The directory itself (href equals the listed path) — must be dropped.
        response('/remote.php/dav/files/alice/Presentaties/', collection: true) +
            response(
              '/remote.php/dav/files/alice/Presentaties/sub/',
              collection: true,
            ) +
            response(
              '/remote.php/dav/files/alice/Presentaties/deck.ocideck',
              size: 1234,
            ),
      );
      final entries = WebdavService.parseMultistatus(
        xml,
        username: 'alice',
        rootPath: '/Presentaties',
      );
      expect(entries.length, 2);
      // Directories sort first.
      expect(entries.first.isCollection, isTrue);
      expect(entries.first.relativePath, 'sub');
      final deck = entries[1];
      expect(deck.name, 'deck.ocideck');
      expect(deck.relativePath, 'deck.ocideck');
      expect(deck.isOcideck, isTrue);
      expect(deck.size, 1234);
    });

    test('decodes percent-encoded hrefs', () {
      final xml = body(
        response('/remote.php/dav/files/alice/caf%C3%A9.md'),
      );
      final entries = WebdavService.parseMultistatus(
        xml,
        username: 'alice',
        rootPath: '',
      );
      expect(entries.single.name, 'café.md');
      expect(entries.single.isMarkdown, isTrue);
    });

    test('ignores hrefs outside the configured root', () {
      final xml = body(
        response('/remote.php/dav/files/alice/Other/leak.md') +
            response('/remote.php/dav/files/alice/Presentaties/keep.md'),
      );
      final entries = WebdavService.parseMultistatus(
        xml,
        username: 'alice',
        rootPath: '/Presentaties',
      );
      expect(entries.map((e) => e.name), ['keep.md']);
    });

    test('drops entries whose href contains a parent-traversal segment', () {
      // A hostile server cannot smuggle a `..` path into the listing.
      final xml = body(
        response('/remote.php/dav/files/alice/Presentaties/../escape.md') +
            response('/remote.php/dav/files/alice/Presentaties/ok.md'),
      );
      final entries = WebdavService.parseMultistatus(
        xml,
        username: 'alice',
        rootPath: '/Presentaties',
      );
      expect(entries.map((e) => e.name), ['ok.md']);
    });

    test('throws on malformed xml', () {
      expect(
        () => WebdavService.parseMultistatus(
          '<not-closed',
          username: 'a',
          rootPath: '',
        ),
        throwsA(isA<WebdavException>()),
      );
    });
  });

  group('SecretStore.webdavKey', () {
    test('normalises trailing slashes so one account is one entry', () {
      expect(
        SecretStore.webdavKey('https://c.example.com/', 'alice'),
        SecretStore.webdavKey('https://c.example.com', 'alice'),
      );
    });

    test('different account or server yields a different key', () {
      final a = SecretStore.webdavKey('https://c.example.com', 'alice');
      final b = SecretStore.webdavKey('https://c.example.com', 'bob');
      final c = SecretStore.webdavKey('https://other.example.com', 'alice');
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });

  group('SettingsNotifier WebDAV password', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('a failing keychain write is swallowed and reported, never thrown',
        () async {
      final notifier = SettingsNotifier(secretStore: _ThrowingSecretStore());
      // Must complete normally (return false), not throw.
      await expectLater(
        notifier.setWebdavPassword('https://c.example.com', 'alice', 'pw'),
        completion(isFalse),
      );
    });
  });

  group('NetGuard.safeResolveTrusted', () {
    test('blocks a private literal when not trusted', () async {
      expect(
        await NetGuard.safeResolveTrusted('192.168.1.10', allowPrivate: false),
        isNull,
      );
      expect(
        await NetGuard.safeResolveTrusted('127.0.0.1', allowPrivate: false),
        isNull,
      );
    });

    test('allows a private literal when explicitly trusted', () async {
      final addrs =
          await NetGuard.safeResolveTrusted('192.168.1.10', allowPrivate: true);
      expect(addrs, isNotNull);
      expect(addrs!.single.address, '192.168.1.10');
    });

    test('a public literal resolves regardless of the trust flag', () async {
      final untrusted =
          await NetGuard.safeResolveTrusted('93.184.216.34', allowPrivate: false);
      expect(untrusted, isNotNull);
    });
  });

  group('NetGuard.isAllowedMediaUrlResolved', () {
    test('rejects a non-http(s) scheme', () async {
      expect(
        await NetGuard.isAllowedMediaUrlResolved('ftp://example.com/x.png'),
        isFalse,
      );
      expect(
        await NetGuard.isAllowedMediaUrlResolved('file:///etc/passwd'),
        isFalse,
      );
    });

    test('rejects a loopback / private / link-local literal host', () async {
      expect(
        await NetGuard.isAllowedMediaUrlResolved('http://127.0.0.1/x.png'),
        isFalse,
      );
      expect(
        await NetGuard.isAllowedMediaUrlResolved('http://10.0.0.5/x.png'),
        isFalse,
      );
      // Cloud metadata endpoint — the realistic SSRF target.
      expect(
        await NetGuard.isAllowedMediaUrlResolved(
          'http://169.254.169.254/latest/meta-data/',
        ),
        isFalse,
      );
    });

    test('allows a public literal host (no DNS needed)', () async {
      expect(
        await NetGuard.isAllowedMediaUrlResolved('https://93.184.216.34/a.png'),
        isTrue,
      );
    });
  });
}
