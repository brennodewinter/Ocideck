import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'image_limits.dart';
import 'log.dart';
import 'net_guard.dart';
import 'pinned_http_client.dart';

/// Bovengrens op wat een remote afbeelding aan bytes mag opleveren.
///
/// Los van de decode-cap in [kMaxImageDecodeDimension]: die begrenst wat een
/// afbeelding aan geheugen kost ná het decoderen, deze begrenst wat een host
/// überhaupt de leiding in mag duwen. Een server die eindeloos blijft sturen
/// vult anders het werkgeheugen vóór de decoder ook maar iets te zien krijgt.
/// 64 MiB is ruim boven elke realistische dia-afbeelding.
const int kMaxRemoteMediaBytes = 64 * 1024 * 1024;

/// De afbeeldingsprovider voor een remote media-URL, met de socket vastgepind
/// op het adres dat [NetGuard.safeResolve] heeft goedgekeurd.
///
/// Hier zat het gat dat de audit als AEG-04 noteerde. `NetworkImage` resolvet de
/// hostnaam zelf op het moment van ophalen, dus een `isAllowedMediaUrlResolved`
/// ervóór keurde een adres dat daarna opnieuw werd opgezocht. Wie DNS in handen
/// heeft, kan in dat venster omvlaggen naar een intern adres — dezelfde
/// TOCTOU-rebind waar de deck-import zich met pinning al tegen wapende.
///
/// Nu halen we de bytes zelf op over een gepinde socket en geven ze aan
/// [CappedImage]. Er is geen tweede naamsopzoeking meer, dus geen venster.
/// TLS valideert nog steeds tegen de hóstnaam, niet tegen het IP — dat doet
/// [NetGuard.connectPinned].
ImageProvider guardedNetworkImage(String url) =>
    CappedImage(url, () => _fetchPinned(url));

Future<Uint8List> _fetchPinned(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw const _RemoteMediaRefused('alleen http(s)');
  }
  final addresses = await NetGuard.safeResolve(uri.host);
  if (addresses == null || addresses.isEmpty) {
    throw _RemoteMediaRefused('host geweigerd: ${uri.host}');
  }
  final pinned = addresses.first;

  final client = buildPinnedClient(pinned);
  try {
    final request = await client.getUrl(uri);
    // Een 3xx mag de hostcontrole hierboven niet omzeilen: dan wees de
    // omleiding alsnog naar binnen en was het pinnen voor niets.
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw _RemoteMediaRefused('HTTP ${response.statusCode}');
    }
    return readCappedMedia(response, contentLength: response.contentLength);
  } catch (e) {
    // De aanroeper is een `Image`-widget: die vangt de fout en toont zijn
    // errorBuilder-placeholder. Loggen zodat een geweigerde host niet
    // stilzwijgend als "plaatje kapot" voorbijgaat.
    logWarning('guardedNetworkImage: ophalen mislukt', e);
    rethrow;
  } finally {
    client.close(force: true);
  }
}

class _RemoteMediaRefused implements Exception {
  const _RemoteMediaRefused(this.reason);
  final String reason;
  @override
  String toString() => 'Remote media geweigerd: $reason';
}

/// Leest [chunks] tot [maxBytes] en weigert daarboven.
///
/// Los van [guardedNetworkImageBytes] omdat de grens daar onbereikbaar is voor
/// een test: die pint de socket via [NetGuard], en die weigert loopback — een
/// testserver op deze machine bestaat per ontwerp niet. De grens is precies het
/// stuk dat wél te toetsen valt, dus staat het apart (#618).
///
/// [contentLength] is een hint, geen belofte: er wordt zélf meegeteld. Een
/// liegende of ontbrekende Content-Length (-1) mag niet meer opleveren dan een
/// afgekapte respons.
@visibleForTesting
Future<Uint8List> readCappedMedia(
  Stream<List<int>> chunks, {
  required int contentLength,
  int maxBytes = kMaxRemoteMediaBytes,
}) async {
  if (contentLength > maxBytes) {
    throw const _RemoteMediaRefused('afbeelding te groot');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in chunks) {
    builder.add(chunk);
    // Ná het optellen: de brok die eroverheen gaat mag niet meer meetellen.
    if (builder.length > maxBytes) {
      throw const _RemoteMediaRefused('afbeelding te groot');
    }
  }
  return builder.takeBytes();
}
