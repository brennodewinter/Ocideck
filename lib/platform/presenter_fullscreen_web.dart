import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../utils/log.dart';

/// Web: de browser-Fullscreen-API. `requestFullscreen` moet vanuit een
/// gebruikersgebaar komen (de presenteer-knop is dat), anders weigert de
/// browser stil — daarom is dit best-effort en blokkeert een weigering het
/// presenteren niet; de presenter-route vult sowieso de hele viewport.
Future<void> setPresenterFullscreen(bool fullscreen) async {
  try {
    if (fullscreen) {
      await web.document.documentElement?.requestFullscreen().toDart;
    } else if (web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (e) {
    logWarning('setPresenterFullscreen: browser weigerde fullscreen', e);
  }
}

bool isPresenterFullscreen() {
  try {
    return web.document.fullscreenElement != null;
  } catch (e) {
    logWarning('isPresenterFullscreen: browser-API niet beschikbaar', e);
    return false;
  }
}
