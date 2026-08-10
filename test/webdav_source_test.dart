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

  @override
  Future<void> writeGitToken(String b, String o, String t) async {
    throw Exception('keychain unavailable');
  }
}

/// Een Nextcloud-bron; de host doet er voor het parsen niet toe, alleen het
/// padschema dat eruit volgt.
WebdavServer _srv(String username, String rootPath) => WebdavServer(
  baseUrl: 'https://cloud.example.com',
  username: username,
  rootPath: rootPath,
);

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

  // Het enige dat een niet-Nextcloud-server anders maakt is waar de DAV-wortel
  // ligt. Alles daaromheen — containment, codering, submap — moet identiek
  // blijven werken, dus dat wordt hier expliciet nagelopen.
  group('WebdavServerKind.generic', () {
    const server = WebdavServer(
      baseUrl: 'https://dav.example.com/dav/bestanden',
      username: 'alice',
      rootPath: '/Presentaties',
      kind: WebdavServerKind.generic,
    );

    test('the path in the base url is the DAV root', () {
      expect(
        server.uriFor('deck.ocideck').toString(),
        'https://dav.example.com/dav/bestanden/Presentaties/deck.ocideck',
      );
    });

    test('the username stays out of the path', () {
      expect(server.uriFor('x.md')!.path, isNot(contains('alice')));
      expect(server.uriFor('x.md')!.path, isNot(contains('remote.php')));
    });

    test('a base url without a path serves DAV from the server root', () {
      const root = WebdavServer(
        baseUrl: 'https://dav.example.com',
        username: 'alice',
        kind: WebdavServerKind.generic,
      );
      expect(root.davPrefix, '');
      expect(root.uriFor('x.md').toString(), 'https://dav.example.com/x.md');
    });

    test('containment is enforced exactly as for Nextcloud', () {
      expect(server.uriFor('../secret.md'), isNull);
      expect(server.uriFor('sub/../../escape.md'), isNull);
      expect(server.uriFor('a/b/../c.md'), isNotNull);
    });

    test('a percent-encoded base path is decoded once, not twice', () {
      const encoded = WebdavServer(
        baseUrl: 'https://dav.example.com/sub%20map',
        username: 'alice',
        kind: WebdavServerKind.generic,
      );
      expect(encoded.davSegments, ['sub map']);
      expect(encoded.uriFor('x.md')!.path, '/sub%20map/x.md');
    });

    test('hrefs are resolved against that same root', () {
      final xml =
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
          '<d:response><d:href>/dav/bestanden/Presentaties/</d:href></d:response>'
          '<d:response><d:href>/dav/bestanden/Presentaties/deck.md</d:href></d:response>'
          '<d:response><d:href>/dav/elders/geheim.md</d:href></d:response>'
          '</d:multistatus>';
      final entries = WebdavService.parseMultistatus(xml, server: server);
      expect(entries.map((e) => e.name), ['deck.md']);
    });
  });

  group('WebdavServer JSON', () {
    test('the server kind survives a round trip', () {
      const server = WebdavServer(
        baseUrl: 'https://dav.example.com/dav',
        username: 'alice',
        kind: WebdavServerKind.generic,
      );
      final back = WebdavServer.fromJson(server.toJson());
      expect(back.kind, WebdavServerKind.generic);
      expect(back.davPrefix, '/dav');
    });

    test('a source stored before the kind existed reads as Nextcloud', () {
      final back = WebdavServer.fromJson({
        'baseUrl': 'https://cloud.example.com',
        'username': 'alice',
        'rootPath': '',
        'trustedInternal': false,
      });
      expect(back.kind, WebdavServerKind.nextcloud);
      expect(back.davPrefix, '/remote.php/dav/files/alice');
    });

    test('an unknown kind falls back instead of breaking the source', () {
      final back = WebdavServer.fromJson({
        'baseUrl': 'https://cloud.example.com',
        'username': 'alice',
        'kind': 'sharepoint',
      });
      expect(back.kind, WebdavServerKind.nextcloud);
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

  group('WebdavServer.readPastedDavUrl', () {
    // De meest gemaakte instelfout: Nextcloud toont in zijn eigen scherm de
    // volledige DAV-URL, en die plakken mensen hier in. Tot nu toe verdween
    // het pad — inclusief een submap die ze er bewust in hadden staan.
    test('reads server, user and subfolder from a current-style DAV url', () {
      final parsed = WebdavServer.readPastedDavUrl(
        'https://cloud.example.com/remote.php/dav/files/jan/Presentaties/',
      );
      expect(parsed, isNotNull);
      expect(parsed!.baseUrl, 'https://cloud.example.com');
      expect(parsed.username, 'jan');
      expect(parsed.rootPath, '/Presentaties');
      expect(parsed.hasSomethingToApply, isTrue);
    });

    test('keeps a nested subfolder whole', () {
      final parsed = WebdavServer.readPastedDavUrl(
        'https://cloud.example.com/remote.php/dav/files/jan/Werk/2026',
      );
      expect(parsed!.rootPath, '/Werk/2026');
    });

    test('handles the DAV root without a subfolder', () {
      final parsed = WebdavServer.readPastedDavUrl(
        'https://cloud.example.com/remote.php/dav/files/jan',
      );
      expect(parsed!.username, 'jan');
      expect(parsed.rootPath, '');
      expect(parsed.hasSomethingToApply, isTrue);
    });

    test('handles the older webdav form, which carries no username', () {
      final parsed = WebdavServer.readPastedDavUrl(
        'https://cloud.example.com/remote.php/webdav/Presentaties',
      );
      expect(parsed!.username, isEmpty);
      expect(parsed.rootPath, '/Presentaties');
    });

    test('keeps a non-default port', () {
      final parsed = WebdavServer.readPastedDavUrl(
        'https://cloud.example.com:8443/remote.php/dav/files/jan',
      );
      expect(parsed!.baseUrl, 'https://cloud.example.com:8443');
    });

    test('accepts a pasted url without a scheme', () {
      // Het URL-veld vult https:// aan; deze herkenning moet dat óók doen,
      // anders werkt de hint niet voor wie het schema wegliet.
      final parsed = WebdavServer.readPastedDavUrl(
        'cloud.example.com/remote.php/dav/files/jan',
      );
      expect(parsed!.baseUrl, 'https://cloud.example.com');
    });

    test('a plain origin is not a paste to correct', () {
      expect(
        WebdavServer.readPastedDavUrl('https://cloud.example.com'),
        isNull,
      );
      expect(WebdavServer.readPastedDavUrl(''), isNull);
      expect(WebdavServer.readPastedDavUrl('   '), isNull);
    });

    test('an unrelated path is left alone', () {
      // Bij servertype "Andere WebDAV-server" is een pad juist bedoeld; alleen
      // de herkenbare Nextcloud-vorm mag een hint opleveren.
      expect(
        WebdavServer.readPastedDavUrl('https://dav.example.com/dav/bestanden'),
        isNull,
      );
      expect(
        WebdavServer.readPastedDavUrl('https://x.example.com/remote.php'),
        isNull,
      );
      expect(
        WebdavServer.readPastedDavUrl('https://x.example.com/remote.php/iets'),
        isNull,
      );
    });

    test('the parsed pieces rebuild the same DAV url', () {
      // De echte eis: wat we voorstellen moet naar hetzelfde bestand wijzen als
      // wat de gebruiker plakte. Anders is de "correctie" een verplaatsing.
      const pasted =
          'https://cloud.example.com/remote.php/dav/files/jan/Presentaties';
      final parsed = WebdavServer.readPastedDavUrl(pasted)!;
      final server = WebdavServer(
        baseUrl: parsed.baseUrl,
        username: parsed.username,
        rootPath: parsed.rootPath,
      );
      expect(server.uriFor('deck.ocideck').toString(), '$pasted/deck.ocideck');
    });
  });

  group('WebdavService.parseMultistatus', () {
    String body(String inner) =>
        '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">$inner</d:multistatus>';

    String response(String href, {bool collection = false, int? size}) {
      final type = collection ? '<d:collection/>' : '';
      final len = size == null
          ? ''
          : '<d:getcontentlength>$size</d:getcontentlength>';
      return '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
          '<d:resourcetype>$type</d:resourcetype>$len'
          '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
    }

    test(
      'filters the collection itself and returns children relative to root',
      () {
        final xml = body(
          // The directory itself (href equals the listed path) — must be dropped.
          response(
                '/remote.php/dav/files/alice/Presentaties/',
                collection: true,
              ) +
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
          server: _srv('alice', '/Presentaties'),
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
      },
    );

    test('decodes percent-encoded hrefs', () {
      final xml = body(response('/remote.php/dav/files/alice/caf%C3%A9.md'));
      final entries = WebdavService.parseMultistatus(
        xml,
        server: _srv('alice', ''),
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
        server: _srv('alice', '/Presentaties'),
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
        server: _srv('alice', '/Presentaties'),
      );
      expect(entries.map((e) => e.name), ['ok.md']);
    });

    test('throws on malformed xml', () {
      expect(
        () => WebdavService.parseMultistatus(
          '<not-closed',
          server: _srv('a', ''),
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

    test(
      'a failing keychain write is swallowed and reported, never thrown',
      () async {
        final notifier = SettingsNotifier(secretStore: _ThrowingSecretStore());
        // Must complete normally (return false), not throw.
        await expectLater(
          notifier.setWebdavPassword('https://c.example.com', 'alice', 'pw'),
          completion(isFalse),
        );
      },
    );

    // De `false` hierboven werd nergens afgewacht: de settings-dialoog sloot
    // alsof er niets aan de hand was en de gebruiker zag het pas terug als een
    // geweigerde verbinding. Het signaal is wat de shell er wél over laat zien.
    test('a failing keychain write emits on the secret-error stream', () async {
      final notifier = SettingsNotifier(secretStore: _ThrowingSecretStore());
      final seen = <int>[];
      final sub = notifier.secretErrors.listen(seen.add);

      expect(
        await notifier.setWebdavPassword('https://c.example.com', 'alice', 'p'),
        isFalse,
      );
      expect(
        await notifier.writeGitToken('https://git.example.com', 'acme', 'tok'),
        isFalse,
      );

      // Een broadcast-stream levert asynchroon: zonder deze tik staat het
      // laatste event nog in de wachtrij en meet je er één te weinig.
      await Future<void>.delayed(Duration.zero);

      // Oplopende volgnummers, zodat een tweede fout niet als "ongewijzigd"
      // wordt samengevouwen door de StreamProvider.
      expect(seen, [1, 2]);
      await sub.cancel();
    });

    test('a successful keychain write stays silent', () async {
      final notifier = SettingsNotifier();
      final seen = <int>[];
      final sub = notifier.secretErrors.listen(seen.add);
      // Lege waarde: wist de entry, raakt de keychain-backend niet aan.
      expect(
        await notifier.setWebdavPassword('https://c.example.com', 'alice', ''),
        isTrue,
      );
      expect(seen, isEmpty);
      await sub.cancel();
    });
  });

  group('WebdavService TLS enforcement', () {
    Future<Object?> errorFrom(WebdavServer server) async {
      final svc = WebdavService(server: server, password: 'pw');
      try {
        await svc.list('');
        return null;
      } catch (e) {
        return e;
      }
    }

    test(
      'rejects plain http when the server is not trusted-internal',
      () async {
        final e = await errorFrom(
          const WebdavServer(
            baseUrl: 'http://cloud.example.com',
            username: 'alice',
          ),
        );
        expect(e, isA<WebdavException>());
        expect((e as WebdavException).kind, WebdavError.insecureScheme);
        expect(e.message.toLowerCase(), contains('wachtwoord'));
      },
    );

    test('rejects a non-http(s) scheme', () async {
      final e = await errorFrom(
        const WebdavServer(
          baseUrl: 'ftp://cloud.example.com',
          username: 'alice',
        ),
      );
      expect(e, isA<WebdavException>());
      expect((e as WebdavException).kind, WebdavError.insecureScheme);
    });

    // Note: the "trusted-internal http is allowed past the TLS gate" case is
    // not unit-tested because exercising it reaches the real network; the gate
    // logic (`scheme == 'http' && trustedInternal`) is covered by reading.
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
      final addrs = await NetGuard.safeResolveTrusted(
        '192.168.1.10',
        allowPrivate: true,
      );
      expect(addrs, isNotNull);
      expect(addrs!.single.address, '192.168.1.10');
    });

    test('a public literal resolves regardless of the trust flag', () async {
      final untrusted = await NetGuard.safeResolveTrusted(
        '93.184.216.34',
        allowPrivate: false,
      );
      expect(untrusted, isNotNull);
    });
  });

  group('NetGuard.resolveConfigured names the reason', () {
    test('a private literal is refused as blocked, not as unknown', () async {
      final result = await NetGuard.resolveConfigured(
        '192.168.1.10',
        allowPrivate: false,
      );
      expect(result.isOk, isFalse);
      expect(result.refusal, HostRefusal.blocked);
    });

    test('a name that cannot be resolved is unknownHost', () async {
      // `.invalid` is bij RFC 2606 gereserveerd om nooit op te lossen, dus dit
      // is dezelfde uitkomst met én zonder netwerk — geen flakiness.
      final result = await NetGuard.resolveConfigured(
        'geen-server.invalid',
        allowPrivate: false,
      );
      expect(result.isOk, isFalse);
      expect(result.refusal, HostRefusal.unknownHost);
    });

    test('the trusted flag does not turn a typo into a blocked host', () async {
      // De kern van de klacht: wie de vink al aan had staan, kreeg tóch het
      // advies om hem aan te zetten. Nu blijft de reden dezelfde.
      final result = await NetGuard.resolveConfigured(
        'geen-server.invalid',
        allowPrivate: true,
      );
      expect(result.refusal, HostRefusal.unknownHost);
    });

    test('a public literal resolves and carries its address', () async {
      final result = await NetGuard.resolveConfigured(
        '93.184.216.34',
        allowPrivate: false,
      );
      expect(result.isOk, isTrue);
      expect(result.addresses!.single.address, '93.184.216.34');
      expect(result.refusal, isNull);
    });

    test('a private literal is allowed when the user trusts it', () async {
      final result = await NetGuard.resolveConfigured(
        '10.0.0.5',
        allowPrivate: true,
      );
      expect(result.isOk, isTrue);
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
