// The frame-transport seam of the XMPP client (F2, `NATIVE_CALLS.md` §5). XMPP
// over WebSocket (RFC 7395) sends each stanza and stream element as one WebSocket
// TEXT frame, so this seam is simply "send a frame, receive frames" — there is no
// incremental XML stream to parse. The connection state machine
// (`xmpp_connection.dart`) is written against this interface and unit-tested with
// an in-memory fake; the real socket lives only behind the io implementation
// (`xmpp_frame_transport_io.dart`, the layer's single egress point).

/// A bidirectional stream of XMPP frames, each a complete XML element.
abstract interface class XmppFrameTransport {
  /// Frames arriving from the server, in order. Single-subscription.
  Stream<String> get inbound;

  /// Send one frame (a complete XML element).
  void send(String frame);

  /// Close the transport and release the socket. Idempotent.
  Future<void> close();
}

/// A fail-closed refusal to open or keep an XMPP connection: an internal/blocked
/// host, a non-wss scheme to a named host, an untrusted certificate, a redirect,
/// or a platform without socket pinning (web).
class XmppConnectException implements Exception {
  const XmppConnectException(this.message);

  final String message;

  @override
  String toString() => 'XmppConnectException: $message';
}
