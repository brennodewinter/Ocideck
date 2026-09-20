import 'dart:typed_data';

class OciServeHttpResponse {
  const OciServeHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final Uint8List body;
  final Map<String, String> headers;
}

abstract class OciServeHttpTransport {
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers,
    List<int>? body,
    int maxResponseBytes,
    Duration timeout,
  });
}

class OciServeTransportException implements Exception {
  const OciServeTransportException(this.code);

  final String code;

  @override
  String toString() => 'OciServeTransportException: $code';
}

/// Het toonbare deel van een RFC 7807-probleemantwoord: het `type`-URI, de
/// `detail`-zin en een eventuele `Retry-After`. Bevat bewust alleen de
/// technische, server-gegenereerde tekst — nooit invoer van de gebruiker,
/// dus een vouchercode kan hier nooit in lekken.
class OciServeProblem {
  const OciServeProblem({this.type, this.detail, this.retryAfter});

  final String? type;
  final String? detail;
  final Duration? retryAfter;
}

/// Sanitized connector failure. It deliberately carries no URL, body or token.
class OciServeException implements Exception {
  const OciServeException(this.code, {this.statusCode, this.problem});

  final String code;
  final int? statusCode;

  /// Probleemdetails van de server, als de fout één meestuurde — daarmee kan
  /// de client een weigering in producttaal vertalen zonder HTTP-codes te
  /// tonen.
  final OciServeProblem? problem;

  /// Matcht een planning-weigering (HTTP 409) op een kenmerkend deel van de
  /// vaste Go-fouttekst in `detail` — de server stuurt daar geen stabiele
  /// machinecode, dus dit is bewust een substraat-match.
  bool isPlanningConflict(String detailPart) =>
      statusCode == 409 && (problem?.detail ?? '').contains(detailPart);

  @override
  String toString() => 'OciServeException: $code';
}
