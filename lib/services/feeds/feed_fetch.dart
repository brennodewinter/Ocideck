// Het netwerkpad van de feedroute (#2931): één begrensde GET voor
// feedcontroles en -ophalingen, mét de responsevelden die een
// updatecyclus nodig heeft (status, ETag, Last-Modified, eind-URL) —
// de bytes-only import-API verliest precies die.
//
// Twee netwerkvormen achter één retourtype:
//  * desktop loopt NetGuard-resolve + de gepinde client en volgt 3xx
//    handmatig, hop voor hop opnieuw getoetst — dezelfde regel als de
//    deck-import, maar dan wél volgend omdat feeds routinematig
//    verhuizen;
//  * web gebruikt de browser-fetch (CORS/CSP bewaken de hosts); een
//    conditionele header kan een preflight uitlokken — dat is dan een
//    eerlijke netwerk-uitkomst, geen stille val.
//
// Credentials in de feed-URL gaan nooit mee naar een andere host: een
// omleiding of enclosure die elders uitkomt wordt van zijn userInfo
// ontdaan vóór er een byte heen gaat.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/log.dart';
import '../../utils/net_guard.dart';
import '../../utils/pinned_http_client.dart';
import '../file_service.dart' show ImportFailure;
import '../net/transport_failure.dart';

/// Bovengrens voor één feeddocument. Ruim genoeg voor jarenlange feeds
/// met honderden items; geen oneindige stroom — zelfde geest als de
/// deck-limiet.
const maxFeedBytes = 8 * 1024 * 1024;

/// Meer omleidingen volgen we niet: een lus blijft een lus.
const _maxRedirectHops = 5;

/// Wat één feed-GET opleverde. [statusCode] 304 betekent: niets nieuws,
/// er komen ook geen [bytes]. Bij [failure] is de rest niet gezet.
class FeedFetchResult {
  const FeedFetchResult._({
    this.statusCode,
    this.bytes,
    this.etag,
    this.lastModified,
    this.finalUrl,
    this.failure,
  });

  const FeedFetchResult.ok({
    required int statusCode,
    Uint8List? bytes,
    String? etag,
    String? lastModified,
    required Uri finalUrl,
  }) : this._(
         statusCode: statusCode,
         bytes: bytes,
         etag: etag,
         lastModified: lastModified,
         finalUrl: finalUrl,
       );

  const FeedFetchResult.failed(ImportFailure failure)
    : this._(failure: failure);

  final int? statusCode;
  final Uint8List? bytes;
  final String? etag;
  final String? lastModified;
  final Uri? finalUrl;
  final ImportFailure? failure;

  bool get notModified => statusCode == HttpStatus.notModified;
  bool get ok => statusCode == HttpStatus.ok && bytes != null;
}

/// Strip credentials die per omleiding of verwijzing op een andere host
/// zouden belanden. Zelfde host: behouden — daar stond de gebruiker ze
/// zelf bij. Anders: weg, de server geeft geen toestemming voor andermans
/// inloggegevens.
Uri _credentialsGuarded(Uri target, Uri origin) {
  if (target.userInfo.isEmpty || target.host == origin.host) return target;
  return target.replace(userInfo: '');
}

/// Eén begrensde feed-GET, optioneel conditioneel op [etag]/
/// [lastModified]. Desktop toetst elke omleidingshop opnieuw via
/// NetGuard; [client] injecteert een testclient (web-pad) of omzeilt het
/// pin-pad niet — de desktoproute blijft gepind. Een opgegeven [allowUrl]
/// geldt bij elke native omleiding; op web is de definitieve URL niet toetsbaar.
/// [totalTimeout] begrenst op native ook trage, voortdurend druppelende bodies.
Future<FeedFetchResult> fetchFeed(
  Uri url, {
  String? etag,
  String? lastModified,
  int maxBytes = maxFeedBytes,
  Duration timeout = const Duration(seconds: 30),
  bool Function(Uri url)? allowUrl,
  Duration? totalTimeout,
  @visibleForTesting http.Client? client,
}) async {
  final scheme = url.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || allowUrl?.call(url) == false) {
    return const FeedFetchResult.failed(ImportFailure.insecureScheme);
  }
  if (kIsWeb && allowUrl != null) {
    return const FeedFetchResult.failed(ImportFailure.blockedHost);
  }
  if (kIsWeb || client != null) {
    return _fetchFeedWeb(
      url,
      etag: etag,
      lastModified: lastModified,
      maxBytes: maxBytes,
      timeout: timeout,
      client: client,
    );
  }
  return _fetchFeedPinned(
    url,
    etag: etag,
    lastModified: lastModified,
    maxBytes: maxBytes,
    timeout: timeout,
    allowUrl: allowUrl,
    totalTimeout: totalTimeout,
  );
}

