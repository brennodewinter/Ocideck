import 'runtime_flags_io.dart'
    if (dart.library.html) 'runtime_flags_web.dart'
    as impl;

/// True when running under `flutter test`.
bool get isFlutterTest => impl.isFlutterTest;
