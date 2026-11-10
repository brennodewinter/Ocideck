import 'video_embed_host.dart';

/// A bounded local document URL avoids WebView2's 2 MiB inline HTML limit.
/// The host exposes only this generated document, never project files.
class OfflineRenderDocument {
  OfflineRenderDocument._(this._host);
  final VideoEmbedHost _host;
  Uri get uri => _host.uri;

  static Future<OfflineRenderDocument> start(String html) async =>
      OfflineRenderDocument._(await VideoEmbedHost.start(html));

  Future<void> close() => _host.close();
}