/// Browser-pad: package:http ziet status en headers; de browser volgt
/// omleidingen zelf binnen CORS. `finalUrl` is op web niet zichtbaar
/// zonder extra API's — de aangevraagde URL geldt als eindadres.
Future<FeedFetchResult> _fetchFeedWeb(
  Uri url, {
  String? etag,
  String? lastModified,
  required int maxBytes,
  required Duration timeout,
  http.Client? client,
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final request = http.Request('GET', url);
    if (etag != null) request.headers['If-None-Match'] = etag;
    if (lastModified != null) {
      request.headers['If-Modified-Since'] = lastModified;
    }
    final response = await c.send(request).timeout(timeout);
    if (response.statusCode == HttpStatus.notModified) {
      await response.stream.listen(null).cancel();
      return FeedFetchResult.ok(
        statusCode: HttpStatus.notModified,
        finalUrl: url,
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.listen(null).cancel();
      return FeedFetchResult.failed(_classifyFeedStatus(response.statusCode));
    }
    if (response.contentLength != null && response.contentLength! > maxBytes) {
      await response.stream.listen(null).cancel();
      return const FeedFetchResult.failed(ImportFailure.tooLarge);
    }
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          return const FeedFetchResult.failed(ImportFailure.tooLarge);
        }
      }
    } finally {
      // Stream kan al gedraineerd zijn; cancel is dan een no-op.
    }
    return FeedFetchResult.ok(
      statusCode: HttpStatus.ok,
      bytes: builder.takeBytes(),
      etag: response.headers['etag'],
      lastModified: response.headers['last-modified'],
      finalUrl: url,
    );
  } catch (e) {
    logWarning('feed_fetch: web-ophalen mislukt', e);
    return const FeedFetchResult.failed(ImportFailure.network);
  } finally {
    if (owned) c.close();
  }
}

/// Desktop-pad: NetGuard-resolve + gepinde client, 3xx handmatig en per
/// hop opnieuw getoetst — een omleiding kan naar een intern adres wijzen
/// en mag de hostcontrole nooit omzeilen.
Future<FeedFetchResult> _fetchFeedPinned(
  Uri url, {
  String? etag,
  String? lastModified,
  required int maxBytes,
  required Duration timeout,
  bool Function(Uri url)? allowUrl,
  Duration? totalTimeout,
}) async {
  final elapsed = Stopwatch()..start();
  Duration? remaining() =>
      totalTimeout == null ? null : totalTimeout - elapsed.elapsed;
  var current = url;
  for (var hop = 0; hop <= _maxRedirectHops; hop++) {
    if (allowUrl?.call(current) == false ||
        NetGuard.isBlockedHost(current.host)) {
      return const FeedFetchResult.failed(ImportFailure.blockedHost);
    }
    final dnsBudget = remaining();
    if (dnsBudget != null && dnsBudget <= Duration.zero) {
      return const FeedFetchResult.failed(ImportFailure.network);
    }
    final lookup = NetGuard.resolveConfigured(
      current.host,
      allowPrivate: false,
    );
    final resolved = dnsBudget == null
        ? await lookup
        : await lookup
              .then<HostResolution?>((value) => value)
              .timeout(dnsBudget, onTimeout: () => null);
    if (resolved == null) {
      return const FeedFetchResult.failed(ImportFailure.network);
    }
    if (!resolved.isOk) {
      return FeedFetchResult.failed(
        resolved.refusal == HostRefusal.unknownHost
            ? ImportFailure.unknownHost
            : ImportFailure.blockedHost,
      );
    }
    final client = buildPinnedClient(resolved.addresses!.first);
    final budget = remaining();
    final deadline = budget == null
        ? null
        : Timer(budget, () => client.close(force: true));
    try {
      final request = await client.getUrl(current);
      // Verplicht volgens de pinned-client-conventie: omleidingen gaan
      // door deze lus, nooit door de client zelf (zie network_sink_guard).
      request.followRedirects = false;
      if (etag != null) request.headers.set('If-None-Match', etag);
      if (lastModified != null) {
        request.headers.set('If-Modified-Since', lastModified);
      }
      final response = await request.close().timeout(timeout);
      final status = response.statusCode;
      // Elke hop heeft zijn eigen client, die we in finally geforceerd
      // sluiten. Een ongebruikte body hoeven we daarom niet leeg te lezen.
      if (status == HttpStatus.notModified) {
        return FeedFetchResult.ok(statusCode: status, finalUrl: current);
      }
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null || hop == _maxRedirectHops) {
          return const FeedFetchResult.failed(ImportFailure.redirect);
        }
        final next = _credentialsGuarded(current.resolve(location), url);
        if (next.scheme != 'http' && next.scheme != 'https') {
          return const FeedFetchResult.failed(ImportFailure.insecureScheme);
        }
        current = next;
        continue;
      }
      if (status != HttpStatus.ok) {
        return FeedFetchResult.failed(_classifyFeedStatus(status));
      }
      if (response.contentLength > maxBytes) {
        return const FeedFetchResult.failed(ImportFailure.tooLarge);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          return const FeedFetchResult.failed(ImportFailure.tooLarge);
        }
      }
      return FeedFetchResult.ok(
        statusCode: status,
        bytes: builder.takeBytes(),
        etag: response.headers.value('etag'),
        lastModified: response.headers.value('last-modified'),
        finalUrl: current,
      );
    } catch (e) {
      final kind = classifyTransportFailure(e);
      logTransportFailure('feed_fetch', kind, e);
      return FeedFetchResult.failed(
        kind == TransportFailure.tls
            ? ImportFailure.tls
            : ImportFailure.network,
      );
    } finally {
      deadline?.cancel();
      client.close(force: true);
    }
  }
  return const FeedFetchResult.failed(ImportFailure.redirect);
}

