import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_log_store.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/webdav_service.dart';

/// One captured inbound request.
class _Req {
  _Req(this.method, this.path, this.ifNoneMatch, this.body);
  final String method;
  final String path;
  final String? ifNoneMatch;
  final Uint8List body;
}

/// A throwaway WebDAV server on loopback. [WebdavService] pins its socket to the
/// resolved address and we mark the server `trustedInternal`, so NetGuard lets
/// the loopback literal through and the store's real HTTP lands here — the same
/// pattern as `webdav_service_coverage_test.dart`, no live Nextcloud needed.
class _FakeWebdav {
  _FakeWebdav._(this._server, this._responder);
  final HttpServer _server;
  final Future<void> Function(HttpRequest) _responder;
  final List<_Req> requests = [];
  int get port => _server.port;

  static Future<_FakeWebdav> start(
    Future<void> Function(HttpRequest) responder,
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
            req.method,
            req.uri.path,
            req.headers.value(HttpHeaders.ifNoneMatchHeader),
            builder.takeBytes(),
          ),
        );
        await fake._responder(req);
        await req.response.close();
      } catch (_) {
        // Expected socket teardown noise; the client-side assertion is what
        // matters.
      }
    });
    return fake;
  }

  Future<void> stop() => _server.close(force: true);
}

const _davRoot = '/remote.php/dav/files/alice';

String _fileResp(String href, int size) =>
    '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
    '<d:resourcetype/><d:getcontentlength>$size</d:getcontentlength>'
    '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';

String _dirResp(String href) =>
    '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
    '<d:resourcetype><d:collection/></d:resourcetype>'
    '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';

String _multistatus(String inner) =>
    '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">$inner</d:multistatus>';

WebdavCollabLogStore _storeFor(int port) {
  final server = WebdavServer(
    baseUrl: 'http://127.0.0.1:$port',
    username: 'alice',
    rootPath: '',
    trustedInternal: true,
  );
  return WebdavCollabLogStore(
    service: WebdavService(server: server, password: 'secret'),
    opsDir: 'ops',
  );
}

