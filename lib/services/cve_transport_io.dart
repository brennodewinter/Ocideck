import 'dart:convert';
import 'dart:async';
import 'dart:typed_data' show BytesBuilder;

import '../utils/net_guard.dart';
import '../utils/pinned_http_client.dart';
import 'cve_transport.dart';

/// The platform transport on dart:io targets (desktop/mobile).
CveTransport createCveTransport() => PinnedCveTransport();

/// SSRF-pinned HTTP GET — the same recipe as the URL-import path
/// (`file_service_import.dart`): reject non-web schemes and blocked hosts,
/// resolve the host and reject internal addresses, pin the socket to the
/// validated address (so a DNS rebind can't reach an internal IP), block
/// redirects, and cap the body. TLS still validates the original hostname.
class PinnedCveTransport implements CveTransport {
  static const transferTimeout = Duration(seconds: 30);
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

    final client = buildPinnedClient(
      pinned,
      connectionTimeout: const Duration(seconds: 12),
    );
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw CveTransportException('status ${response.statusCode}');
      }
      return await readBody(response).timeout(transferTimeout);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> readBody(
    Stream<List<int>> response, {
    int maxBytes = _maxBytes,
    Duration timeout = transferTimeout,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      if (chunk.length > maxBytes - builder.length) {
        throw const CveTransportException('too large');
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }
}