/// Zelfde status→reden-indeling als de URL-import (`_classifyUrlImportStatus`
/// is library-prive): 404 is "hier staat niets", 3xx zonder bruikbare
/// Location is "omgeleid", de rest generiek netwerk.
ImportFailure _classifyFeedStatus(int status) {
  if (status == HttpStatus.notFound) return ImportFailure.notFound;
  if (status >= 300 && status < 400) return ImportFailure.redirect;
  return ImportFailure.network;
}

/// Streaming-download van een aflevering of andere mediabron naar
/// [destPath] — desktop-only: op web gaan bytes via [fetchFeed] naar de
/// `mem:`-assetstore (een `File` bestaat daar niet). Eigen omvangsgrens
/// ([maxBytes]) in plaats van de feed-/deck-limiet; een halve download
/// wordt opgeruimd zodat er nooit een afgekapt bestand als bron blijft
/// staan.
Future<({String? path, ImportFailure? failure})> downloadFeedMedia(
  Uri url,
  String destPath, {
  required int maxBytes,
  void Function(int received, int? total)? onProgress,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final scheme = url.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return (path: null, failure: ImportFailure.insecureScheme);
  }
  var current = url;
  for (var hop = 0; hop <= _maxRedirectHops; hop++) {
    if (NetGuard.isBlockedHost(current.host)) {
      return (path: null, failure: ImportFailure.blockedHost);
    }
    final resolved = await NetGuard.resolveConfigured(
      current.host,
      allowPrivate: false,
    );
    if (!resolved.isOk) {
      return (
        path: null,
        failure: resolved.refusal == HostRefusal.unknownHost
            ? ImportFailure.unknownHost
            : ImportFailure.blockedHost,
      );
    }
    final client = buildPinnedClient(resolved.addresses!.first);
    try {
      final request = await client.getUrl(current);
      // Pinned-client-conventie: omleidingen lopen via deze lus.
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      final status = response.statusCode;
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null || hop == _maxRedirectHops) {
          return (path: null, failure: ImportFailure.redirect);
        }
        final next = _credentialsGuarded(current.resolve(location), url);
        if (next.scheme != 'http' && next.scheme != 'https') {
          return (path: null, failure: ImportFailure.insecureScheme);
        }
        current = next;
        continue;
      }
      if (status != HttpStatus.ok) {
        return (path: null, failure: _classifyFeedStatus(status));
      }
      if (response.contentLength > maxBytes) {
        return (path: null, failure: ImportFailure.tooLarge);
      }
      final file = File(destPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(timeout)) {
          received += chunk.length;
          if (received > maxBytes) {
            await sink.close();
            await _deleteQuietly(file);
            return (path: null, failure: ImportFailure.tooLarge);
          }
          sink.add(chunk);
          onProgress?.call(received, response.contentLength);
        }
      } finally {
        await sink.close();
      }
      return (path: destPath, failure: null);
    } catch (e) {
      final kind = classifyTransportFailure(e);
      logTransportFailure('feed_fetch.downloadFeedMedia', kind, e);
      await _deleteQuietly(File(destPath));
      return (
        path: null,
        failure: kind == TransportFailure.tls
            ? ImportFailure.tls
            : ImportFailure.network,
      );
    } finally {
      client.close(force: true);
    }
  }
  return (path: null, failure: ImportFailure.redirect);
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on Object {
    // Opruiming die mislukt mag de eigenlijke uitkomst niet overschrijven.
  }
}
