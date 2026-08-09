// Part of the file_service library — see file_service.dart.
// Split out for navigability (web-fetch); alle imports leven in het
// hoofdbestand. De desktop-URL-import (dart:io, met SSRF-pinning uit
// [NetGuard]) leeft in parts/file_service_import.dart.
part of '../file_service.dart';

/// Browser-fetch van de webversie, met terugval op het same-origin
/// fetch-hulppunt (server/fetch-proxy).
extension FileServiceNet on FileService {
  /// Haal ruwe bytes op van [url] voor de web-URL-import, mét de reden waarom het
  /// niet lukte. Op web bewaken de browser (CORS, mixed content) en de
  /// pagina-CSP (`connect-src`) welke hosts bereikbaar zijn — de dart:io
  /// SSRF-pinning van [importFromUrl] bestaat daar niet en kan er ook niet
  /// draaien. Hier begrenzen we schema en omvang.
  ///
  /// De reden is er zodat de schil niet elke mislukking op CORS gooit: een te
  /// groot deck of een 404 van een server die de lezing wél toestond is een echt
  /// antwoord, geen CORS-probleem. Een ondoorzichtige browserweigering (het
  /// gewone geval bij een bron zonder CORS-headers) blijft [ImportFailure.network]
  /// — dán klopt de CORS-uitleg. `bytes` is null zodra `failure` gezet is.
  Future<({Uint8List? bytes, ImportFailure? failure})> fetchUrlBytes(
    String url, {
    int maxBytes = FileService.maxDeckMarkdownBytes,
    ProxyFallbackConfirm? onConfirmProxy,
    @visibleForTesting http.Client? client,
    @visibleForTesting bool? viaProxyFallback,
    @visibleForTesting bool closeInjectedClient = false,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      return (bytes: null, failure: ImportFailure.network);
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return (bytes: null, failure: ImportFailure.insecureScheme);
    }
    // Een zelf-gemaakte client sluiten we; een geïnjecteerde (test) client
    // niet — tenzij de test de owned-close-race expliciet wil reproduceren.
    final owned = client == null || closeInjectedClient;
    final c = client ?? http.Client();
    try {
      final direct = await _fetchCapped(c, uri, maxBytes);
      if (direct.bytes != null) return direct;
      // Een 404 of een te groot deck van een server die de lezing wél toestond is
      // een écht antwoord: dat melden we meteen, niet met een CORS-omweg via het
      // hulppunt (dat zou hetzelfde antwoord geven, alleen trager en met de
      // verkeerde uitleg).
      if (direct.failure == ImportFailure.notFound ||
          direct.failure == ImportFailure.tooLarge) {
        return direct;
      }
      // Web: de meeste bronservers sturen geen CORS-headers, dus de browser
      // weigert de directe lezing. Val terug op het same-origin fetch-hulppunt
      // (server/fetch-proxy) dat met dezelfde SSRF-regels als NetGuard
      // server-zijdig ophaalt. Zonder gedeployd hulppunt faalt dit net zo
      // stil als de directe poging; de melding noemt dan CORS.
      if (viaProxyFallback ?? kIsWeb) {
        if (!await _mayFallBackToProxy(uri, onConfirmProxy)) {
          return (bytes: null, failure: ImportFailure.network);
        }
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
      return direct;
    } finally {
      if (owned) c.close();
    }
  }

  /// Of de terugval op het fetch-hulppunt mag lopen.
  ///
  /// Twee sloten, en het eerste staat vast.
  ///
  /// **Een URL mét inloggegevens gaat er nooit doorheen.** Het hulppunt haalt
  /// server-zijdig op, dus het krijgt alles wat in de URL staat in handen —
  /// inclusief `https://gebruiker:wachtwoord@…`. Dit is hetzelfde slot dat
  /// `GitWebTransport` op zijn token zet; daar heet het `_mayUseProxy`.
  ///
  /// **En anders vraagt hij het.** Zonder die vraag verhuisde de hele URL
  /// automatisch en zonder melding van de bronserver naar de origin die de app
  /// serveert — een derde partij die de gebruiker niet had aangewezen. De URL
  /// zelf kan een gegeven zijn (een deellink met een sleutel erin). Geen
  /// bevestiger geregistreerd betekent geen toestemming: dan valt de terugval
  /// weg en meldt de import gewoon dat het niet lukte.
  Future<bool> _mayFallBackToProxy(
    Uri uri,
    ProxyFallbackConfirm? onConfirmProxy,
  ) async {
    if (uri.userInfo.isNotEmpty) {
      logWarning(
        'FileService.fetchUrlBytes: URL draagt inloggegevens, geen terugval '
        'op het fetch-hulppunt',
      );
      return false;
    }
    if (onConfirmProxy == null) return false;
    return onConfirmProxy(host: uri.host);
  }

  /// Eén begrensde GET: 200-only, harde bytecap. Geeft de bytes, of de reden
  /// waarom niet — een niet-200 status via [_classifyUrlImportStatus] (404 →
  /// notFound), een overschreden cap als [ImportFailure.tooLarge], en elke
  /// gevangen fout (de ondoorzichtige CORS-/netwerkweigering) als
  /// [ImportFailure.network].
  Future<({Uint8List? bytes, ImportFailure? failure})> _fetchCapped(
    http.Client c,
    Uri uri,
    int maxBytes, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await c.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        return (
          bytes: null,
          failure: _classifyUrlImportStatus(response.statusCode),
        );
      }
      final bytes = response.bodyBytes;
      if (bytes.length > maxBytes) {
        return (bytes: null, failure: ImportFailure.tooLarge);
      }
      return (bytes: bytes, failure: null);
    } catch (e) {
      logError('FileService._fetchCapped: download failed', e);
      return (bytes: null, failure: ImportFailure.network);
    }
  }
}
