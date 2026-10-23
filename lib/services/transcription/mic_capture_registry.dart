// Welke opnamebron dit platform registreert. Desktop krijgt microfoon
// en systeemgeluid; web krijgt de browserroutes. De eerste passende
// voorwaarde wint, dus een VM met beide libraries houdt de io-helft.
export 'mic_capture_registry_stub.dart'
    if (dart.library.io) 'mic_capture_registry_io.dart'
    if (dart.library.js_interop) 'mic_capture_registry_web.dart';
