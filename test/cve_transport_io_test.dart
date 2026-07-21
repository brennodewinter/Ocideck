@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/cve_transport.dart';
import 'package:ocideck/services/cve_transport_io.dart';

/// De SSRF-poort vóór de CVE-opzoeking. `network_sink_guard_test` bewijst dat
/// dit bestand een netwerkuitgang *is* en dat de recepten erin staan; hier
/// wordt bewezen dat de poort ook dichtgaat.
///
/// Elk geval hieronder wordt geweigerd vóórdat er een socket opengaat, dus er
/// is geen netwerk voor nodig — en dat is meteen de bewering: een geblokkeerde
/// URI mag geen verbinding kosten om als geblokkeerd te gelden.
void main() {
  final transport = PinnedCveTransport();

  Future<String> reasonFor(String uri) async {
    try {
      await transport.getBody(Uri.parse(uri));
      fail('$uri werd niet geweigerd');
    } on CveTransportException catch (e) {
      return e.reason;
    }
  }

  test('de fabriek levert de gepinde transport op dit platform', () {
    expect(createCveTransport(), isA<PinnedCveTransport>());
  });

  group('schema', () {
    test('alles wat geen http(s) is wordt geweigerd', () async {
      // file: en data: zouden de lokale schijf respectievelijk het geheugen
      // tot "netwerk" maken; ftp/gopher zijn klassieke SSRF-omwegen.
      for (final uri in const [
        'file:///etc/passwd',
        'data:text/plain,hallo',
        'ftp://example.com/x',
        'gopher://example.com/x',
        'HTTPX://example.com/x',
      ]) {
        expect(await reasonFor(uri), 'scheme', reason: uri);
      }
    });

    test('http en https komen voorbij de schemacontrole', () async {
      // Ze stranden op de host, niet op het schema — het bewijs dat de
      // volgorde klopt en dat hoofdletters het schema niet omzeilen.
      expect(await reasonFor('HTTPS://127.0.0.1/x'), 'host');
      expect(await reasonFor('HtTp://127.0.0.1/x'), 'host');
    });
  });

  group('host', () {
    test('loopback, privé en link-local worden geweigerd', () async {
      for (final uri in const [
        'http://localhost/x',
        'http://sub.localhost/x',
        'http://127.0.0.1/x',
        'http://[::1]/x',
        'http://10.1.2.3/x',
        'http://192.168.1.1/x',
        'http://172.16.0.1/x',
        // De metadata-service van elke cloud: het klassieke SSRF-doelwit.
        'http://169.254.169.254/latest/meta-data/',
        // Dezelfde binnenkant, verpakt als IPv6-literal. Dart meldt hiervoor
        // isLoopback == false, dus zonder het uitpakken van de ingebedde IPv4
        // glipt dit erdoor.
        'http://[::ffff:169.254.169.254]/x',
        'http://[::ffff:127.0.0.1]/x',
      ]) {
        expect(await reasonFor(uri), 'host', reason: uri);
      }
    });

    test('een naam die nergens op uitkomt wordt geweigerd', () async {
      // `.invalid` bestaat bij afspraak niet (RFC 2606), dus de opzoeking
      // faalt en er valt niets te pinnen. Weigeren, niet alsnog proberen.
      expect(await reasonFor('https://nergens.invalid/cve'), 'resolve');
    });
  });

  test('een fout draagt zijn reden mee in de tekst', () async {
    // De reden is wat de aanroeper aan de gebruiker toont; een lege of
    // generieke tekst maakt elke melding hetzelfde.
    expect(const CveTransportException('host').toString(), contains('host'));
  });
}
