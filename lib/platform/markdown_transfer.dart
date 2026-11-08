import 'markdown_transfer_io.dart'
    if (dart.library.js_interop) 'markdown_transfer_web.dart'
    as impl;

/// Registreer de `message`-luisteraar van de postMessage-browserkoppeling
/// (#2827). De callback krijgt de platte event-data, `event.origin`, of
/// `event.source` de ouder van dit frame is, en een `reply` die naar die
/// source post met `targetOrigin = origin` — nooit `'*'`.
///
/// Op desktop is dit een no-op: zonder browser is er geen postMessage.
void startMarkdownListener(
  void Function(
    Object? data,
    String origin,
    bool sourceIsParent,
    void Function(Map<String, Object?>) reply,
  )
  onEvent,
) => impl.startMarkdownListener(onEvent);
