import 'dart:io';

import 'package:uuid/uuid.dart';

/// WebView2 ignores loadHtmlString's baseUrl. A real document URL supplies the
/// HTTP Referer required by YouTube (otherwise playback fails with error 153).
/// This host serves only one generated document, never files or remote URLs.
class VideoEmbedHost {
  final HttpServer _server;
  final String _path;
  String _html;
  late final Uri uri;

  VideoEmbedHost._(this._server, this._path, this._html) {
    uri = Uri.http('127.0.0.1:${_server.port}', _path);
    _server.listen((request) async {
      final response = request.response;
      if (request.uri.path != _path ||
          request.method != 'GET' ||
          request.headers.value(HttpHeaders.hostHeader) != uri.authority) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.headers.contentType = ContentType.html;
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        response.headers.set(
          'Referrer-Policy',
          'strict-origin-when-cross-origin',
        );
        response.headers.set('X-Content-Type-Options', 'nosniff');
        response.write(_html);
      }
      await response.close();
    });
  }

  static Future<VideoEmbedHost> start(String html) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return VideoEmbedHost._(server, '/${const Uuid().v4()}', html);
  }

  void update(String html) => _html = html;

  Future<void> close() async => _server.close(force: true);
}
