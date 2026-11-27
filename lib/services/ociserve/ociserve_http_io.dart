import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import '../../utils/net_guard.dart';
import '../../utils/pinned_http_client.dart';
import '../../utils/log.dart';
import 'ociserve_http.dart';

OciServeHttpTransport createOciServeHttpTransport() =>
    const PinnedOciServeHttpTransport();

OciServeHttpTransport createIntakeRespondentTransport(Uri base) =>
    createOciServeHttpTransport();

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
    final scope = OciServeRequestScope.current;
    if (scope?.cancelled == true) {
      throw const OciServeTransportException('cancelled');
    }
    final elapsed = Stopwatch()..start();
    final List<InternetAddress>? addresses;
    try {
      addresses = await NetGuard.safeResolveTrusted(
        url.host,
        allowPrivate: trustedInternal,
      ).timeout(timeout);
    } on TimeoutException {
      throw const OciServeTransportException('timeout');
    }
    if (addresses == null || addresses.isEmpty) {
      throw const OciServeTransportException('host_refused');
    }
    if (scope?.cancelled == true) {
      throw const OciServeTransportException('cancelled');
    }
    final client = buildPinnedClient(addresses.first);
    void abort() => client.close(force: true);
    scope?.add(abort);
    var timedOut = false;
    final remaining = timeout - elapsed.elapsed;
    final timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      timedOut = true;
      abort();
    });
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
      throw OciServeTransportException(
        scope?.cancelled == true
            ? 'cancelled'
            : timedOut
            ? 'timeout'
            : 'network',
      );
    } finally {
      timer.cancel();
      scope?.remove(abort);
      client.close(force: true);
    }
  }
}
