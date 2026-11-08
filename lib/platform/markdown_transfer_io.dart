/// Desktop-implentatie van [startMarkdownListener]: geen browser, geen
/// postMessage — niets om naar te luisteren. Zie markdown_transfer.dart.
void startMarkdownListener(
  void Function(
    Object? data,
    String origin,
    bool sourceIsParent,
    void Function(Map<String, Object?>) reply,
  )
  onEvent,
) {}
