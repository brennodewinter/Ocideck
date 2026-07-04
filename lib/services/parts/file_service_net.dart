// Part of the file_service library — see file_service.dart.
// Split out for navigability (web-fetch); alle imports leven in het
// hoofdbestand. De desktop-URL-import (dart:io, met SSRF-pinning uit
// [NetGuard]) leeft in parts/file_service_import.dart.
part of '../file_service.dart';

/// Browser-fetch van de webversie, met terugval op het same-origin
/// fetch-hulppunt (server/fetch-proxy).
extension FileServiceNet on FileService {
  /// Haal ruwe bytes op van [url] voor de web-URL-import. Op web bewaken de
  /// browser (CORS, mixed content) en de pagina-CSP (`connect-src`) welke
  /// hosts bereikbaar zijn — de dart:io SSRF-pinning van [importFromUrl]
  /// bestaat daar niet en kan er ook niet draaien. Hier begrenzen we schema
  /// en omvang. Retourneert null bij elke fout, net als [importFromUrl].
  Future<Uint8List?> fetchUrlBytes(
    String url, {
    int maxBytes = FileService.maxDeckMarkdownBytes,
    @visibleForTesting http.Client? client,
    @visibleForTesting bool? viaProxyFallback,
    @visibleForTesting bool closeInjectedClient = false,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    // Een zelf-gemaakte client sluiten we; een geïnjecteerde (test) client
    // niet — tenzij de test de owned-close-race expliciet wil reproduceren.
    final owned = client == null || closeInjectedClient;
    final c = client ?? http.Client();
    try {
      final direct = await _fetchCapped(c, uri, maxBytes);
      if (direct != null) return direct;
      // Web: de meeste bronservers sturen geen CORS-headers, dus de browser
      // weigert de directe lezing. Val terug op het same-origin fetch-hulppunt
      // (server/fetch-proxy) dat met dezelfde SSRF-regels als NetGuard
      // server-zijdig ophaalt. Zonder gedeployd hulppunt faalt dit net zo
      // stil als de directe poging; de melding noemt dan CORS.
      if (viaProxyFallback ?? kIsWeb) {
        final proxied = Uri.base.resolve(
          'fetch-proxy?url=${Uri.encodeComponent(url.trim())}',
        );
        // `await` is essentieel: zonder wacht het finally-blok niet en sluit
        // het de HttpClient terwijl deze fetch nog loopt, waardoor die stil
        // afbreekt en de terugval altijd faalt.
        return await _fetchCapped(
          c,
          proxied,
          maxBytes,
          timeout: const Duration(seconds: 120),
        );
      }
      return null;
    } finally {
      if (owned) c.close();
    }
  }

  /// Eén begrensde GET: 200-only, harde bytecap, elke fout wordt null.
  Future<Uint8List?> _fetchCapped(
    http.Client c,
    Uri uri,
    int maxBytes, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await c.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      if (bytes.length > maxBytes) return null;
      return bytes;
    } catch (e) {
      logError('FileService._fetchCapped: download failed', e);
      return null;
    }
  }
}
