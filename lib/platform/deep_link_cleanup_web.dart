import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `history.replaceState` werkt de adresbalk bij zonder navigatie —
/// precies wat een afgehandelde `?deck=`-deeplink nodig heeft: de
/// browser-geschiedenis blijft kloppen (terug gaat naar waar je vandaan
/// kwam), maar een herlading haalt het deck niet opnieuw binnen.
void replaceAddressBar(Uri uri) {
  web.window.history.replaceState(null, '', uri.toString());
}
