import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../utils/net_guard.dart';
import 'model_download.dart';
import 'model_store.dart';
import 'whisper_model.dart';

/// Wat één HTTP-hop oplevert. Los van `HttpClientResponse` zodat tests de
/// volledige redirect- en limietlogica kunnen toetsen zonder dat NetGuard
/// (terecht) loopback weigert.
class ModelFetchResult {
  const ModelFetchResult({
    required this.statusCode,
    this.contentLength = -1,
    this.location,
    this.body = const Stream.empty(),
    this.dispose,
  });

  final int statusCode;
  final int contentLength;

  /// Het `Location`-antwoord bij een redirect, anders null.
  final String? location;

  /// De body — leeg bij een redirect.
  final Stream<List<int>> body;

  /// Breekt de onderliggende connectie af — bij een redirect (die body gaat
  /// nooit de byteslus in) én bij elk voortijdig einde van de byteslus, zodat
  /// een geannuleerde download zijn socket niet open laat staan.
  final Future<void> Function()? dispose;
}

/// De transportpunt waar NetGuard omheen zit: één request, host opgelost
/// door de poort en de socket op het gekeurde adres vastgezet, redirects
/// bewust uit. In tests vervangbaar; in productie is dit de enige weg.
typedef ModelFetch = Future<ModelFetchResult> Function(Uri url);

/// De desktop-downloader (§4.4). Volgt de redirect-keten met de hand zodat
/// élke hop — ook de derde CDN-sprong — opnieuw door [NetGuard.safeResolve]
/// gaat; zie GithubBulkTransport voor waarom dat niet optioneel is.
class IoModelDownloader implements ModelDownloader {
  IoModelDownloader({ModelFetch? fetch}) : _fetch = fetch ?? _netGuardFetch;

  final ModelFetch _fetch;

  static const _maxRedirects = 5;

  /// Hoe lang er tussen twee brokken mag zitten. Zonder deze grens staat
  /// een stilgevallen CDN de download voorgoed op "bezig" — dezelfde les
  /// als bij de CVE-transport.
  static const _chunkTimeout = Duration(seconds: 60);

  @override
  ModelDownload start(WhisperModel model, ModelStorePath destination) {
    final handle = _IoModelDownload._();
    unawaited(_run(model, destination, handle));
    return handle;
  }

  Future<void> _run(
    WhisperModel model,
    ModelStorePath destination,
    _IoModelDownload handle,
  ) async {
    final part = File('${destination.path}.part');
    try {
      await part.parent.create(recursive: true);
      if (await part.exists()) await part.delete();

      final response = await _follow(model.url);
      if (response.statusCode != 200) {
        throw ModelDownloadException(
          ModelDownloadFailure.networkFailed,
          'HTTP ${response.statusCode}',
        );
      }

      // De catalogus weet precies hoe groot het bestand is; een server die
      // iets anders aankondigt levert sowieso een hash-mismatch — vroeg en
      // duidelijk stoppen is eerlijker dan de gebruiker een mislukte
      // verificatie laten afwachten.
      final announced = response.contentLength;
      if (announced > 0 && announced != model.downloadBytes) {
        throw ModelDownloadException(
          ModelDownloadFailure.refused,
          'de server kondigt $announced bytes aan, de catalogus '
          '${model.downloadBytes}',
        );
      }

      handle._emit(
        ModelDownloadProgress(
          ModelDownloadPhase.downloading,
          0,
          announced > 0 ? announced : model.downloadBytes,
        ),
      );

      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.body.timeout(_chunkTimeout)) {
          handle._throwIfCancelled();
          received += chunk.length;
          // Ná optellen, vóór schrijven: een stream die verder groeit dan
          // de catalogus is kapot of kwaad, en die bytes horen niet op schijf.
          if (received > model.downloadBytes) {
            throw const ModelDownloadException(
              ModelDownloadFailure.refused,
              'de download groeide voorbij de catalogusomvang',
            );
          }
          sink.add(chunk);
          handle._emit(
            ModelDownloadProgress(
              ModelDownloadPhase.downloading,
              received,
              announced > 0 ? announced : model.downloadBytes,
            ),
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
        // Ook na een normale afronding is dit onschadelijk (`close` is
        // idempotent); bij annulering of een fout is dit dé opruiming.
        await response.dispose?.call();
      }

      handle._emit(
        ModelDownloadProgress(
          ModelDownloadPhase.verifying,
          received,
          model.downloadBytes,
        ),
      );

      final digest = await sha256
          .bind(part.openRead())
          .single
          .then((d) => d.toString());
      handle._throwIfCancelled();
      if (digest != model.sha256) {
        await part.delete();
        throw const ModelDownloadException(
          ModelDownloadFailure.invalidHash,
          'de SHA-256 van het bestand wijkt af van de catalogus',
        );
      }

      // Pas nu mag het eindpad bestaan — en nooit eerder. `rename` op
      // dezelfde map is atomair, dus een crash tussen hash en hernoem
      // kan geen half "geïnstalleerd" bestand achterlaten.
      await part.rename(destination.path);
      handle._complete(ModelStorePath(destination.path, true));
    } on ModelDownloadException catch (e) {
      await _removeQuietly(part);
      handle._fail(e);
    } on SocketException catch (e) {
      await _removeQuietly(part);
      handle._fail(
        ModelDownloadException(ModelDownloadFailure.networkFailed, e.message),
      );
    } on HttpException catch (e) {
      await _removeQuietly(part);
      handle._fail(
        ModelDownloadException(ModelDownloadFailure.networkFailed, e.message),
      );
    } on TimeoutException {
      await _removeQuietly(part);
      handle._fail(
        const ModelDownloadException(
          ModelDownloadFailure.networkFailed,
          'de transfer stond te lang stil',
        ),
      );
    } on FileSystemException catch (e) {
      await _removeQuietly(part);
      handle._fail(
        ModelDownloadException(ModelDownloadFailure.ioFailed, e.message),
      );
    }
  }

