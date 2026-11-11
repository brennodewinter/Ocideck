import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/video_embed_host.dart';

void main() {
  test(
    'embed host serves only its document and closes with the player',
    () async {
      final host = await VideoEmbedHost.start('<html>first</html>');
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      addTearDown(host.close);
      expect(host.uri.host, '127.0.0.1');

      var response = await (await client.getUrl(host.uri)).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(
        response.headers.value('Referrer-Policy'),
        'strict-origin-when-cross-origin',
      );
      expect(
        await response.transform(SystemEncoding().decoder).join(),
        '<html>first</html>',
      );

      host.update('<html>second</html>');
      response = await (await client.getUrl(host.uri)).close();
      expect(
        await response.transform(SystemEncoding().decoder).join(),
        '<html>second</html>',
      );

      response = await (await client.getUrl(
        host.uri.replace(path: '/etc/passwd'),
      )).close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();

      final request = await client.postUrl(host.uri);
      response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();

      final rebound = await client.getUrl(host.uri);
      rebound.headers.set(HttpHeaders.hostHeader, 'attacker.invalid');
      response = await rebound.close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();

      await host.close();
      await expectLater(
        Socket.connect(host.uri.host, host.uri.port),
        throwsA(isA<SocketException>()),
      );
    },
  );
}
