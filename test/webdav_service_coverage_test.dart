import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/webdav_service.dart';

/// Een Nextcloud-bron; de host doet er voor het parsen niet toe, alleen het
/// padschema dat eruit volgt.
WebdavServer _srv(String username, String rootPath) => WebdavServer(
  baseUrl: 'https://cloud.example.com',
  username: username,
  rootPath: rootPath,
);

/// One captured inbound request on the fake server.
class _Req {
  _Req({
    required this.method,
    required this.path,
    required this.depth,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final String? depth;
  final String? authorization;
  final Uint8List body;
}

/// A throwaway WebDAV server on loopback. Because [WebdavService] pins its
/// socket to the *resolved* address and we mark the server `trustedInternal`,
/// NetGuard lets the loopback literal through and the real request lands here,
/// so the network methods (list/download/upload/probe) run end-to-end without a
/// live Nextcloud.
class _FakeWebdav {
  _FakeWebdav._(this._server, this._responder);

  final HttpServer _server;
  final Future<void> Function(HttpRequest req) _responder;
  final List<_Req> requests = [];

  int get port => _server.port;

  static Future<_FakeWebdav> start(
    Future<void> Function(HttpRequest req) responder,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeWebdav._(server, responder);
    server.listen((req) async {
      try {
        final builder = BytesBuilder();
        await for (final chunk in req) {
          builder.add(chunk);
        }
        fake.requests.add(
          _Req(
            method: req.method,
            path: req.uri.path,
            depth: req.headers.value('depth'),
            authorization: req.headers.value(HttpHeaders.authorizationHeader),
            body: builder.takeBytes(),
          ),
        );
        await fake._responder(req);
        await req.response.close();
      } catch (_) {
        // The client aborts (e.g. tooLarge) before draining our response; the
        // resulting socket errors are expected — only the client-side assertion
        // matters.
      }
    });
    return fake;
  }

  Future<void> stop() => _server.close(force: true);
}

const _multistatusOpen = '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">';
const _multistatusClose = '</d:multistatus>';

String _resp(String href, {bool collection = false, int? size, String? type}) {
  final rt = collection ? '<d:collection/>' : '';
  final len = size == null
      ? ''
      : '<d:getcontentlength>$size</d:getcontentlength>';
  final ct = type == null ? '' : '<d:getcontenttype>$type</d:getcontenttype>';
  return '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
      '<d:resourcetype>$rt</d:resourcetype>$len$ct'
      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
}

void main() {
  WebdavService svcFor(int port, {String rootPath = ''}) {
    final server = WebdavServer(
      baseUrl: 'http://127.0.0.1:$port',
      username: 'alice',
      rootPath: rootPath,
      trustedInternal: true,
    );
    return WebdavService(server: server, password: 'secret');
  }

  final expectedAuth = 'Basic ${base64Encode(utf8.encode('alice:secret'))}';

  group('probe', () {
    test('sends an authenticated Depth:0 PROPFIND and accepts 207', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 207;
        req.response.write('<ok/>');
      });
      addTearDown(fake.stop);

      await svcFor(fake.port).probe();

      final r = fake.requests.single;
      expect(r.method, 'PROPFIND');
      expect(r.depth, '0');
      expect(r.authorization, expectedAuth);
      // The PROPFIND body is the fixed prop request.
      expect(utf8.decode(r.body), contains('<d:propfind'));
    });

    test('maps 401 to an auth error', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 401;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).probe());
      expect(e, isA<WebdavException>());
      expect((e as WebdavException).kind, WebdavError.auth);
    });

    test('a non-207 success status is a server error', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).probe());
      expect((e as WebdavException).kind, WebdavError.server);
    });

    test('rejects a path outside the root before any request', () async {
      // An unparseable origin makes uriFor return null → config error, no I/O.
      final svc = WebdavService(
        server: const WebdavServer(baseUrl: 'notaurl', username: 'alice'),
        password: 'pw',
      );
      final e = await _catch(svc.probe);
      expect((e as WebdavException).kind, WebdavError.config);
    });
  });

  group('list', () {
    test('parses a Depth:1 multistatus into sorted entries', () async {
      final xml =
          _multistatusOpen +
          _resp('/remote.php/dav/files/alice/', collection: true) +
          _resp('/remote.php/dav/files/alice/deck.ocideck', size: 12) +
          _resp('/remote.php/dav/files/alice/sub/', collection: true) +
          _multistatusClose;
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 207;
        req.response.headers.contentType = ContentType('application', 'xml');
        req.response.write(xml);
      });
      addTearDown(fake.stop);

      final entries = await svcFor(fake.port).list('');

      expect(fake.requests.single.method, 'PROPFIND');
      expect(fake.requests.single.depth, '1');
      // Folder sorts before the file; the collection itself is filtered out.
      expect(entries.map((e) => e.name), ['sub', 'deck.ocideck']);
      expect(entries.first.isCollection, isTrue);
      expect(entries[1].size, 12);
    });

    test('a 500 status surfaces as a server error', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 500;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).list(''));
      expect((e as WebdavException).kind, WebdavError.server);
    });

    test('an unexpected 2xx status is a server error', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
        req.response.write('<ok/>');
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).list(''));
      expect((e as WebdavException).kind, WebdavError.server);
    });

    test('a path escaping the root is refused before any request', () async {
      final svc = svcFor(1, rootPath: '/Presentaties');
      final e = await _catch(() => svc.list('../escape'));
      expect((e as WebdavException).kind, WebdavError.config);
    });

    test('a refused connection maps to a network error', () async {
      // Bind then immediately release the port so the connect is refused.
      final fake = await _FakeWebdav.start((_) async {});
      final port = fake.port;
      await fake.stop();

      final e = await _catch(() => svcFor(port).list(''));
      expect((e as WebdavException).kind, WebdavError.network);
    });
  });

  group('download', () {
    test('returns the body bytes on 200', () async {
      final payload = Uint8List.fromList(List.generate(64, (i) => i));
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentLength = payload.length;
        req.response.add(payload);
      });
      addTearDown(fake.stop);

      final bytes = await svcFor(fake.port).download('deck.ocideck');
      expect(bytes, payload);
      expect(fake.requests.single.method, 'GET');
      expect(fake.requests.single.path, endsWith('/deck.ocideck'));
    });

    test('rejects when the Content-Length header exceeds the cap', () async {
      final payload = Uint8List.fromList(List.filled(100, 7));
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentLength = payload.length;
        req.response.add(payload);
      });
      addTearDown(fake.stop);

      final e = await _catch(
        () => svcFor(fake.port).download('big.bin', maxBytes: 50),
      );
      expect((e as WebdavException).kind, WebdavError.tooLarge);
    });

    test('rejects when the streamed body exceeds the cap', () async {
      // No Content-Length set → chunked → the header check passes and the
      // streamed accumulation trips the cap instead.
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
        req.response.add(Uint8List.fromList(List.filled(40, 1)));
      });
      addTearDown(fake.stop);

      final e = await _catch(
        () => svcFor(fake.port).download('big.bin', maxBytes: 4),
      );
      expect((e as WebdavException).kind, WebdavError.tooLarge);
    });

    test('a 404 maps to notFound', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 404;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).download('gone.bin'));
      expect((e as WebdavException).kind, WebdavError.notFound);
    });

    test('an unexpected 2xx status is a server error', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 204;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).download('x.bin'));
      expect((e as WebdavException).kind, WebdavError.server);
    });

    test('a path outside the root is refused before any request', () async {
      final svc = svcFor(1, rootPath: '/root');
      final e = await _catch(() => svc.download('../../etc/passwd'));
      expect((e as WebdavException).kind, WebdavError.config);
    });
  });

  group('upload', () {
    test('creates missing parents then PUTs the bytes', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = req.method == 'PUT' ? 201 : 201;
      });
      addTearDown(fake.stop);

      final payload = [1, 2, 3, 4];
      await svcFor(fake.port).upload('a/b/file.bin', payload);

      final methods = fake.requests.map((r) => r.method).toList();
      // Two MKCOLs (for a/ and a/b/) precede the PUT.
      expect(methods, ['MKCOL', 'MKCOL', 'PUT']);
      final put = fake.requests.last;
      expect(put.path, endsWith('/a/b/file.bin'));
      expect(put.body, payload);
    });

    test('a root-level file skips MKCOL entirely', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
      });
      addTearDown(fake.stop);

      await svcFor(fake.port).upload('file.bin', [9]);
      expect(fake.requests.map((r) => r.method), ['PUT']);
    });

    test('an existing parent (405) is tolerated', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = req.method == 'MKCOL' ? 405 : 201;
      });
      addTearDown(fake.stop);

      // Must not throw: 405 means "collection already exists".
      await svcFor(fake.port).upload('a/file.bin', [1]);
      expect(fake.requests.map((r) => r.method), ['MKCOL', 'PUT']);
    });

    test('MKCOL 403 is an auth error', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 403;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).upload('a/file.bin', [1]));
      expect((e as WebdavException).kind, WebdavError.auth);
    });

    test('MKCOL 500 is a server error', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 500;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).upload('a/file.bin', [1]));
      expect((e as WebdavException).kind, WebdavError.server);
    });

    test('an unexpected PUT status is a server error', () async {
      final fake = await _FakeWebdav.start((req) async {
        // Not caught by _checkStatus (not 401/403/404/5xx), but not a success
        // status either → the explicit "Upload gaf status" branch.
        req.response.statusCode = 302;
      });
      addTearDown(fake.stop);

      final e = await _catch(() => svcFor(fake.port).upload('file.bin', [1]));
      expect((e as WebdavException).kind, WebdavError.server);
    });

    test('a path outside the root is refused before any request', () async {
      final svc = svcFor(1, rootPath: '/root');
      final e = await _catch(() => svc.upload('../evil.bin', [1]));
      expect((e as WebdavException).kind, WebdavError.config);
    });
  });

  group('_client SSRF gate', () {
    test('a private literal host is blocked when not trusted', () async {
      final svc = WebdavService(
        server: const WebdavServer(
          baseUrl: 'https://192.168.1.50',
          username: 'alice',
          // trustedInternal defaults to false
        ),
        password: 'pw',
      );
      final e = await _catch(svc.probe);
      expect((e as WebdavException).kind, WebdavError.blockedHost);
    });
  });

  group('parseMultistatus extra coverage', () {
    test('captures a content type and ignores the root href', () {
      final xml =
          _multistatusOpen +
          _resp('/remote.php/dav/files/alice/') + // the root itself → dropped
          _resp(
            '/remote.php/dav/files/alice/pic.png',
            size: 3,
            type: 'image/png',
          ) +
          _multistatusClose;
      final entries = WebdavService.parseMultistatus(
        xml,
        server: _srv('alice', ''),
      );
      expect(entries.single.name, 'pic.png');
      expect(entries.single.contentType, 'image/png');
      expect(entries.single.isImage, isTrue);
    });

    test('caps the number of entries at maxListingEntries', () {
      final buf = StringBuffer(_multistatusOpen);
      for (var i = 0; i < WebdavService.maxListingEntries + 25; i++) {
        buf.write(_resp('/remote.php/dav/files/alice/f$i.md'));
      }
      buf.write(_multistatusClose);
      final entries = WebdavService.parseMultistatus(
        buf.toString(),
        server: _srv('alice', ''),
      );
      expect(entries.length, WebdavService.maxListingEntries);
    });
  });

  group('WebdavException / WebdavEntry', () {
    test('toString names the kind and message', () {
      final e = WebdavException(WebdavError.notFound, 'weg');
      expect(e.toString(), contains('notFound'));
      expect(e.toString(), contains('weg'));
    });

    test('entry classification helpers', () {
      const zip = WebdavEntry(
        name: 'Deck.ZIP',
        relativePath: 'Deck.ZIP',
        isCollection: false,
      );
      expect(zip.isOcideck, isTrue);
      expect(zip.lowerName, 'deck.zip');

      const svg = WebdavEntry(
        name: 'logo.SVG',
        relativePath: 'logo.SVG',
        isCollection: false,
      );
      expect(svg.isImage, isTrue);
      expect(svg.isMarkdown, isFalse);
    });
  });
}

/// Runs [action] and returns whatever it throws, or null when it completes.
Future<Object?> _catch(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (e) {
    return e;
  }
}
