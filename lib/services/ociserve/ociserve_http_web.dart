import 'ociserve_http.dart';
import 'ociserve_http_web_stub.dart'
    if (dart.library.js_interop) 'ociserve_web_session_browser.dart'
    as implementation;

export 'ociserve_http_web_stub.dart' show WebRefusingOciServeHttpTransport;

OciServeHttpTransport createOciServeHttpTransport() =>
    implementation.createBrowserAccountTransport();

OciServeHttpTransport createIntakeRespondentTransport(Uri base) =>
    implementation.createBrowserIntakeTransport(base);
