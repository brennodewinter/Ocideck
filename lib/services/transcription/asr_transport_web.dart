// De web-transport voor de ASR-serverroute (#2524). De browser is hier de
// netwerkgrens: `fetch` met CORS beslist wat werkelijk het netwerk op mag,
// en de body gaat via `AbortController` stopbaar op pad. De door de gate
// gekozen [AiResolveStrategy] is op web alleen nog een toestemming, geen
// route — pinnen kan in een browser niet; dat is precies waarom de gate
// web-regels heeft (`insecureHttpOnWeb`, geen userInfo).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../utils/log.dart';
import 'asr_transport.dart';

final class WebAsrTransport implements AsrTransport {
  const WebAsrTransport({this.maxResponseBytes = 16 * 1024 * 1024});

  /// Harde grens aan de responsebody; er wordt niet meer gebufferd.
  final int maxResponseBytes;

  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 15),
  }) {
    final controller = web.AbortController();
    final completer = Completer<AsrResponse>();
    final timer = Timer(timeout, () => controller.abort());

    () async {
      try {
        final init = web.RequestInit(
          method: method,
          signal: controller.signal,
          // De serverroute is een gekozen, geen same-origin endpoint —
          // `cors` is de eerlijke modus: de browser toetst preflight bij
          // de Authorization- en Content-Type-headers die we zetten.
          mode: 'cors',
          credentials: 'omit',
        );
        if (headers.isNotEmpty) {
          final h = web.Headers();
          // Geen tear-off (`h.set`): extension-type interop-leden mogen
          // dat niet onder dart2js.
          headers.forEach((k, v) => h.set(k, v));
          init.headers = h;
        }
        if (body != null) init.body = body.toJS;
        final response = await web.window
            .fetch(url.toString().toJS, init)
            .toDart;
        // `bodyUsed` is niet nodig — de response is vers en ongelezen;
        // arrayBuffer() leent zich voor de byte-cap (een losgeslagen
        // server mag de tab niet vullen).
        final buf = (await response.arrayBuffer().toDart).toDart;
        if (buf.lengthInBytes > maxResponseBytes) {
          throw const AsrRequestException('respons groter dan het maximum');
        }
        completer.complete(AsrResponse(response.status, _decodeUtf8(buf)));
      } on AsrRequestException catch (e, s) {
        completer.completeError(e, s);
      } catch (e) {
        // AbortError = de gebruiker stopte; de engine vertaalt dat.
        if (controller.signal.aborted) {
          completer.completeError(const AsrRequestException('afgebroken'));
        } else {
          logError('WebAsrTransport.send: verzoek mislukt', e);
          completer.completeError(const AsrRequestException('netwerk'));
        }
      } finally {
        timer.cancel();
      }
    }();

    return AsrSendHandle(
      done: completer.future,
      cancel: () => controller.abort(),
    );
  }
}

/// UTF-8 met vervanging bij kapotte tekens (`fatal` blijft uit) — de
/// serverroute mag nooit op een byte stuklopen; de parser bepaalt daarna
/// of de inhoud zinnig is.
String _decodeUtf8(ByteBuffer buf) =>
    web.TextDecoder().decode(buf.asUint8List().toJS);

AsrTransport createAsrTransport() => const WebAsrTransport();
