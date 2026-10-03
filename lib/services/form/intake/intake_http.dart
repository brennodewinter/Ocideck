// De HTTP-laag van het inzendprotocol (docs/design/INTAKE_PROTOCOL.md §2): één verzoek, één
// antwoord, begrensd. Een trait zodat de client te toetsen is zonder netwerk; de echte
// implementatie (`intake_http_io.dart`) pint de socket aan een door NetGuard goedgekeurd adres.
//
// Het adres in een uitnodiging is invoer van buiten — een link uit een appje —, dus er is
// **geen** "vertrouwd intern" zoals bij een opslagserver die de gebruiker zelf instelde: een
// uitnodiging mag nooit een intern adres bereiken.

import 'dart:typed_data';

/// Een antwoord: status, koppen (kleine letters) en de bytes, nooit meer dan gevraagd.
class IntakeHttpResponse {
  const IntakeHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final Uint8List body;
  final Map<String, String> headers;
}

/// Waarom een verzoek niet tot een antwoord leidde. Geen URL, geen body, geen kop: het
/// adres is van de organisator en een inzending is van de invuller.
enum IntakeHttpFailure {
  /// Geweigerd vóór er een socket openging: geen https, een poort die niet mag, een
  /// ongeldige begrenzing.
  requestRefused,

  /// De host is niet op te lossen, of lost op naar een intern adres.
  hostRefused,

  /// Het antwoord was groter dan gevraagd.
  responseTooLarge,

  /// Te traag.
  timeout,

  /// Een verbindingsfout.
  network,

  /// Dit platform doet geen inzendverkeer (het web, tot de webinvuller er is).
  desktopOnly,
}

class IntakeHttpException implements Exception {
  const IntakeHttpException(this.failure);

  final IntakeHttpFailure failure;

  @override
  String toString() => 'IntakeHttpException: ${failure.name}';
}

abstract class IntakeHttp {
  /// Eén verzoek. [body] gaat mee met zijn lengte in `Content-Length` (het protocol eist die
  /// vóór de eerste byte); een antwoord boven [maxResponseBytes] is [IntakeHttpFailure.responseTooLarge].
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers,
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  });
}
