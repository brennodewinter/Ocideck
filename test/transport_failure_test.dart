import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/net/transport_failure.dart';

void main() {
  group('classifyTransportFailure', () {
    test('een TLS-fout is een TLS-fout, ook in zijn twee ondersoorten', () {
      // TlsException is de bovensoort; de twee die dart:io in de praktijk
      // gooit moeten er allebei onder vallen, anders leest een afgewezen
      // certificaat als "onbekende fout".
      expect(
        classifyTransportFailure(const TlsException('mislukt')),
        TransportFailure.tls,
      );
      expect(
        classifyTransportFailure(const HandshakeException('mislukt')),
        TransportFailure.tls,
      );
      expect(
        classifyTransportFailure(const CertificateException('afgewezen')),
        TransportFailure.tls,
      );
    });

    test('een dichte poort of onbekende host is onbereikbaar', () {
      expect(
        classifyTransportFailure(const SocketException('geen route')),
        TransportFailure.unreachable,
      );
    });

    test('een verbinding die halverwege wegviel staat apart', () {
      // Dart meldt dit als HttpException, niet als SocketException. Juist deze
      // soort is het opnieuw proberen waard, dus hij mag niet met de rest op
      // één hoop.
      expect(
        classifyTransportFailure(
          const HttpException('Connection closed before full header'),
        ),
        TransportFailure.interrupted,
      );
    });

    test('al het andere is onbekend, ook een verlopen wachttijd', () {
      expect(
        classifyTransportFailure(TimeoutException('te lang')),
        TransportFailure.unknown,
      );
      expect(
        classifyTransportFailure(const FormatException('rommel')),
        TransportFailure.unknown,
      );
      // Ook iets dat helemaal geen uitzondering is hoort er netjes uit te
      // komen; de aanroeper vangt met `catch (e)` en die vangt álles.
      expect(
        classifyTransportFailure('een kale string'),
        TransportFailure.unknown,
      );
    });
  });

  group('logTransportFailure', () {
    test('elke soort komt langs zonder te klappen', () {
      // Het logboek zelf toetsen we niet — dat het voor élke soort een tak
      // heeft wél, want een ontbrekende tak zou pas in productie opvallen.
      for (final kind in TransportFailure.values) {
        expect(
          () => logTransportFailure('Toets.methode', kind, 'oorzaak'),
          returnsNormally,
        );
      }
    });
  });
}
