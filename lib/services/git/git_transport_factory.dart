// Selects the platform git transport: the SSRF-pinned dart:io implementation on
// desktop, and the browser-fetch implementation on web. Unlike the CVE
// transport, the web side is a real implementation rather than a stub — git
// storage is offered on web (§4.4), with the REST data plane only.
//
// Mirrors the cve_transport/platform conditional-export seams.
export 'git_transport_web.dart' if (dart.library.io) 'git_transport_io.dart';
