// The production Matrix egress on web (`docs/design/SELF_ENCRYPTED_RELAY.md` §11,
// phase P-D). The dart:io SSRF-pinning of the desktop variant does not exist here
// and cannot run: the browser sandbox and the page CSP (`connect-src`) govern
// which hosts are reachable. What this guards is scheme (the access token must not
// go over plaintext to a non-loopback host) and response size; redirects are the
// browser's to follow. The client is injectable so tests drive it with no network.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/matrix_settings.dart';
import 'matrix_client.dart';

/// The platform transport on web.
MatrixHttpTransport createMatrixHttpTransport(MatrixServer server) =>
    BrowserMatrixHttpTransport(server);

/// Browser-fetch transport. Pinning is impossible in a browser; the CSP and CORS
/// are the host gate. Bounds scheme (via the lexical loopback/https check the
/// client already applied) and response size.
class BrowserMatrixHttpTransport implements MatrixHttpTransport {
  BrowserMatrixHttpTransport(
    this.server, {
    @visibleForTesting http.Client? client,
  }) : _injected = client;

  final MatrixServer server;
  final http.Client? _injected;
  http.Client? _owned;

  http.Client get _client => _injected ?? (_owned ??= http.Client());

  /// Cap on the response body a hostile/misconfigured homeserver may return.
  static const int maxResponseBytes = 16 * 1024 * 1024;

  @override
  Future<MatrixHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = http.Request(method, url);
    request.followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) request.body = body;
    try {
      final streamed = await _client.send(request);
      final bytes = await streamed.stream.toBytes();
      if (bytes.length > maxResponseBytes) {
        throw const MatrixException(
          MatrixErrorKind.server,
          'homeserver response too large',
        );
      }
      // Decode as UTF-8 directly: `http.Response.body` falls back to latin1 when
      // the response carries no charset, which a Matrix JSON body often does not.
      return MatrixHttpResponse(
        streamed.statusCode,
        utf8.decode(bytes, allowMalformed: true),
      );
    } on MatrixException {
      rethrow;
    } on http.ClientException catch (e) {
      throw MatrixException(
        MatrixErrorKind.network,
        'homeserver unreachable: $e',
      );
    }
  }
}
