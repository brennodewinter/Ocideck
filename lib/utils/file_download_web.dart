import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'log.dart';

/// Start in de browser een download van [content] onder de naam [fileName].
///
/// Werkt binnen de strikte CSP van web/index.html: een `blob:`-URL op een
/// anchor met `download` is een download-navigatie, geen fetch, dus
/// `connect-src 'self'` blokkeert hem niet. De object-URL wordt direct na de
/// click weer vrijgegeven.
bool downloadTextFile(String fileName, String content) {
  try {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: 'text/markdown;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (e) {
    logWarning('downloadTextFile: browser download failed', e);
    return false;
  }
}
