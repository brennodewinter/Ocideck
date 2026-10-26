// De transportnaad voor de live-ASR-route (§4.3, #2525): een WebSocket
// in plaats van een request/response. Welke route mag, besliste
// `AsrServerGate.evaluateLive` al; de transport krijgt de
// [AiResolveStrategy] mee en verzint er geen eigen bij.
//
// Drie helften: `_io` pint de socket via `NetGuard.connectPinned` door
// een `customClient` mee te geven aan `WebSocket.connect` (de upgrade
// is een gewone HTTP-GET op die client) en kan een `Authorization`-
// header zetten; `_web` gebruikt de browser-WebSocket — CORS, origin en
// TLS zijn dáár de grens, en aangepaste headers bestaan niet, dus een
// sleutel-eisende server is op web eerlijk onbereikbaar; `_stub`
// weigert netjes.
import 'dart:async';
import 'dart:typed_data';

import 'package:network_guard/network_guard.dart' show AiResolveStrategy;

import 'asr_live_transport_stub.dart'
    if (dart.library.io) 'asr_live_transport_io.dart'
    if (dart.library.js_interop) 'asr_live_transport_web.dart'
    as impl;

export 'package:network_guard/network_guard.dart' show AiResolveStrategy;

/// Fout van de live-transportlaag — connect geweigerd of verbroken.
/// De gate-weigering gebeurt eerder, in `AsrServerGate`.
final class AsrLiveException implements Exception {
  const AsrLiveException(this.message);

  final String message;

  @override
  String toString() => 'AsrLiveException: $message';
}

/// Een open live-socket. De naad spreekt bewust in ruwe frames — de
/// protocolvorm (`vosk-ws-1`) is het werk van de engine erboven.
abstract class AsrLiveSocket {
  /// Inkomende frames: `String` voor tekstframes, `Uint8List` voor
  /// binaire. Eindigt als de socket sluit; een netwerkbreuk eindigt hem
  /// met een fout, tenzij de helft dat onmogelijk kan onderscheiden
  /// (de browser meldt weigeringen bewust éénvormig).
  Stream<Object> get messages;

  /// De sluitcode als de socket dicht is (`null` = nog open of de
  /// helft kent geen code). 1000 is de normale afsluiting.
  int? get closeCode;

  /// Stuur een binair audioframe. Dicht = weggegooid, nooit een fout.
  void sendBytes(Uint8List frame);

  /// Stuur een tekstframe (config, eof). Dicht = weggegooid.
  void sendText(String frame);

  /// Sluit de socket; idempotent. In-flight verzoeken om te sluiten
  /// voltooien zonder extra frames uit te zenden.
  Future<void> close();
}

/// Injecteerbare transportnaad. Tests leveren een fake zodat geen test
/// het netwerk raakt; de platformhelften dwingen pinning respectievelijk
/// browsergrenzen af.
abstract class AsrLiveTransport {
  /// Open een socket. [headers] gaan op io in de handshake (oa.
  /// `Authorization`); op web negeert de browser ze — de engine beslist
  /// wat dat betekent, de transport liegt er niet over.
  Future<AsrLiveSocket> connect({
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers,
  });
}

AsrLiveTransport createAsrLiveTransport() => impl.createAsrLiveTransport();
