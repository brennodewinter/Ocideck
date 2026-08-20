/// Leest de HTML-variant van het klembord, als die er is.
///
/// Flutter's `Clipboard.kTextPlain` is overal beschikbaar; HTML niet.
/// Windows en web levert het bestaande `pasteboard`-pakket; macOS en Linux
/// hebben daar geen lezer, dus die gaan via het eigen `ocideck/clipboard`-
/// kanaal. De bytes gaan daarna naar [htmlClipboardToMarkdown] — nooit naar
/// een renderer.
library;

import 'package:flutter/foundation.dart';

import 'clipboard_html_io.dart'
    if (dart.library.js_interop) 'clipboard_html_web.dart'
    as impl;

typedef ClipboardHtmlReader = Future<String?> Function();

/// Testnaad: onder `flutter test` is er geen host-plugin, en de echte
/// `NSPasteboard`/`GtkClipboard` valt buiten de suite. Een override houdt de
/// Dart-keten wél onder test.
@visibleForTesting
ClipboardHtmlReader? debugClipboardHtmlReader;

/// HTML van het systeemklembord, of `null` als die variant ontbreekt.
Future<String?> readClipboardHtml() async {
  final override = debugClipboardHtmlReader;
  if (override != null) return override();
  return impl.readClipboardHtmlImpl();
}
