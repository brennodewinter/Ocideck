import 'ociserve_http.dart';
import 'ociserve_http_io.dart'
    if (dart.library.js_interop) 'ociserve_http_web.dart'
    as implementation;

OciServeHttpTransport createOciServeHttpTransport() =>
    implementation.createOciServeHttpTransport();

OciServeHttpTransport createIntakeRespondentTransport(Uri base) =>
    implementation.createIntakeRespondentTransport(base);
