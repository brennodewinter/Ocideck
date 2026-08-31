/// Download-als-bestand voor de webversie: biedt [downloadBytesToBrowser] aan
/// dat in de browser een download start (Blob + tijdelijk anchor). Op niet-web
/// is het een stub die `false` teruggeeft — daar schrijft de app gewoon naar
/// disk.
///
/// Dit is het rauwe primitief. Exportpaden gebruiken het niet rechtstreeks maar
/// via `services/download_delivery.dart`, dat één export ook echt als één
/// download aflevert.
library;

// `dart.library.js_interop` en niet `dart.library.html`: die laatste is onwaar
// onder dart2wasm, en dan koos deze regel stilzwijgend de stub — elke download
// zou op een wasm-build een lege huls zijn. De web-implementatie hieronder
// gebruikt alleen `dart:js_interop` en `package:web`, die allebei op wasm
// werken. Dezelfde vorm als clipboard_html.dart en presenter_fullscreen.dart.
// Wasm is nog geen bouwdoel (#1734), en dit is precies de val die dat later
// stil zou maken.
export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
