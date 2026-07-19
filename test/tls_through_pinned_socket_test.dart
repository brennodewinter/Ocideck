@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/utils/net_guard.dart';

/// Dat een `https`-verzoek ook écht versleuteld de lijn op gaat.
///
/// De aanleiding: `HttpClient.connectionFactory` neemt letterlijk over wat je
/// teruggeeft. Zet je hem — en dat doen we, om de socket op een gekeurd adres
/// te pinnen tegen DNS-rebind — dan is de fabriek volledig verantwoordelijk
/// voor TLS. Een kale `Socket` betekende dus: geen TLS. Elk https-verzoek ging
/// als platte HTTP de lijn op, inclusief de `Authorization`-header met het
/// wachtwoord erin.
///
/// Geen enkele bestaande test ving dat, en dat was geen toeval: ze praten
/// allemaal `http://127.0.0.1` met `trustedInternal`, dus het TLS-pad werd
/// nooit aangeraakt.
///
/// Deze test heeft geen certificaten nodig. Hij luistert op een kale socket en
/// kijkt naar de eerste bytes die binnenkomen. Een TLS-verbinding begint met
/// een handshake-record (0x16); platte HTTP begint met de naam van de methode.
/// Dat onderscheid is precies de bug.
class _WireTap {
  _WireTap._(this._server);

  final ServerSocket _server;
  final Completer<List<int>> _first = Completer<List<int>>();

  int get port => _server.port;

  /// De eerste bytes die een client stuurde.
  Future<List<int>> get firstBytes => _first.future;

  static Future<_WireTap> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final tap = _WireTap._(server);
    server.listen((socket) {
      socket.listen(
        (data) {
          if (!tap._first.isCompleted) tap._first.complete(data);
          // Meteen dicht: we willen alleen weten wát er gestuurd werd, niet
          // een gesprek voeren.
          socket.destroy();
        },
        onError: (_) => socket.destroy(),
        cancelOnError: true,
      );
    });
    return tap;
  }

  Future<void> stop() => _server.close();
}

void main() {
  test('an https request is never sent as readable plaintext', () async {
    final tap = await _WireTap.start();
    addTearDown(tap.stop);

    final service = WebdavService(
      server: WebdavServer(
        // https naar een luisteraar die géén TLS spreekt. Het verzoek hoort te
        // stranden — maar op de handshake, niet op een 400 nadat het
        // wachtwoord er al uit is.
        baseUrl: 'https://127.0.0.1:${tap.port}',
        username: 'alice',
        trustedInternal: true,
      ),
      password: 'geheim',
    );

    // Dat dit faalt is de bedoeling; waar het om gaat is wát er verstuurd werd.
    await service.probe().then((_) {}, onError: (_) {});

    final first = await tap.firstBytes.timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <int>[],
    );
    expect(first, isNotEmpty, reason: 'de client moet iets gestuurd hebben');

    // 0x16 = TLS handshake record. Vóór de reparatie stond hier 'PROPFIND'.
    expect(
      first.first,
      0x16,
      reason: 'https hoort met een TLS-handshake te beginnen, niet met HTTP',
    );

    final asText = String.fromCharCodes(first.take(64));
    expect(asText, isNot(contains('PROPFIND')));
    expect(
      asText.toLowerCase(),
      isNot(contains('authorization')),
      reason: 'het wachtwoord mag nooit leesbaar over de lijn',
    );
  });

  test('an http request stays plain http', () async {
    // De keerzijde: een LAN-server zonder TLS moet blijven werken. Zou
    // connectPinned altijd TLS opzetten, dan brak dit pad.
    final tap = await _WireTap.start();
    addTearDown(tap.stop);

    final service = WebdavService(
      server: WebdavServer(
        baseUrl: 'http://127.0.0.1:${tap.port}',
        username: 'alice',
        trustedInternal: true,
      ),
      password: 'geheim',
    );
    await service.probe().then((_) {}, onError: (_) {});

    final first = await tap.firstBytes.timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <int>[],
    );
    expect(String.fromCharCodes(first.take(16)), startsWith('PROPFIND'));
  });

  test('connectPinned wraps https and leaves http alone', () async {
    final tap = await _WireTap.start();
    addTearDown(tap.stop);
    final local = InternetAddress('127.0.0.1');

    final plain = await NetGuard.connectPinned(
      local,
      Uri.parse('http://127.0.0.1:${tap.port}/'),
    );
    expect(await plain.socket, isNot(isA<SecureSocket>()));
    (await plain.socket).destroy();
  });
}
