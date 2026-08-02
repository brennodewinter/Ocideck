import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/xmpp_settings.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport_io.dart';

void main() {
  Matcher refusesWith(String message) => throwsA(
    isA<XmppConnectException>().having(
      (error) => error.message,
      'message',
      contains(message),
    ),
  );

  test('refuses an unparseable endpoint before opening a socket', () async {
    await expectLater(
      openXmppFrameTransport(const XmppSettings(serverUrl: 'not a URL')),
      refusesWith('unparseable'),
    );
  });

  test('refuses plaintext XMPP to a named host', () async {
    await expectLater(
      openXmppFrameTransport(
        const XmppSettings(serverUrl: 'ws://xmpp.example/socket'),
      ),
      refusesWith('must be wss://'),
    );
  });

  test('refuses a non-WebSocket scheme', () async {
    await expectLater(
      openXmppFrameTransport(
        const XmppSettings(serverUrl: 'https://xmpp.example/socket'),
      ),
      refusesWith('endpoint must be wss://'),
    );
  });

  test('refuses an untrusted loopback endpoint', () async {
    await expectLater(
      openXmppFrameTransport(
        const XmppSettings(serverUrl: 'ws://127.0.0.1/socket'),
      ),
      refusesWith('host refused'),
    );
  });

  test(
    'maps a failed trusted loopback upgrade to a connection refusal',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      await expectLater(
        openXmppFrameTransport(
          XmppSettings(
            serverUrl: 'ws://127.0.0.1:${server.port}/socket',
            trustedInternal: true,
          ),
        ),
        throwsA(isA<XmppConnectException>()),
      );
    },
  );
}
