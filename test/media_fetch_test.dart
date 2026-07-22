@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/utils/media_fetch.dart';
import 'package:ocideck/utils/media_fetch_io.dart' show kMaxRemoteMediaBytes;

/// De gepinde ophaalweg voor een remote dia-afbeelding (audit AEG-04).
///
/// `NetworkImage` zoekt de hostnaam zélf op op het moment van ophalen. Een
/// `NetGuard`-controle ervóór keurde dus een adres dat daarna opnieuw werd
/// opgezocht, en in dat venster kan wie DNS beheerst omvlaggen naar een intern
/// adres. Deze provider haalt de bytes zelf op over een socket die op het
/// gekeurde adres vastzit, zodat er geen tweede naamsopzoeking meer is.
void main() {
  test('een interne host levert geen bytes, ook niet via een omweg', () async {
    // Loopback, RFC1918 en de cloud-metadata-adressen horen allemaal door
    // NetGuard.safeResolve geweigerd te worden vóórdat er ook maar een socket
    // opengaat. De IPv4-in-IPv6-vorm staat er nadrukkelijk bij: dat is de
    // klassieke omweg langs een naïeve adrescontrole.
    for (final url in const [
      'http://127.0.0.1/logo.png',
      'http://[::1]/logo.png',
      'http://169.254.169.254/latest/meta-data/',
      'http://[::ffff:169.254.169.254]/x.png',
      'http://10.0.0.1/x.png',
      'http://192.168.1.1/x.png',
    ]) {
      await expectLater(
        bytesOf(url),
        throwsA(isA<Exception>()),
        reason: '$url had geweigerd moeten worden',
      );
    }
  });

  test('een niet-web schema komt er niet in', () async {
    for (final url in const [
      'file:///etc/passwd',
      'gopher://127.0.0.1:70/',
      'ftp://example.com/x.png',
    ]) {
      await expectLater(bytesOf(url), throwsA(isA<Exception>()));
    }
  });

  test('de bytecap staat los van de decode-cap', () {
    // De decode-cap begrenst wat een afbeelding ná het decoderen aan geheugen
    // kost; deze begrenst wat een host überhaupt de leiding in mag duwen. Zonder
    // die tweede vult een eindeloos zendende server het werkgeheugen vóór de
    // decoder ook maar iets ziet.
    expect(kMaxRemoteMediaBytes, greaterThan(0));
  });

  test('dezelfde URL levert dezelfde cache-identiteit op', () {
    // De provider is de sleutel in Flutters afbeeldingscache. Zou hij niet
    // gelijk zijn aan zichzelf, dan haalde elke frame de afbeelding opnieuw op
    // — over het net, en bij elke render opnieuw door de SSRF-poort.
    expect(
      guardedNetworkImage('https://example.com/a.png'),
      guardedNetworkImage('https://example.com/a.png'),
    );
    expect(
      guardedNetworkImage('https://example.com/a.png'),
      isNot(guardedNetworkImage('https://example.com/b.png')),
    );
  });
}

/// Dwingt het ophalen af zonder de hele afbeeldingspijplijn op te tuigen.
///
/// [CappedImage.loadBytes] ís het ophaalpad; die rechtstreeks aanroepen toetst
/// wat er te toetsen valt en laat de decoder erbuiten. De weigering hoort te
/// vallen vóór er een socket opengaat, dus deze test raakt het netwerk niet.
Future<void> bytesOf(String url) =>
    (guardedNetworkImage(url) as CappedImage).loadBytes();
