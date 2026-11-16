// De desktop-transport voor de live-ASR-route (#2525). De WebSocket-
// upgrade is een gewone HTTP-GET, dus de pinning uit `asr_resolve_io`
// geldt hier onverkort: resolve per gate-strategie, socket pinnen op
// het gevalideerde adres via `customClient` — een DNS-rebind kan de
// stream zo niet alsnog naar een intern adres zetten.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/log.dart';
import '../../utils/pinned_http_client.dart';
import 'asr_live_transport.dart';
import 'asr_live_limits.dart';
import 'asr_resolve_io.dart';

final class IoAsrLiveTransport implements AsrLiveTransport {
  const IoAsrLiveTransport({
    this.connectTimeout = const Duration(seconds: 15),
    this.limits = const LiveResponseLimits(),
  });

  final Duration connectTimeout;
  final LiveResponseLimits limits;

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
      return _IoLiveSocket(ws, client, limits);
    } catch (e, s) {
      client.close(force: true);
      logError('IoAsrLiveTransport.connect', e, s);
      throw const AsrLiveException('verbinding mislukt');
    }
  }
}

final class _IoLiveSocket implements AsrLiveSocket {
  _IoLiveSocket(this._ws, this._client, LiveResponseLimits limits) {
    _inbound = BoundedLiveInput(
      limits: limits,
      onLimit: () => unawaited(close()),
    );
    _subscription = _ws.cast<Object>().listen(
      _inbound.add,
      onError: _inbound.addError,
      onDone: _inbound.close,
    );
  }

  final WebSocket _ws;
  final HttpClient _client;
  late final BoundedLiveInput _inbound;
  late final StreamSubscription<Object> _subscription;
  bool _closed = false;

  @override
  Stream<Object> get messages => _inbound.stream;

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
    _ws.add(frame);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _inbound.close();
    await _subscription.cancel();
    try {
      await _ws.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Een socket die niet wil sluiten is al dicht genoeg.
    } finally {
      _client.close(force: true);
    }
  }
}

AsrLiveTransport createAsrLiveTransport() => const IoAsrLiveTransport();
