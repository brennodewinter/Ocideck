// Platform-selected factory for the local CVE database.
//
// The whole feature is desktop-only: it needs a filesystem for a multi-hundred-
// megabyte index, and a 550 MB download has no business in a browser tab. The
// io half does the real work; the web half reports itself unsupported so the
// settings screen can hide the feature instead of offering a button that cannot
// do anything.
export 'local_cve_database_api.dart';
export 'local_cve_database_io.dart'
    if (dart.library.html) 'local_cve_database_web.dart';
