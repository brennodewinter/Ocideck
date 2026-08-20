import 'package:pasteboard/pasteboard.dart';

import '../utils/html_to_markdown.dart';
import '../utils/log.dart';

/// Web: `navigator.clipboard.read()` op `text/html`, via het pasteboard-pakket.
/// Faalt de leesvraag (toestemming, browser), dan `null` — de val is platte tekst.
Future<String?> readClipboardHtmlImpl() async {
  try {
    final html = await Pasteboard.html;
    if (html == null || html.isEmpty) return null;
    if (html.length > kClipboardHtmlMaxChars) return null;
    return html;
  } catch (e) {
    logWarning('Pasteboard.html failed', e);
    return null;
  }
}
