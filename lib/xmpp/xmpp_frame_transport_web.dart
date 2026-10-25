// De web-helft van de XMPP-egress (RFC 7395 over de browser-WebSocket). De
// browser is hier de netwerkgrens — hetzelfde recept als `media_fetch_web`
// en `asr_transport_web`: DNS en TLS doet de browser, pinnen kan niet, en de
// pagina-CSP begrenst met `connect-src` waar de socket heen mag (`wss:` is
// daarvoor toegevoegd; `ws:` staat er bewust niet in — platte tekst hoort
// hooguit bij een loopback-testbed op dezelfde origin, waar 'self' dekt).
// [XmppSettings.pinnedCertSha256] en [XmppSettings.trustedInternal] gelden
// hier daarom bewust niet.
//
// Wel blijft de schemegrens van de io-helft overeind: `wss` voor elke host,
// `ws` alleen naar een letterlijk loopback-adres — het SASL-wachtwoord gaat
// over deze stroom, dus nooit klartekst naar een naam die via DNS overal
// heen kan wijzen.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/xmpp_settings.dart';
import '../utils/literal_loopback.dart';
import '../utils/log.dart';
import 'xmpp_frame_transport.dart';

Future<XmppFrameTransport> openXmppFrameTransport(XmppSettings settings) async {
  final endpoint = settings.endpoint;
  if (endpoint == null) {
    throw const XmppConnectException('unparseable XMPP server URL');
  }
  if (!allowsWebXmppSocket(endpoint)) {
    throw const XmppConnectException(
      'the XMPP endpoint must be wss:// (or ws:// to a loopback address)',
    );
  }

  final socket = web.WebSocket(
    settings.serverUrl,
    <JSString>['xmpp'.toJS].toJS,
  );
  final completer = Completer<XmppFrameTransport>();
  // Een sluiting vóór `open` is ook een mislukte connect (de server weigerde
  // de upgrade of het subprotocol 'xmpp').
  final transport = _WebSocketFrameTransport(
    socket,
    onClosed: () {
      if (!completer.isCompleted) {
        completer.completeError(
          const XmppConnectException('could not open the XMPP WebSocket'),
        );
      }
    },
  );
  final timer = Timer(const Duration(seconds: 20), () {
    transport.close();
    if (!completer.isCompleted) {
      completer.completeError(
        const XmppConnectException(
          'could not open the XMPP WebSocket: timeout',
        ),
      );
    }
  });

  socket.onopen = ((web.Event _) {
    timer.cancel();
    if (!completer.isCompleted) completer.complete(transport);
  }).toJS;
  // De browser rapporteert weigeringen bewust éénvormig: DNS, TLS en een
  // dichte poort leveren allemaal alleen een generiek error-event op.
  socket.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      timer.cancel();
      completer.completeError(
        const XmppConnectException('could not open the XMPP WebSocket'),
      );
    }
  }).toJS;

  return completer.future;
}

class _WebSocketFrameTransport implements XmppFrameTransport {
  _WebSocketFrameTransport(this._socket, {this.onClosed}) {
    _socket.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      // XMPP-over-WebSocket spreekt tekstframes; binaire frames horen bij
      // deze binding niet en worden genegeerd.
      if (data.isA<JSString>()) {
        _inbound.add((data as JSString).toDart);
      }
    }).toJS;
    _socket.onclose = ((web.CloseEvent _) {
      _closed = true;
      onClosed?.call();
      unawaited(_inbound.close());
    }).toJS;
  }

  final web.WebSocket _socket;

  /// Wordt aangeroepen zodra de socket sluit — ook vóór `open`, zodat de
  /// connect-wachter een vroege weigering als fout kan melden.
  final void Function()? onClosed;
  final StreamController<String> _inbound = StreamController();
  bool _closed = false;

  @override
  Stream<String> get inbound => _inbound.stream;

  @override
  void send(String frame) {
    if (_closed || _socket.readyState != web.WebSocket.OPEN) return;
    try {
      _socket.send(frame.toJS);
    } catch (e) {
      _closed = true;
      logWarning('xmpp.transport.send', e);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _socket.close();
    } catch (e) {
      logWarning('xmpp.transport.close', e);
    }
    await _inbound.close();
  }
}
