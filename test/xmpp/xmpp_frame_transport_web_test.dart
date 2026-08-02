import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/xmpp_settings.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport_web.dart';

void main() {
  test('web transport refuses an unpinnable XMPP connection', () async {
    const settings = XmppSettings(
      serverUrl: 'wss://xmpp.example/xmpp-websocket',
      jid: 'alice@example.org',
    );

    await expectLater(
      openXmppFrameTransport(settings),
      throwsA(
        isA<XmppConnectException>().having(
          (error) => error.message,
          'message',
          contains('not supported on the web'),
        ),
      ),
    );
  });
}
