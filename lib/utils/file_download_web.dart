import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'log.dart';

/// Biedt [bytes] in de browser aan als download onder de naam [fileName].
///
/// Werkt binnen de strikte CSP van web/index.html: een `blob:`-URL op een
/// anchor met `download` is een download-navigatie, geen fetch, dus
/// `connect-src 'self'` blokkeert hem niet. De object-URL wordt direct na de
/// click weer vrijgegeven.
///
/// `true` betekent dat het *aanbieden* lukte — niet dat het bestand in de
/// downloadmap staat. Dat kan de pagina niet weten: een klik op een
/// download-anker meldt niets terug, ook niet wanneer de browser de download
/// tegenhoudt. Meer dan dit valt er niet te meten, en daarom vuurt
/// `deliverAsDownload` er nooit meer dan één per export af (#1902).
bool downloadBytesToBrowser(String fileName, Uint8List bytes, String mimeType) {
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
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
    logWarning('downloadBytesToBrowser: browser download failed', e);
    return false;
  }
}
