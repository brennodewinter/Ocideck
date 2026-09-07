import 'dart:async';
import 'dart:typed_data';

import '../../utils/net_guard.dart';
import '../../utils/pinned_http_client.dart';
import '../../utils/log.dart';
import 'ociserve_http.dart';

OciServeHttpTransport createOciServeHttpTransport() =>
    const PinnedOciServeHttpTransport();

class PinnedOciServeHttpTransport implements OciServeHttpTransport {
  const PinnedOciServeHttpTransport();

  static const int absoluteMaxResponseBytes = 100 * 1024 * 1024;

  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (url.scheme.toLowerCase() != 'https' ||
        maxResponseBytes <= 0 ||
        maxResponseBytes > absoluteMaxResponseBytes) {
      throw const OciServeTransportException('request_refused');
    }
    final addresses = await NetGuard.safeResolveTrusted(
      url.host,
      allowPrivate: trustedInternal,
    );
    if (addresses == null || addresses.isEmpty) {
      throw const OciServeTransportException('host_refused');
    }
    final client = buildPinnedClient(addresses.first);
    try {
      final request = await client.openUrl(method, url).timeout(timeout);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.add(body);
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) {
          throw const OciServeTransportException('response_too_large');
        }
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });
      return OciServeHttpResponse(
        statusCode: response.statusCode,
        body: builder.takeBytes(),
        headers: responseHeaders,
      );
    } on OciServeTransportException {
      rethrow;
    } on TimeoutException {
      throw const OciServeTransportException('timeout');
    } catch (error, stack) {
      logError('OciServe: netwerkverzoek', error.runtimeType, stack);
      throw const OciServeTransportException('network');
    } finally {
      client.close(force: true);
    }
  }
}
