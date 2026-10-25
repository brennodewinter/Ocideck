import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport.dart';

void main() {
  test('connect exception describes its refusal', () {
    expect(
      const XmppConnectException('blocked').toString(),
      'XmppConnectException: blocked',
    );
  });

  // De web-helft zelf kan de test-VM niet compileren (package:web is
  // js-interop only); de echte socket wordt bewezen in het testbed (#2544),
  // en de toetsbare loopback-lexica die zijn schemegrens deelt doorloopt
  // literal_loopback_test.dart.
}
