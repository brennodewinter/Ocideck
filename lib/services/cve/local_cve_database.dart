// ── lib/services/cve/ ────────────────────────────────────────────────────────
// The *offline* CVE corpus: downloading the CVE List V5 bulk release
// (cve_bulk_ingest.dart), turning one record into the fields the picker shows
// (cve_record_parser.dart), keeping it searchable on disk (local_cve_index.dart)
// and offering all that behind one platform-selected facade (this file and its
// `_api`/`_io`/`_web` halves).
//
// The *online* lookup is deliberately not here: `../cve_search_service.dart`
// with `../cve_transport*.dart` sits one directory up, because it shares
// nothing with the corpus but the subject. If your change is about a network
// request, it belongs there; if it is about the local index, it belongs here.
// Neither holds the UI wiring (lib/state/local_cve_provider.dart) or the record
// types (lib/models/local_cve_*.dart). File by file: docs/SOURCE_MAP.md.
// ─────────────────────────────────────────────────────────────────────────────
//
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
