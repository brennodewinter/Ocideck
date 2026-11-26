import 'ociserve_http.dart';
import 'ociserve_http_io.dart';

OciServeHttpTransport createPublicOciServeHttpTransport() =>
    _PublicPinnedTransport();

class _PublicPinnedTransport
    implements OciServeHttpTransport, OciServeClosableTransport {
  final _scope = OciServeRequestScope();
  @override
  void close() => _scope.cancel();
  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 30),
  }) => _scope.run(
    () => const PinnedOciServeHttpTransport().send(
      method: method,
      url: url,
      trustedInternal: trustedInternal,
      headers: headers,
      body: body,
      maxResponseBytes: maxResponseBytes,
      timeout: timeout,
    ),
  );
}
