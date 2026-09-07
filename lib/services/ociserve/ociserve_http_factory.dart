import 'ociserve_http.dart';
import 'ociserve_http_io.dart'
    if (dart.library.html) 'ociserve_http_web.dart'
    as implementation;

OciServeHttpTransport createOciServeHttpTransport() =>
    implementation.createOciServeHttpTransport();
