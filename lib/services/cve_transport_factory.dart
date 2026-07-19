// Selects the platform CVE transport: the SSRF-pinned dart:io implementation on
// desktop/mobile, and the no-op web stub on the web build (CVE lookup is
// desktop-only). Mirrors the info_safety/platform conditional-export seams.
export 'cve_transport_web.dart' if (dart.library.io) 'cve_transport_io.dart';
