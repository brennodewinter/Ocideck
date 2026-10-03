import 'dart:async';
import 'dart:typed_data';

import '../../../utils/log.dart';
import '../../../utils/net_guard.dart';
import '../../../utils/pinned_http_client.dart';
import 'intake_http.dart';

IntakeHttp createIntakeHttp() => const PinnedIntakeHttp();

/// Het echte verkeer: https alleen, de host door [NetGuard.safeResolve] (een naam die naar een
/// intern adres wijst wordt geweigerd), de socket gepind aan dat adres en geen redirects — een
/// 3xx kan de hostcontrole niet omzeilen.
class PinnedIntakeHttp implements IntakeHttp {
  const PinnedIntakeHttp();

  /// Het plafond voor een antwoord: een verzegeld pakket is hooguit 120 MiB (§5.4).
  static const int absoluteMaxResponseBytes = 130 * 1024 * 1024;

  @override
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  }) async {
    if (url.scheme != 'https' ||
        !NetGuard.allowedWebPorts.contains(url.port) ||
        maxResponseBytes <= 0 ||
        maxResponseBytes > absoluteMaxResponseBytes) {
      throw const IntakeHttpException(IntakeHttpFailure.requestRefused);
    }
    // `safeResolve`, niet `safeResolveTrusted`: het adres staat in een uitnodiging en is dus
    // invoer van buiten, geen server die de gebruiker zelf instelde.
    final addresses = await NetGuard.safeResolve(url.host);
    if (addresses == null || addresses.isEmpty) {
      throw const IntakeHttpException(IntakeHttpFailure.hostRefused);
    }
    final client = buildPinnedClient(
      addresses.first,
      connectionTimeout: timeout,
    );
    // Geen User-Agent: de server hoeft niet te weten welk programma en welke versie.
    client.userAgent = null;
    try {
      final request = await client.openUrl(method, url).timeout(timeout);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder();
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) {
          throw const IntakeHttpException(IntakeHttpFailure.responseTooLarge);
        }
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });
      return IntakeHttpResponse(
        statusCode: response.statusCode,
        body: builder.takeBytes(),
        headers: responseHeaders,
      );
    } on IntakeHttpException {
      rethrow;
    } on TimeoutException {
      throw const IntakeHttpException(IntakeHttpFailure.timeout);
    } catch (error, stack) {
      logError('Inzendserver: netwerkverzoek', error.runtimeType, stack);
      throw const IntakeHttpException(IntakeHttpFailure.network);
    } finally {
      client.close(force: true);
    }
  }
}
