// Echte-sockettest voor de io-configfetch (#2533): een loopback-HttpServer
// levert config.js — NetGuard-resolutie, pinning, redirectweigering, status-
// en bytecap lopen over een echte socket, niet over een fake.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_config.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_config_io.dart';

void main() {
  HttpServer? server;

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  Future<Uri> start(void Function(HttpRequest req) answer) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server!.forEach((req) async {
        answer(req);
        await req.response.close();
      }),
    );
    return Uri.parse('http://127.0.0.1:${server!.port}');
  }

  test('haalt config.js op over een gepinde loopback-socket', () async {
    final base = await start((req) {
      req.response.statusCode = 200;
      req.response.write("var config = { hosts: { domain: 'meet.jitsi' } };");
    });
    final body = await fetchJitsiConfig(
      base.resolve('/config.js'),
      allowPrivate: true,
    );
    expect(parseJitsiConfig(body).domain, 'meet.jitsi');
  });

  test('http buiten letterlijke loopback wordt geweigerd', () {
    expect(
      () => fetchJitsiConfig(
        Uri.parse('http://meet.example/config.js'),
        allowPrivate: true,
      ),
      throwsA(isA<JitsiConfigFetchException>()),
    );
  });

  test('loopback zonder vertrouwd-besluit wordt geweigerd', () async {
    final base = await start((req) {
      req.response.statusCode = 200;
    });
    expect(
      () => fetchJitsiConfig(base.resolve('/config.js'), allowPrivate: false),
      throwsA(isA<JitsiConfigFetchException>()),
    );
  });

  test('een niet-200-antwoord faalt met de status in de reden', () async {
    final base = await start((req) {
      req.response.statusCode = 404;
    });
    expect(
      () => fetchJitsiConfig(base.resolve('/config.js'), allowPrivate: true),
      throwsA(
        isA<JitsiConfigFetchException>().having(
          (e) => e.reason,
          'reason',
          contains('404'),
        ),
      ),
    );
  });

  test('een redirect wordt niet gevolgd maar als status gemeld', () async {
    final base = await start((req) {
      req.response.statusCode = 302;
      req.response.headers.set('location', 'http://evil.example/config.js');
    });
    expect(
      () => fetchJitsiConfig(base.resolve('/config.js'), allowPrivate: true),
      throwsA(
        isA<JitsiConfigFetchException>().having(
          (e) => e.reason,
          'reason',
          contains('302'),
        ),
      ),
    );
  });

  test('een te grote response wordt afgekapt met een eerlijke reden', () async {
    final base = await start((req) {
      req.response.statusCode = 200;
      req.response.write(utf8.decode(List.filled(4096, 120))); // 'x' * 4096
    });
    expect(
      () => fetchJitsiConfig(
        base.resolve('/config.js'),
        allowPrivate: true,
        maxBytes: 1024,
      ),
      throwsA(isA<JitsiConfigFetchException>()),
    );
  });
}
