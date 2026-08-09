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
import '../utils/log.dart';
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
  // dart:io rewrites ws→http and wss→https before calling the connection
  // factory. For wss the factory must see https (fail closed on a downgrade
  // that would strip TLS and leak the SASL password). For ws the factory sees
  // http — only acceptable to a literal loopback address (checked above), where
  // there is no TLS to strip and no wire for a listener to sit on.
  final plainLoopback = scheme == 'ws';

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..connectionFactory = (uri, _, _) {
      // Redirects can't run past the host check here even though the app cannot
      // set `followRedirects = false` — `WebSocket.connect` builds the upgrade
      // request internally. This factory is called for EVERY hop, including a 3xx
      // redirect, and pins each to the one `resolveConfigured`-approved address
      // (the closure captures `pinned`), so a redirect never reaches a new,
      // unvetted host; the https assert below also refuses a downgrade hop, and a
      // 3xx is not a 101 so the upgrade fails regardless. This is the documented
      // exception in `network_sink_guard_test.dart`'s redirect ratchet.
      //
      // Fail closed on the SDK-internal wss→https rewrite: NetGuard.connectPinned
      // drops to a PLAIN (un-TLS'd) socket for any non-https scheme, which would
      // strip TLS and leak the SASL password. dart:io rewrites wss→https before
      // calling this factory; if it ever stops, refuse — never downgrade.
      // The one exception is ws→http to a literal loopback address (the local
      // testbed): no TLS to strip, no wire to listen on.
      final uriScheme = uri.scheme.toLowerCase();
      if (uriScheme != 'https' && !(plainLoopback && uriScheme == 'http')) {
        throw XmppConnectException(
          'refusing an unpinned XMPP socket (factory saw $uriScheme)',
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
    if (_closed) return;
    try {
      _socket.add(frame);
    } catch (e) {
      // De socket kan tussen de _closed-check en de send sluiten (race). Een
      // onafgevangen uitzondering hier zou de app laten crashen (#1430).
      _closed = true;
      logWarning('xmpp.transport.send', e);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.close();
    } catch (e) {
      // close() kan gooien als de socket al halverwege de sluiting is — niet
      // fataal, maar mag niet crashen (#1430).
      logWarning('xmpp.transport.close', e);
    }
    try {
      _client.close(force: true);
    } catch (e) {
      logWarning('xmpp.transport.httpClientClose', e);
    }
  }
}
