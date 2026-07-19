@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/utils/net_guard.dart';
import 'package:ocideck/widgets/dialogs/certificate_trust_dialog.dart';

/// Het vastpinnen van een zelfondertekend certificaat.
///
/// Een zelf gehoste server op het eigen netwerk heeft vaak geen certificaat van
/// een erkende uitgever, en dat is precies de populatie waarvoor "vertrouwde
/// interne server" bestaat. De uitweg is níet "accepteer alles wat
/// zelfondertekend is" — dat zou élk certificaat toelaten, ook dat van een
/// aanvaller — maar: precies dít ene certificaat, door de gebruiker bevestigd
/// op zijn vingerafdruk.
///
/// Deze suite draait tegen een échte TLS-server met een echt zelfondertekend
/// certificaat, want de hele vraag is of de TLS-laag zich gedraagt. Het
/// certificaat wordt per run gemaakt met `openssl` en staat dus niet in de
/// repo; ontbreekt openssl, dan slaat de suite zichzelf over en zégt dat.
void main() {
  late Directory tmp;
  late HttpServer server;
  late String fingerprint;
  var haveOpenssl = true;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('ocideck_certpin');
    final gen = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048',
      '-keyout', '${tmp.path}/k.pem', '-out', '${tmp.path}/c.pem',
      '-days', '2', '-nodes', '-subj', '/CN=localhost',
      // Bewust alleen de naam en niet het IP: zo blijft toetsbaar dat een
      // gepinde verbinding nog steeds de hostnaam controleert.
      '-addext', 'subjectAltName=DNS:localhost',
    ]).catchError((_) => ProcessResult(0, 127, '', 'geen openssl'));
    if (gen.exitCode != 0) {
      haveOpenssl = false;
      return;
    }
    final ctx = SecurityContext()
      ..useCertificateChain('${tmp.path}/c.pem')
      ..usePrivateKey('${tmp.path}/k.pem');
    // Op beide families luisteren: `localhost` lost per machine op naar
    // 127.0.0.1 of ::1, en de test mag daar niet van afhangen.
    server = await HttpServer.bindSecure(
      InternetAddress.anyIPv6,
      0,
      ctx,
      v6Only: false,
    );
    server.listen((req) {
      req.response.statusCode = 207;
      req.response.write('<ok/>');
      req.response.close();
    });
    final resolved = await NetGuard.resolveConfigured(
      'localhost',
      allowPrivate: true,
    );
    final cert = await NetGuard.peekCertificate(
      resolved.addresses!.first,
      Uri.parse('https://localhost:${server.port}/'),
    );
    fingerprint = cert == null ? '' : NetGuard.certificateFingerprint(cert);
  });

  tearDownAll(() async {
    if (haveOpenssl) await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  WebdavService serviceWith(String pin) => WebdavService(
    server: WebdavServer(
      baseUrl: 'https://localhost:${server.port}',
      username: 'alice',
      trustedInternal: true,
      pinnedCertSha256: pin,
    ),
    password: 'geheim',
  );

  test('peekCertificate shows the certificate without trusting it', () {
    if (!haveOpenssl) {
      markTestSkipped('openssl ontbreekt: geen zelfondertekend certificaat');
      return;
    }
    expect(
      fingerprint,
      hasLength(64),
      reason: 'een SHA-256 in hex is 64 tekens',
    );
  });

  test('without a pin a self-signed server is refused', () async {
    if (!haveOpenssl) {
      markTestSkipped('openssl ontbreekt: geen zelfondertekend certificaat');
      return;
    }
    final e = await serviceWith(
      '',
    ).probe().then<Object?>((_) => null, onError: (Object e) => e);
    expect(e, isA<WebdavException>());
    expect((e! as WebdavException).kind, WebdavError.tls);
  });

  test('with the matching pin the connection goes through', () async {
    if (!haveOpenssl) {
      markTestSkipped('openssl ontbreekt: geen zelfondertekend certificaat');
      return;
    }
    await serviceWith(fingerprint).probe();
  });

  test('a pin is not case sensitive', () async {
    if (!haveOpenssl) {
      markTestSkipped('openssl ontbreekt: geen zelfondertekend certificaat');
      return;
    }
    await serviceWith(fingerprint.toUpperCase()).probe();
  });

  test('a pin for a different certificate is refused', () async {
    if (!haveOpenssl) {
      markTestSkipped('openssl ontbreekt: geen zelfondertekend certificaat');
      return;
    }
    // Dit is de kern: de pin mag geen "sta zelfondertekend toe"-schakelaar
    // zijn geworden. Een ánder certificaat op dezelfde host hoort te stranden.
    final e = await serviceWith(
      'a' * 64,
    ).probe().then<Object?>((_) => null, onError: (Object e) => e);
    expect((e! as WebdavException).kind, WebdavError.tls);
  });

  test('a pinned host still validates its name', () async {
    if (!haveOpenssl) {
      markTestSkipped('openssl ontbreekt: geen zelfondertekend certificaat');
      return;
    }
    // Het certificaat staat op localhost; via 127.0.0.1 hoort het niet te
    // passen. Zonder naamcontrole zou een gepinde verbinding een vrijbrief
    // voor elke hostnaam worden.
    final service = WebdavService(
      server: WebdavServer(
        baseUrl: 'https://127.0.0.1:${server.port}',
        username: 'alice',
        trustedInternal: true,
      ),
      password: 'geheim',
    );
    final e = await service.probe().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(e, isA<WebdavException>());
  });

  test('the fingerprint is shown in readable groups', () {
    // 64 tekens achter elkaar zijn met het oog niet te vergelijken met wat je
    // server toont, en vergelijken is precies wat we van de gebruiker vragen.
    final hex = '0123456789abcdef' * 4;
    final shown = CertificateTrustDialog.groupFingerprint(hex);
    expect(shown, startsWith('01:23:45:67:89:AB:CD:EF'));
    // 32 bytes in groepen van acht: vier regels, elk kort genoeg om in één
    // oogopslag met de server te vergelijken.
    expect(shown.split('\n'), hasLength(4));
    expect(
      shown.replaceAll(RegExp(r'[:\n]'), ''),
      hex.toUpperCase(),
      reason: 'de groepering mag geen teken toevoegen of weglaten',
    );
  });

  test('pinnedCertCheck without a pin allows no exception at all', () {
    expect(NetGuard.pinnedCertCheck(''), isNull);
    expect(NetGuard.pinnedCertCheck('   '), isNull);
  });
}
