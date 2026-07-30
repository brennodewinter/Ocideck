// The public surface of the collaboration module (`docs/design/COLLABORATION.md`
// §5). One import for the whole layer: the typed op model, the transport seam
// and its implementations, the session authority, and the wire codec. The state
// layer reaches the module through the `TabInfo.collabSession` seam (§5.7); the
// transports are the module's capabilities a session is constructed over —
// `LoopbackTransport` for the single-machine case and tests, and
// `WebdavAsyncTransport` for asynchronous co-authoring over WebDAV (Fase 0.5,
// #989). Real-time Matrix (§6) joins this list later behind the same seam.

export 'collab_codec.dart';
export 'collab_log_store.dart';
export 'collab_session.dart';
export 'collab_snapshot.dart';
export 'collab_transport.dart';
export 'deck_op.dart';
export 'webdav_async_transport.dart';
