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

/// Sanitized connector failure. It deliberately carries no URL, body or token.
class OciServeException implements Exception {
  const OciServeException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => 'OciServeException: $code';
}
