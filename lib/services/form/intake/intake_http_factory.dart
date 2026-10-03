import 'intake_http.dart';
import 'intake_http_io.dart'
    if (dart.library.js_interop) 'intake_http_web.dart'
    as implementation;

/// De HTTP-laag van dit platform: gepind op het bureaublad, geweigerd op het web.
IntakeHttp createIntakeHttp() => implementation.createIntakeHttp();
