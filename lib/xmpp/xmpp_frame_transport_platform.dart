// Selects the platform XMPP WebSocket egress: the NetGuard-pinned dart:io
// implementation on desktop, a fail-closed stub on web (a browser has no socket
// pinning). Mirrors the `matrix_http_transport` conditional-export seam. Provides
// `openXmppFrameTransport(XmppSettings)`.

export 'xmpp_frame_transport_web.dart'
    if (dart.library.io) 'xmpp_frame_transport_io.dart';
