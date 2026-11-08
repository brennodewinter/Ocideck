import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web: luister naar `message`-events van het insluitende frame.
///
/// `event.origin` is de enige betrouwbare herkomst (Referrer-Policy is
/// `no-referrer`), en `reply` post naar `event.source` met die origin als
/// target — een `'*'`-antwoord zou elke luisteraar op die pagina mee
/// laten lezen. Dat de app hier kan luisteren betekent al dat ze
/// ingesloten is; wie dat mag staat bij `frame-ancestors` op de server.
void startMarkdownListener(
  void Function(
    Object? data,
    String origin,
    bool sourceIsParent,
    void Function(Map<String, Object?>) reply,
  )
  onEvent,
) {
  web.window.addEventListener(
    'message',
    ((web.Event event) {
      final e = event as web.MessageEvent;
      final source = e.source;
      onEvent(
        e.data.dartify(),
        e.origin,
        identical(source, web.window.parent),
        (reply) {
          // Afzenders op dit kanaal zijn altijd vensters (de ouder die
          // ons insluit); de cast is een view, geen runtime-check.
          final win = source as web.Window?;
          win?.postMessage(
            reply.jsify(),
            web.WindowPostMessageOptions(targetOrigin: e.origin),
          );
        },
      );
    }).toJS,
  );
}
