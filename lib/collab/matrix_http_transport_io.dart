// The production Matrix egress on dart:io targets (desktop)
// (`docs/design/SELF_ENCRYPTED_RELAY.md` §11, phase P-D). Same SSRF recipe as
// `webdav_service.dart`, the URL import and `git_transport_io.dart`: require https
// (a bearer token travels on every request, so it must not go in cleartext),
// resolve the homeserver host and refuse internal addresses, pin the socket to the
// validated address (so a DNS rebind cannot land on an internal IP), block
// redirects (a 3xx must not bypass the host check), and cap the response body.
//
// The pin is laid once and reused: the homeserver is fixed in the [MatrixServer],
// so re-resolving per request would only be a second chance to end up elsewhere.
// This is the only place in the collaboration layer that opens a raw `HttpClient`;
// it is listed in `network_sink_guard_test.dart`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import '../models/matrix_settings.dart';
import '../services/net/transport_failure.dart';
import '../utils/net_guard.dart';
import '../utils/pinned_http_client.dart';
import 'matrix_client.dart';

/// The platform transport on dart:io targets.
MatrixHttpTransport createMatrixHttpTransport(MatrixServer server) =>
    PinnedMatrixHttpTransport(server);

/// SSRF-pinned HTTP to a single homeserver origin. Reused across every CS-API
/// request of one session.
class PinnedMatrixHttpTransport implements MatrixHttpTransport {
  PinnedMatrixHttpTransport(this.server);

  final MatrixServer server;

  /// Cap on the response body a hostile/misconfigured homeserver may return.
  static const int maxResponseBytes = 16 * 1024 * 1024;

  HttpClient? _client;

  @override
  Future<MatrixHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final client = await _ensureClient(url);
    try {
      final request = await client.openUrl(method, url);
      request.followRedirects = false; // a 3xx must not bypass the host check
      headers.forEach(request.headers.set);
      if (body != null) request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 40),
      );
      if (response.contentLength > maxResponseBytes) {
        throw const MatrixException(
          MatrixErrorKind.server,
          'homeserver response too large',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) {
          throw const MatrixException(
            MatrixErrorKind.server,
            'homeserver response too large',
          );
        }
      }
      return MatrixHttpResponse(
        response.statusCode,
        utf8.decode(builder.takeBytes(), allowMalformed: true),
      );
    } on MatrixException {
      rethrow;
    } catch (e) {
      // Host omitted from the message: it is user-configured but may be
      // sensitive. A refused certificate is not transient; a dropped connection
      // is — but the caller (a sync loop) simply retries next round either way.
      throw switch (classifyTransportFailure(e)) {
        TransportFailure.tls => const MatrixException(
          MatrixErrorKind.network,
          'homeserver certificate not trusted',
        ),
        TransportFailure.unreachable ||
        TransportFailure.interrupted ||
        TransportFailure.unknown => const MatrixException(
          MatrixErrorKind.network,
          'homeserver unreachable',
        ),
      };
    }
  }

  Future<HttpClient> _ensureClient(Uri url) async {
    final existing = _client;
    if (existing != null) return existing;

    final origin = server.origin;
    // Alleen een bereikbare homeserver-origin is nodig: de whoami-aanroep die
    // hierlangs loopt is juist hóé het device-id na de login binnenkomt, dus we
    // eisen hier geen (sinds #1043 verplicht) device-id via isConfigured.
    if (origin == null) {
      throw const MatrixException(
        MatrixErrorKind.config,
        'homeserver not configured',
      );
    }
    // The request must land on the configured origin, or we would loose a pinned
    // client on a different host.
    if (url.host != origin.host || url.scheme != origin.scheme) {
      throw const MatrixException(
        MatrixErrorKind.config,
        'request falls outside the configured homeserver',
      );
    }
    // The access token rides on every request: over plain http it would go in
    // the clear. `trustedInternal` is about the server, not the wire, so it does
    // not lift this — same stance as the git/WebDAV transports.
    final scheme = origin.scheme.toLowerCase();
    if (!NetGuard.maySendReusableSecret(scheme, host: origin.host)) {
      throw const MatrixException(
        MatrixErrorKind.config,
        'a homeserver must be https: the access token travels on every request',
      );
    }
    final resolved = await NetGuard.resolveConfigured(
      origin.host,
      allowPrivate: server.trustedInternal,
    );
    if (!resolved.isOk) {
      throw switch (resolved.refusal!) {
        HostRefusal.unknownHost => const MatrixException(
          MatrixErrorKind.network,
          'homeserver name not found',
        ),
        HostRefusal.blocked => const MatrixException(
          MatrixErrorKind.network,
          'homeserver host refused',
        ),
      };
    }
    final pinned = resolved.addresses!.first;
    final client = buildPinnedHttpClient(
      pinned,
      pinnedCertSha256: server.pinnedCertSha256,
    );
    _client = client;
    return client;
  }
}
