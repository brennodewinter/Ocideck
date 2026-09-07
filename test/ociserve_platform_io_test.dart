@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/ociserve/ociserve_auth_platform.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_http_factory.dart';

void main() {
  test('de lokale OIDC-ontvanger neemt één geldige callback aan', () async {
    final receiver = await createOciServeAuthorizationReceiver();
    addTearDown(receiver.close);
    final redirectUri = receiver.redirectUri;
    expect(redirectUri.host, '127.0.0.1');
    expect(redirectUri.path, '/oauth/callback');

    final received = receiver.receive(const Duration(seconds: 2));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      redirectUri.replace(queryParameters: const {'code': 'eenmalig'}),
    );
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.ok);
    expect(await received, const {'code': 'eenmalig'});
  });

  test('de lokale OIDC-ontvanger weigert een verkeerde callback', () async {
    final receiver = await createOciServeAuthorizationReceiver();
    addTearDown(receiver.close);
    final redirectUri = receiver.redirectUri;
    final received = expectLater(
      receiver.receive(const Duration(seconds: 2)),
      throwsFormatException,
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(redirectUri);
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.badRequest);
    await received;
  });

  test(
    'de OciServe-transport weigert onveilige verzoeken vóór netwerkgebruik',
    () async {
      final transport = createOciServeHttpTransport();

      await expectLater(
        transport.send(
          method: 'GET',
          url: Uri.parse('http://example.test'),
          trustedInternal: false,
        ),
        throwsA(
          isA<OciServeTransportException>().having(
            (error) => error.code,
            'code',
            'request_refused',
          ),
        ),
      );
      await expectLater(
        transport.send(
          method: 'GET',
          url: Uri.parse('https://127.0.0.1:9'),
          trustedInternal: false,
        ),
        throwsA(
          isA<OciServeTransportException>().having(
            (error) => error.code,
            'code',
            'host_refused',
          ),
        ),
      );
    },
  );

  test(
    'een toegestane maar onbereikbare server wordt een netwerkfout',
    () async {
      final transport = createOciServeHttpTransport();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final subscription = server.listen((socket) => socket.destroy());
      addTearDown(subscription.cancel);

      await expectLater(
        transport.send(
          method: 'GET',
          url: Uri.parse('https://127.0.0.1:${server.port}'),
          trustedInternal: true,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(
          isA<OciServeTransportException>().having(
            (error) => error.code,
            'code',
            'network',
          ),
        ),
      );
    },
  );
}
