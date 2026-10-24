// Platformseam voor het ophalen van config.js: desktop doet een NetGuard-
// gepinde GET, web faalt dicht tot er een expliciete CSP-/socketbeslissing
// ligt (dezelfde houding als `xmpp_frame_transport_web`).
export 'jitsi_config_web.dart' if (dart.library.io) 'jitsi_config_io.dart';
