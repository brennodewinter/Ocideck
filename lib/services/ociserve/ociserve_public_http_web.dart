import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'ociserve_http.dart';
import '../../utils/log.dart';

OciServeHttpTransport createPublicOciServeHttpTransport() =>
    _PublicWebTransport();

/// Capability-only fetch. Browser CORS mediation remains mandatory; no proxy,
/// cookies, redirects, referrer or ambient OIDC session can join this request.
class _PublicWebTransport
    implements OciServeHttpTransport, OciServeClosableTransport {
  final _requests = <web.AbortController>{};
  bool _closed = false;
  @override
  void close() {
    _closed = true;
    for (final c in _requests) {
      c.abort();
    }
    _requests.clear();
  }

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
    if (_closed ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !url.path.startsWith('/api/v1/public/file-shares/') ||
        maxResponseBytes <= 0 ||
        maxResponseBytes > 32 * 1024 * 1024) {
      throw const OciServeTransportException('request_refused');
    }
    final abort = web.AbortController();
    _requests.add(abort);
    final timer = Timer(timeout, () => abort.abort());
    try {
      final h = web.Headers();
      headers.forEach((key, value) => h.set(key, value));
      final init = web.RequestInit(
        method: method,
        mode: 'cors',
        credentials: 'omit',
        redirect: 'error',
        referrerPolicy: 'no-referrer',
        cache: 'no-store',
        signal: abort.signal,
        headers: h,
      );
      if (body != null) init.body = Uint8List.fromList(body).toJS;
      final response = await web.window.fetch(url.toString().toJS, init).toDart;
      final bytes = BytesBuilder(copy: false);
      final stream = response.body;
      if (stream != null) {
        final reader = stream.getReader() as web.ReadableStreamDefaultReader;
        try {
          while (true) {
            final next = await reader.read().toDart;
            if (next.done) break;
            final chunk = (next.value as JSUint8Array).toDart;
            if (chunk.length > maxResponseBytes - bytes.length) {
              abort.abort();
              throw const OciServeTransportException('response_too_large');
            }
            bytes.add(chunk);
          }
        } finally {
          reader.releaseLock();
        }
      }
      return OciServeHttpResponse(
        statusCode: response.status,
        body: bytes.takeBytes(),
        headers: {
          for (final key in [
            'content-type',
            'content-length',
            'etag',
            'retry-after',
          ])
            key: ?response.headers.get(key),
        },
      );
    } on OciServeTransportException {
      rethrow;
    } catch (error) {
      logWarning(
        'OciServe: publieke verbinding mislukt (${error.runtimeType})',
      );
      throw OciServeTransportException(
        _closed
            ? 'cancelled'
            : abort.signal.aborted
            ? 'timeout'
            : 'network',
      );
    } finally {
      timer.cancel();
      _requests.remove(abort);
    }
  }
}
