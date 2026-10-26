// De web-transport voor de live-ASR-route (#2525). De browser is hier
// de netwerkgrens — hetzelfde recept als `xmpp_frame_transport_web`:
// DNS, TLS en CORS doet de browser, pinnen kan niet, en de pagina-CSP
// begrenst met `connect-src` waar de socket heen mag (`wss:` staat
// daarvoor in de CSP; `ws:` hoort hooguit bij een loopback-testbed,
// waar 'self' dekt).
//
// Twee browsergrenzen die de engine en de docs eerlijk moeten melden:
//  * een `WebSocket` kan in de browser geen aangepaste headers zetten —
//    [headers] wordt hier bewust genegeerd, dus een API-sleutel-eisende
//    live-server is op web onbereikbaar (en de sleutel gaat per
//    contract nooit in de URL of query);
//  * de browser stuurt zelf een `Origin`-header mee — of de server die
//    toelaat is zijn beleid, geen OciDeck-eigenschap.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'asr_live_transport.dart';

final class WebAsrLiveTransport implements AsrLiveTransport {
  const WebAsrLiveTransport({
    this.connectTimeout = const Duration(seconds: 15),
  });

  final Duration connectTimeout;

  @override
  Future<AsrLiveSocket> connect({
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
  }) async {
    final socket = web.WebSocket(url.toString())..binaryType = 'arraybuffer';
    final completer = Completer<AsrLiveSocket>();
    final inner = _WebLiveSocket(socket);
    inner._onEarlyClose = () {
      if (!completer.isCompleted) {
        completer.completeError(const AsrLiveException('verbinding geweigerd'));
      }
    };
    final timer = Timer(connectTimeout, () {
      unawaited(inner.close());
      if (!completer.isCompleted) {
        completer.completeError(const AsrLiveException('verbinding verliep'));
      }
    });
    socket.onopen = ((web.Event _) {
      timer.cancel();
      inner._onEarlyClose = null;
      if (!completer.isCompleted) completer.complete(inner);
    }).toJS;
    socket.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        timer.cancel();
        completer.completeError(const AsrLiveException('verbinding mislukt'));
      }
    }).toJS;
    return completer.future;
  }
}

final class _WebLiveSocket implements AsrLiveSocket {
  _WebLiveSocket(this._socket) {
    _socket.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data.isA<JSString>()) {
        _inbound.add((data as JSString).toDart);
      } else if (data.isA<JSArrayBuffer>()) {
        _inbound.add((data as JSArrayBuffer).toDart.asUint8List());
      }
    }).toJS;
    _socket.onclose = ((web.CloseEvent event) {
      _closed = true;
      _code = event.code;
      _onEarlyClose?.call();
      unawaited(_inbound.close());
    }).toJS;
  }

  final web.WebSocket _socket;
  final StreamController<Object> _inbound = StreamController();
  void Function()? _onEarlyClose;
  bool _closed = false;
  int? _code;

  @override
  Stream<Object> get messages => _inbound.stream;

  @override
  int? get closeCode => _code;

  @override
  void sendBytes(Uint8List frame) {
    if (_closed || _socket.readyState != web.WebSocket.OPEN) return;
    _socket.send(frame.toJS);
  }

  @override
  void sendText(String frame) {
    if (_closed || _socket.readyState != web.WebSocket.OPEN) return;
    _socket.send(frame.toJS);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _socket.close();
    } on Object {
      // Een socket die niet wil sluiten is al dicht genoeg.
    }
    await _inbound.close();
  }
}

AsrLiveTransport createAsrLiveTransport() => const WebAsrLiveTransport();
