import 'ociserve_http.dart';
import 'ociserve_public_http_io.dart'
    if (dart.library.js_interop) 'ociserve_public_http_web.dart'
    as implementation;

OciServeHttpTransport createPublicOciServeHttpTransport() =>
    implementation.createPublicOciServeHttpTransport();
