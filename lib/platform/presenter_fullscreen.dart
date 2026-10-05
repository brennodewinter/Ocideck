import 'package:flutter/foundation.dart';

import 'presenter_fullscreen_io.dart'
    if (dart.library.js_interop) 'presenter_fullscreen_web.dart'
    as impl;

/// Testnaad: onder `flutter test` is er geen native venster of browserdocument,
/// dus de echte implementatie doet daar niets zichtbaars. Een override maakt de
/// volledigschermaanroepen observeerbaar (zie de dubbelscherm-tests in
/// `fullscreen_presenter_test.dart`).
@visibleForTesting
Future<void> Function(bool fullscreen)? debugSetPresenterFullscreen;

/// Zie [debugSetPresenterFullscreen].
@visibleForTesting
bool Function()? debugIsPresenterFullscreen;

/// Zet de app in of uit volledig scherm voor de presentatiemodus.
///
/// Op desktop stuurt dit het native venster aan (nativeapi); op web de
/// browser-Fullscreen-API. Beide zijn best-effort: een platform dat het niet
/// ondersteunt mag het presenteren nooit blokkeren (zie de aanroepers, die
/// hier omheen gewoon de presenter-route openen).
Future<void> setPresenterFullscreen(bool fullscreen) =>
    (debugSetPresenterFullscreen ?? impl.setPresenterFullscreen)(fullscreen);

/// Of het venster/document momenteel in volledig scherm staat.
///
/// macOS en de browser onderscheppen Escape op platformniveau om het volledig
/// scherm te verlaten — de toets bereikt Flutter dus niet. De presentator
/// pollt deze functie om dat te detecteren en de presentatie alsnog te
/// verlaten, zodat Escape doet wat de documentatie belooft (#1862).
bool isPresenterFullscreen() =>
    (debugIsPresenterFullscreen ?? impl.isPresenterFullscreen)();