void main() {
  group('WebdavCollabLogStore', () {
    test('listSequences parses record filenames and sorts them', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 207;
        req.response.write(
          _multistatus(
            _dirResp('$_davRoot/ops/') +
                _fileResp('$_davRoot/ops/000000000002.json', 40) +
                _fileResp('$_davRoot/ops/000000000001.json', 30) +
                // a stray non-record sibling must be ignored (forward-compat)
                _fileResp('$_davRoot/ops/snapshot.md', 99),
          ),
        );
      });
      addTearDown(fake.stop);

      expect(await _storeFor(fake.port).listSequences(), [1, 2]);
      expect(fake.requests.single.method, 'PROPFIND');
    });

    test(
      'a missing ops directory reads as an empty log, not an error',
      () async {
        final fake = await _FakeWebdav.start((req) async {
          req.response.statusCode = 404;
        });
        addTearDown(fake.stop);

        expect(await _storeFor(fake.port).listSequences(), isEmpty);
      },
    );

    test('read downloads the record at a padded sequence path', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        req.response.write('{"kind":"op"}');
      });
      addTearDown(fake.stop);

      expect(await _storeFor(fake.port).read(1), '{"kind":"op"}');
      expect(
        fake.requests.last.path,
        '$_davRoot/ops/000000000001.json',
        reason: 'the sequence number is zero-padded in the path',
      );
      expect(fake.requests.last.method, 'GET');
    });

    test('append writes with If-None-Match:* and reports success', () async {
      final fake = await _FakeWebdav.start((req) async {
        // Both the MKCOL for the parent dir and the conditional PUT succeed.
        req.response.statusCode = 201;
        if (req.method == 'PUT') {
          req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        }
      });
      addTearDown(fake.stop);

      expect(await _storeFor(fake.port).append(1, '{"x":1}'), isTrue);
      final put = fake.requests.firstWhere((r) => r.method == 'PUT');
      expect(put.ifNoneMatch, '*', reason: 'the append is conditional');
      expect(put.path, '$_davRoot/ops/000000000001.json');
      expect(utf8.decode(put.body), '{"x":1}');
    });

    test('append returns false when the slot is already taken', () async {
      final fake = await _FakeWebdav.start((req) async {
        // MKCOL succeeds; the conditional PUT is refused (412 = slot taken).
        req.response.statusCode = req.method == 'PUT' ? 412 : 201;
      });
      addTearDown(fake.stop);

      expect(await _storeFor(fake.port).append(2, '{"x":2}'), isFalse);
    });

    test('readSnapshot returns null before one is posted (404)', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 404;
      });
      addTearDown(fake.stop);

      expect(await _storeFor(fake.port).readSnapshot(), isNull);
      expect(fake.requests.last.path, '$_davRoot/ops/snapshot.json');
    });

    test('readSnapshot downloads the baseline when present', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        req.response.write('{"version":3,"slides":[]}');
      });
      addTearDown(fake.stop);

      expect(
        await _storeFor(fake.port).readSnapshot(),
        '{"version":3,"slides":[]}',
      );
    });

    test('writeSnapshot puts the baseline unconditionally', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 201;
      });
      addTearDown(fake.stop);

      await _storeFor(fake.port).writeSnapshot('{"version":1}');
      final put = fake.requests.firstWhere((r) => r.method == 'PUT');
      expect(put.path, '$_davRoot/ops/snapshot.json');
      expect(
        put.ifNoneMatch,
        isNull,
        reason: 'the authority owns the snapshot; no conditional guard',
      );
      expect(utf8.decode(put.body), '{"version":1}');
    });

    test('readBeacon returns null before one is posted (404)', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 404;
      });
      addTearDown(fake.stop);

      expect(await _storeFor(fake.port).readBeacon(), isNull);
      expect(fake.requests.last.path, '$_davRoot/ops/beacon.json');
    });

    test('readBeacon downloads the beacon when present', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        req.response.write(
          '{"authority":"a","authorityIsOwner":true,"tick":4}',
        );
      });
      addTearDown(fake.stop);

      expect(
        await _storeFor(fake.port).readBeacon(),
        '{"authority":"a","authorityIsOwner":true,"tick":4}',
      );
    });

    test('writeBeacon puts the beacon unconditionally', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 201;
      });
      addTearDown(fake.stop);

      await _storeFor(fake.port).writeBeacon('{"tick":2}');
      final put = fake.requests.firstWhere((r) => r.method == 'PUT');
      expect(put.path, '$_davRoot/ops/beacon.json');
      expect(
        put.ifNoneMatch,
        isNull,
        reason: 'the beacon is last-write-wins advisory state; no guard',
      );
      expect(utf8.decode(put.body), '{"tick":2}');
    });

    test('listSequences ignores the beacon sibling', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 207;
        req.response.write(
          _multistatus(
            _dirResp('$_davRoot/ops/') +
                _fileResp('$_davRoot/ops/000000000001.json', 30) +
                _fileResp('$_davRoot/ops/beacon.json', 50),
          ),
        );
      });
      addTearDown(fake.stop);

      expect(await _storeFor(fake.port).listSequences(), [1]);
    });

    test('delete issues a DELETE at the padded record path', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 204;
      });
      addTearDown(fake.stop);

      await _storeFor(fake.port).delete(5);
      final del = fake.requests.firstWhere((r) => r.method == 'DELETE');
      expect(
        del.path,
        '$_davRoot/ops/000000000005.json',
        reason:
            'only a numbered record file — never the snapshot, beacon or .md',
      );
    });

    test('delete treats a 404 as success (idempotent)', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 404;
      });
      addTearDown(fake.stop);

      // An already-gone record is not an error.
      await _storeFor(fake.port).delete(7);
    });

    test('delete surfaces a redirect as a failure, not a success', () async {
      final fake = await _FakeWebdav.start((req) async {
        req.response.statusCode = 302;
        req.response.headers.set(HttpHeaders.locationHeader, 'http://evil/');
      });
      addTearDown(fake.stop);

      // A 3xx must never be read as "deleted" — it could redirect the delete.
      expect(
        () => _storeFor(fake.port).delete(9),
        throwsA(isA<WebdavException>()),
      );
    });
  });
}
