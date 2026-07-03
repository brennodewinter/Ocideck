// Part of the file_service library — see file_service.dart.
// Split out for navigability (netwerkpaden: URL-import en web-fetch); alle
// imports leven in het hoofdbestand. Methoden verhuizen ongewijzigd.
part of '../file_service.dart';

/// Netwerkpaden van [FileService]: de desktop-URL-import (dart:io, met
/// SSRF-pinning uit [NetGuard]) en de browser-fetch van de webversie met
/// terugval op het same-origin fetch-hulppunt (server/fetch-proxy).
extension FileServiceNet on FileService {
  /// Download een presentatie vanaf [url]. Een zip-pakket wordt uitgepakt;
  /// platte markdown wordt als losse `.md` opgeslagen. Geeft het pad naar het
  /// markdown-bestand terug. SSRF host/adres-regels leven in [NetGuard] zodat
  /// dit pad en het live remote-media-pad exact dezelfde regels delen.
  Future<String?> importFromUrl(String url, String destParentDir) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    // Only fetch over web schemes, and never reach private/loopback hosts.
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (NetGuard.isBlockedHost(uri.host)) return null;
    // Resolve the hostname up front and reject internal addresses.
    final safeAddrs = await NetGuard.safeResolve(uri.host);
    if (safeAddrs == null) return null;
    final pinned = safeAddrs.first;

    final List<int> bytes;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        // Pin the socket to the validated address so a DNS rebind between the
        // check above and the actual connect can't point us at an internal IP.
        // TLS (for https) still validates against the original hostname.
        ..connectionFactory = (u, proxyHost, proxyPort) =>
            Socket.startConnect(pinned, u.port);
      try {
        final request = await client.getUrl(uri);
        // Don't auto-follow redirects: a 3xx could point at a private host and
        // bypass the SSRF check above.
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 200) return null;
        if (response.contentLength > FileService.maxPackageBytes) return null;
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
          if (builder.length > FileService.maxPackageBytes) {
            return null; // runaway body
          }
        }
        bytes = builder.takeBytes();
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      logError('FileService.importFromUrl: download failed', e);
      return null;
    }

    // Zip-magie → pakket; anders als markdown behandelen.
    if (FileService.looksLikeZipBytes(bytes)) {
      return importPackageBytes(bytes, destParentDir);
    }

    // Platte markdown.
    return importMarkdownBytes(bytes, destParentDir, uri.path);
  }

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
