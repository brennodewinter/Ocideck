// Selects the platform Matrix egress: the SSRF-pinned dart:io implementation on
// desktop, and the browser-fetch implementation on web. Mirrors the
// `git_transport`/`cve_transport` conditional-export seams. The `MatrixHttpTransport`
// interface itself lives in `matrix_client.dart`; this only picks the impl.
//
// `createMatrixHttpTransport(server)` builds the right transport for a
// [MatrixServer], to be handed to a `MatrixClient`.
export 'matrix_http_transport_web.dart'
    if (dart.library.io) 'matrix_http_transport_io.dart';
