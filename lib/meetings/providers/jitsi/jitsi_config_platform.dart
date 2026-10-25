// Platformseam voor het ophalen van config.js: desktop doet een NetGuard-
// gepinde GET. Web haalt via de browser (`jitsi_config_web`) — pinnen kan
// daar niet; de schemegrens en de pagina-CSP zijn de grens (#2544).
export 'jitsi_config_web.dart' if (dart.library.io) 'jitsi_config_io.dart';
