// The web build has no raw socket and no certificate pinning, so a guarded XMPP
// connection cannot be opened there in v1 — fail closed and say so honestly rather
// than open an unpinnable socket (`NATIVE_CALLS.md` §8; mirrors
// `matrix_http_transport_web.dart`). Desktop is the target for the connection
// slice; a web path needs a decided CSP `connect-src wss:` delta first.

import '../models/xmpp_settings.dart';
import 'xmpp_frame_transport.dart';

Future<XmppFrameTransport> openXmppFrameTransport(XmppSettings settings) async {
  throw const XmppConnectException(
    'XMPP connections are not supported on the web build yet (no socket pinning)',
  );
}