  /// Volgt de keten hop voor hop. Elke bestemming is een nieuwe URL die
  /// opnieuw door [ModelFetch] — en dus NetGuard — gaat; een redirect naar
  /// http of naar `..`-achtige paden lossen we hier al op.
  Future<ModelFetchResult> _follow(Uri url) async {
    var target = url;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (target.scheme != 'https') {
        throw const ModelDownloadException(
          ModelDownloadFailure.refused,
          'alleen https',
        );
      }
      final result = await _fetch(target);
      if (!_isRedirect(result.statusCode)) return result;

      await result.dispose?.call();
      final location = result.location;
      if (location == null) {
        throw const ModelDownloadException(
          ModelDownloadFailure.refused,
          'redirect zonder bestemming',
        );
      }
      target = target.resolve(location);
    }
    throw const ModelDownloadException(
      ModelDownloadFailure.refused,
      'te veel omleidingen',
    );
  }

  static bool _isRedirect(int status) => switch (status) {
    301 || 302 || 303 || 307 || 308 => true,
    _ => false,
  };

  static Future<void> _removeQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on Object {
      // Opruim-hulp is geen reden om de echte fout te verliezen.
    }
  }

  /// Het bewaakte request: host door NetGuard, socket gepind, geen
  /// automatische redirects — precies het recept van pinned_http_client,
  /// hier per hop opnieuw toegepast.
  static Future<ModelFetchResult> _netGuardFetch(Uri url) async {
    final addresses = await NetGuard.safeResolve(url.host);
    if (addresses == null || addresses.isEmpty) {
      throw ModelDownloadException(
        ModelDownloadFailure.refused,
        'host geweigerd: ${url.host}',
      );
    }
    final client = buildPinnedModelClient(addresses.first);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, 'OciDeck');
      request.followRedirects = false;
      final response = await request.close().timeout(_chunkTimeout);
      return ModelFetchResult(
        statusCode: response.statusCode,
        contentLength: response.contentLength,
        location: response.headers.value(HttpHeaders.locationHeader),
        dispose: () async => client.close(force: true),
        body: response,
      );
    } on Object {
      client.close(force: true);
      rethrow;
    }
  }
}

/// De gepinde client — zelfde recept als `buildPinnedClient`, hier gehouden
/// bij de enige andere plaats die het mag gebruiken zodat het recept op
/// één plek blijft (zie utils/pinned_http_client.dart).
HttpClient buildPinnedModelClient(InternetAddress pinnedAddress) {
  final client = HttpClient();
  client.connectionFactory = (uri, proxyHost, proxyPort) =>
      NetGuard.connectPinned(pinnedAddress, uri);
  client.connectionTimeout = const Duration(seconds: 15);
  return client;
}

/// Eén lopende download: de statusschoorsteen en de eindbelofte.
class _IoModelDownload implements ModelDownload {
  _IoModelDownload._();

  final _progress = StreamController<ModelDownloadProgress>();
  final _done = Completer<ModelStorePath>();
  var _cancelled = false;

  @override
  Stream<ModelDownloadProgress> get progress => _progress.stream;

  @override
  Future<ModelStorePath> get done => _done.future;

  @override
  void cancel() => _cancelled = true;

  void _throwIfCancelled() {
    if (_cancelled) {
      throw const ModelDownloadException(ModelDownloadFailure.cancelled);
    }
  }

  void _emit(ModelDownloadProgress p) {
    if (!_progress.isClosed) _progress.add(p);
  }

  void _complete(ModelStorePath path) {
    if (!_done.isCompleted) _done.complete(path);
    unawaited(_progress.close());
  }

  void _fail(ModelDownloadException e) {
    if (!_done.isCompleted) _done.completeError(e);
    unawaited(_progress.close());
  }
}

/// Toetsbaar los van NetGuard: de byteslus + grens + annulering, precies zo
/// als `_run` hem gebruikt. `destination` is in de test een gewone tempfile.
@visibleForTesting
ModelDownloader createTestModelDownloader(ModelFetch fetch) =>
    IoModelDownloader(fetch: fetch);

ModelDownloader createModelDownloader() => IoModelDownloader();
