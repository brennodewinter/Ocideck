import 'dart:async';
import 'dart:io';

import 'ociserve_auth_platform.dart';

Future<OciServeAuthorizationReceiver>
createOciServeAuthorizationReceiver() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  return _LoopbackAuthorizationReceiver(server);
}

class _LoopbackAuthorizationReceiver implements OciServeAuthorizationReceiver {
  _LoopbackAuthorizationReceiver(this._server);

  final HttpServer _server;

  @override
  Uri get redirectUri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: '/oauth/callback',
  );

  @override
  Future<Map<String, String>> receive(Duration timeout) async {
    final requests = StreamIterator(_server);
    try {
      if (!await requests.moveNext().timeout(timeout)) {
        throw const FormatException('missing callback');
      }
      final request = requests.current;
      final valid =
          request.method == 'GET' &&
          request.uri.path == '/oauth/callback' &&
          request.connectionInfo?.remoteAddress.isLoopback == true;
      request.response.statusCode = valid
          ? HttpStatus.ok
          : HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        valid
            ? '<!doctype html><meta charset="utf-8"><title>OciDeck</title>'
                  '<p>Authentication completed. You can close this window.</p>'
            : '<!doctype html><meta charset="utf-8"><title>OciDeck</title>'
                  '<p>Invalid callback.</p>',
      );
      await request.response.close();
      if (!valid) throw const FormatException('invalid callback');
      return Map<String, String>.from(request.uri.queryParameters);
    } finally {
      await requests.cancel();
    }
  }

  @override
  Future<void> close() => _server.close(force: true);
}
