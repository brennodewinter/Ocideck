import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import '../utils/net_guard.dart';
import 'cve_transport.dart';

/// The platform transport on dart:io targets (desktop/mobile).
CveTransport createCveTransport() => PinnedCveTransport();

/// SSRF-pinned HTTP GET — the same recipe as the URL-import path
/// (`file_service_import.dart`): reject non-web schemes and blocked hosts,
/// resolve the host and reject internal addresses, pin the socket to the
/// validated address (so a DNS rebind can't reach an internal IP), block
/// redirects, and cap the body. TLS still validates the original hostname.
class PinnedCveTransport implements CveTransport {
  static const _maxBytes = 2 * 1024 * 1024; // 2 MB

  @override
  Future<String> getBody(Uri uri) async {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const CveTransportException('scheme');
    }
    if (NetGuard.isBlockedHost(uri.host)) {
      throw const CveTransportException('host');
    }
    final safe = await NetGuard.safeResolve(uri.host);
    if (safe == null || safe.isEmpty) {
      throw const CveTransportException('resolve');
    }
    final pinned = safe.first;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..connectionFactory = (u, _, _) => Socket.startConnect(pinned, u.port);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw CveTransportException('status ${response.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > _maxBytes) {
          throw const CveTransportException('too large');
        }
      }
      return utf8.decode(builder.takeBytes());
    } finally {
      client.close(force: true);
    }
  }
}
