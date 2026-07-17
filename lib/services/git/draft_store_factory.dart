// Selects the platform draft store: real files on desktop, the browser's
// key/value store on web.
//
// §8.3 originally specified an IndexedDB draft here. It does not need one: a
// deck's working copy is text through and through (deck.md is markdown, both
// sidecar codecs return JSON strings), so a key/value store holds it — and one
// this repository already tests, rather than browser interop it cannot test at
// all. See draft_store_web.dart.
export 'draft_store_web.dart' if (dart.library.io) 'draft_store_io.dart';
