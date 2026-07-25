import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../services/web_asset_store.dart';

/// Webvariant van [mem_asset_blob.dart]. Maakt eenmalig een `blob:`-URL van de
/// bytes achter [memPath] en onthoudt hem, zodat herhaald renderen niet telkens
/// een nieuwe blob (en dus een lek) oplevert. De blob leeft — net als de
/// [WebAssetStore] zelf — zolang de pagina leeft.
final Map<String, String> _urls = {};

String? memAssetBlobUrl(String memPath) {
  final cached = _urls[memPath];
  if (cached != null) return cached;
  final bytes = WebAssetStore.bytesFor(memPath);
  if (bytes == null) return null;
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(
      type: _mimeForName(WebAssetStore.nameFor(memPath) ?? ''),
    ),
  );
  final url = web.URL.createObjectURL(blob);
  _urls[memPath] = url;
  return url;
}

/// MIME-type uit de bestandsnaam. Media wordt niet op magic bytes gevalideerd
/// (FILE_FORMAT §13), dus de extensie is de enige aanwijzing; bij een onbekende
/// extensie laat de browser zelf snuffelen.
String _mimeForName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'ogv' => 'video/ogg',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    'flac' => 'audio/flac',
    _ => 'application/octet-stream',
  };
}
