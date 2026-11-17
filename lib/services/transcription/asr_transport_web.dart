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
        final buf = await _readBody(response, controller);
        completer.complete(
          AsrByteResponse(
            response.status,
            buf,
            finalUrl: Uri.tryParse(response.url),
            headers: {
              for (final name in [
                'content-type',
                'content-length',
                'location',
                'etag',
                'last-modified',
              ])
                name: ?response.headers.get(name),
            },
          ),
        );
      } on AsrRequestException catch (e, s) {
        completer.completeError(e, s);
      } catch (e) {
        // AbortError = de gebruiker stopte; de engine vertaalt dat.
        if (controller.signal.aborted) {
          completer.completeError(const AsrRequestException('afgebroken'));
        } else {
          logWarning('WebAsrTransport.send: netwerkfout (${e.runtimeType})');
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

  /// Toets vóór bewaren; Content-Length kan ontbreken of onjuist zijn.
  Future<Uint8List> _readBody(
    web.Response response,
    web.AbortController controller,
  ) async {
    final body = response.body;
    if (body == null) return Uint8List(0);
    final reader = body.getReader() as web.ReadableStreamDefaultReader;
    // Eén groeiende buffer: bewaar geen object/buffer per klein netwerkchunk.
    final bytes = BytesBuilder(copy: true);
    var complete = false;
    try {
      while (true) {
        final step = await reader.read().toDart;
        if (step.done) {
          complete = true;
          return bytes.takeBytes();
        }
        final value = step.value;
        if (value == null) continue;
        final chunk = (value as JSUint8Array).toDart;
        if (chunk.length > maxResponseBytes - bytes.length) {
          throw const AsrRequestException('respons groter dan het maximum');
        }
        bytes.add(chunk);
      }
    } catch (e) {
      if (e is AsrRequestException || controller.signal.aborted) rethrow;
      // Onze cleanup-abort hieronder is geen gebruikersannulering.
      throw const AsrRequestException('netwerk');
    } finally {
      if (!complete) {
        controller.abort();
        // Cleanup mag de oorspronkelijke limiet-/netwerkfout niet vervangen.
        try {
          unawaited(reader.cancel().toDart.catchError((Object _) => null));
        } on Object {
          // De reader kan door een browserfout al losgelaten zijn.
        }
      }
      try {
        reader.releaseLock();
      } on Object {
        // Een cleanupfout vervangt de oorspronkelijke uitkomst niet.
      }
    }
  }
}

AsrTransport createAsrTransport({int maxResponseBytes = 16 * 1024 * 1024}) =>
    WebAsrTransport(maxResponseBytes: maxResponseBytes);
