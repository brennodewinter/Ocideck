import 'presenter_fullscreen_io.dart'
    if (dart.library.js_interop) 'presenter_fullscreen_web.dart'
    as impl;

/// Zet de app in of uit volledig scherm voor de presentatiemodus.
///
/// Op desktop stuurt dit het native venster aan (window_manager); op web de
/// browser-Fullscreen-API. Beide zijn best-effort: een platform dat het niet
/// ondersteunt mag het presenteren nooit blokkeren (zie de aanroepers, die
/// hier omheen gewoon de presenter-route openen).
Future<void> setPresenterFullscreen(bool fullscreen) =>
    impl.setPresenterFullscreen(fullscreen);
