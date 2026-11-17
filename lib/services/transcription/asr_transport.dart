// De transportnaad voor de ASR-serverroute (§4.3, #2524). Anders dan de
// AI-laag kan deze bytes versturen (multipart audio) en is elk verzoek
// afbreekbaar — `transcribe` op een honderd MB upload moet stopbaar zijn.
//
// De transport is de enige plek die écht het netwerk op gaat. Welke route
// mag, besliste `AsrServerGate` al; de transport krijgt de
// [AiResolveStrategy] mee en verzint er geen eigen bij. Drie helften:
// `_io` pint de socket via `NetGuard.connectPinned`, `_web` gebruikt
// `fetch`+`AbortController` (daar is CORS de grens), `_stub` weigert
// netjes op platforms zonder beide.
import 'dart:typed_data';
import 'dart:convert';

import 'package:network_guard/network_guard.dart' show AiResolveStrategy;

import 'asr_transport_stub.dart'
    if (dart.library.io) 'asr_transport_io.dart'
    if (dart.library.js_interop) 'asr_transport_web.dart'
    as impl;

export 'package:network_guard/network_guard.dart' show AiResolveStrategy;

/// Resultaat van één uitwisseling — status plus body als tekst. De engine
/// begrenst en parseert hem; de transport garandeert alleen dat er nooit
/// meer dan `maxResponseBytes` gebufferd is.
final class AsrResponse {
  const AsrResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;

  bool get isOk => statusCode >= 200 && statusCode < 300;
  Uint8List get bytes => Uint8List.fromList(utf8.encode(body));
  Map<String, String> get headers => const {};
  Uri? get finalUrl => null;
}

/// Raw bounded transport bytes. JSON callers decode once, on first access;
/// media callers retain binary audio without a lossy UTF-8 round trip.
final class AsrByteResponse implements AsrResponse {
  AsrByteResponse(
    this.statusCode,
    Uint8List bytes, {
    Map<String, String> headers = const {},
    this.finalUrl,
  }) : bytes = bytes.asUnmodifiableView(),
       headers = Map.unmodifiable(headers);

  @override
  final int statusCode;
  @override
  final Uint8List bytes;
  @override
  final Map<String, String> headers;
  @override
  final Uri? finalUrl;
  @override
  late final String body = utf8.decode(bytes, allowMalformed: true);
  @override
  bool get isOk => statusCode >= 200 && statusCode < 300;
}

/// Een lopend verzoek: zijn uitkomst plus de knop die hem afbreekt.
/// `cancel` is idempotent en maakt [done] waar met een afbreekfout — welke
/// precies is platformwerk; de engine vertaalt hem naar [Cancelled].
final class AsrSendHandle {
  const AsrSendHandle({required this.done, required this.cancel});

  final Future<AsrResponse> done;
  final void Function() cancel;
}

/// Netwerk- of protocolfout van de transportlaag. Geen gate-weigering —
/// die gebeurt vóór dit punt, in `AsrServerGate`.
final class AsrRequestException implements Exception {
  const AsrRequestException(this.message);

  final String message;

  @override
  String toString() => 'AsrRequestException: $message';
}

/// Injecteerbare transportnaad. Tests leveren een fake zodat geen test het
/// netwerk raakt; de platformhelften dwingen pinning respectievelijk
/// abort af.
abstract class AsrTransport {
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    required Uint8List? body,
    Map<String, String> headers,
    Duration timeout,
  });
}

AsrTransport createAsrTransport({int maxResponseBytes = 16 * 1024 * 1024}) =>
    impl.createAsrTransport(maxResponseBytes: maxResponseBytes);
