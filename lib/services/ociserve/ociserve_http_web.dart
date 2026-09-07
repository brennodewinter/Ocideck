import 'ociserve_http.dart';

OciServeHttpTransport createOciServeHttpTransport() =>
    const WebRefusingOciServeHttpTransport();

class WebRefusingOciServeHttpTransport implements OciServeHttpTransport {
  const WebRefusingOciServeHttpTransport();

  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 0,
    Duration timeout = Duration.zero,
  }) => throw const OciServeTransportException('desktop_only');
}
