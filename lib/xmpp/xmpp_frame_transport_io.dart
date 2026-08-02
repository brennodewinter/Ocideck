// The XMPP WebSocket egress on dart:io targets (desktop). This is the ONLY
// outbound socket the XMPP layer opens; it is listed in
// `network_sink_guard_test.dart`. The recipe mirrors `matrix_http_transport_io.dart`:
// require TLS (wss), resolve the host and refuse internal addresses, pin the
// socket to the validated address (a DNS rebind cannot land on an internal IP),
// and fail closed on any downgrade.
//
// Raw `WebSocket.connect` is used deliberately (not `IOWebSocketChannel`): the
// egress-scan regex catches `WebSocket.connect`, so this socket does not slip past
// the gate that a first outbound connection must face (security-architect, F2).

import 'dart:io';

import '../models/xmpp_settings.dart';
import '../utils/net_guard.dart';
import 'xmpp_frame_transport.dart';

Future<XmppFrameTransport> openXmppFrameTransport(XmppSettings settings) async {
  final endpoint = settings.endpoint;
  if (endpoint == null) {
    throw const XmppConnectException('unparseable XMPP server URL');
  }
  final scheme = endpoint.scheme.toLowerCase();
  if (scheme == 'ws') {
    // Plain ws only to a literal loopback address (the local testbed); never to a
    // named host — the whole stream, password included, would cross in the clear.
    if (!NetGuard.isLiteralLoopbackHost(endpoint.host)) {
      throw const XmppConnectException(
        'an XMPP server must be wss:// — the stream and password cross the wire',
      );
    }
  } else if (scheme != 'wss') {
    throw const XmppConnectException(
      'the XMPP endpoint must be wss:// (or ws:// to a loopback address)',
    );
  }

  final resolved = await NetGuard.resolveConfigured(
    endpoint.host,
    allowPrivate: settings.trustedInternal,
  );
  if (!resolved.isOk) {
    throw XmppConnectException(
      resolved.refusal! == HostRefusal.unknownHost
          ? 'XMPP server name not found'
          : 'XMPP server host refused (internal address?)',
    );
  }
  final pinned = resolved.addresses!.first;

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..connectionFactory = (uri, _, _) {
      // Fail closed on the SDK-internal wss→https rewrite: NetGuard.connectPinned
      // drops to a PLAIN (un-TLS'd) socket for any non-https scheme, which would
      // strip TLS and leak the SASL password. dart:io rewrites wss→https before
      // calling this factory; if it ever stops, refuse — never downgrade.
      if (uri.scheme.toLowerCase() != 'https') {
        throw XmppConnectException(
          'refusing an unpinned XMPP socket (factory saw ${uri.scheme})',
        );
      }
      return NetGuard.connectPinned(
        pinned,
        uri,
        onBadCertificate: NetGuard.pinnedCertCheck(settings.pinnedCertSha256),
      );
    };

  final WebSocket socket;
  try {
    socket = await WebSocket.connect(
      settings.serverUrl,
      protocols: const ['xmpp'],
      customClient: client,
    ).timeout(const Duration(seconds: 20));
  } catch (e) {
    client.close(force: true);
    if (e is XmppConnectException) rethrow;
    throw XmppConnectException('could not open the XMPP WebSocket: $e');
  }
  return _WebSocketFrameTransport(socket, client);
}

class _WebSocketFrameTransport implements XmppFrameTransport {
  _WebSocketFrameTransport(WebSocket socket, this._client)
    : _socket = socket,
      _inbound = socket.where((frame) => frame is String).cast<String>();

  final WebSocket _socket;
  final HttpClient _client;
  final Stream<String> _inbound;
  bool _closed = false;

  @override
  Stream<String> get inbound => _inbound;

  @override
  void send(String frame) {
    if (!_closed) _socket.add(frame);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
    _client.close(force: true);
  }
}
