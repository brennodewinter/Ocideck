// De desktop-transport voor de live-ASR-route (#2525). De WebSocket-
// upgrade is een gewone HTTP-GET, dus de pinning uit `asr_resolve_io`
// geldt hier onverkort: resolve per gate-strategie, socket pinnen op
// het gevalideerde adres via `customClient` — een DNS-rebind kan de
// stream zo niet alsnog naar een intern adres zetten.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/log.dart';
import '../../utils/pinned_http_client.dart';
import 'asr_live_transport.dart';
import 'asr_resolve_io.dart';

final class IoAsrLiveTransport implements AsrLiveTransport {
  const IoAsrLiveTransport({this.connectTimeout = const Duration(seconds: 15)});

  final Duration connectTimeout;

  @override
  Future<AsrLiveSocket> connect({
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
  }) async {
    final pinned = await resolveAsrPinned(url.host, strategy);
    final client = buildPinnedClient(pinned);
    try {
      final ws = await WebSocket.connect(
        url.toString(),
        headers: headers,
        customClient: client,
      ).timeout(connectTimeout);
      // De client blijft bij de socket: de losse upgrade-delegatie van
      // dart:io maakt sluiten onschadelijk, en `close(force)` is de
      // laatste stekker als de stream zelf niet wil sterven.
      return _IoLiveSocket(ws, client);
    } catch (e, s) {
      client.close(force: true);
      logError('IoAsrLiveTransport.connect', e, s);
      throw const AsrLiveException('verbinding mislukt');
    }
  }
}

final class _IoLiveSocket implements AsrLiveSocket {
  _IoLiveSocket(this._ws, this._client);

  final WebSocket _ws;
  final HttpClient _client;

  @override
  Stream<Object> get messages => _ws.map(
    (frame) => frame is String
        ? frame
        : frame is List<int>
        ? Uint8List.fromList(frame)
        : utf8.encode('$frame'),
  );

  @override
  int? get closeCode => _ws.closeCode;

  @override
  void sendBytes(Uint8List frame) {
    if (_ws.readyState != WebSocket.open) return;
    _ws.add(frame);
  }

  @override
  void sendText(String frame) {
    if (_ws.readyState != WebSocket.open) return;
    _ws.addUtf8Text(utf8.encode(frame));
  }

  @override
  Future<void> close() async {
    try {
      await _ws.close();
    } on Object {
      // Een socket die niet wil sluiten is al dicht genoeg.
    }
    _client.close(force: true);
  }
}

AsrLiveTransport createAsrLiveTransport() => const IoAsrLiveTransport();
