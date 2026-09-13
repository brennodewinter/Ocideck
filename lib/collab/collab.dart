// The public surface of the collaboration module (`docs/design/COLLABORATION.md`
// §5). One import for the whole layer: the typed op model, the transport seam
// and its implementations, the session authority, and the wire codec. The state
// layer reaches the module through the `TabInfo.collabSession` seam (§5.7); the
// transports are the module's capabilities a session is constructed over —
// `LoopbackTransport` for the single-machine case and tests, and
// `WebdavAsyncTransport` for asynchronous co-authoring over WebDAV (Fase 0.5,
// #989). XMPP joins this list behind the same seam.

export 'collab_codec.dart';
export 'collab_crypto.dart';
export 'collab_device_directory.dart';
export 'collab_device_store.dart';
export 'collab_participant.dart';
export 'collab_deck_diff.dart';
export 'collab_log_store.dart';
export 'collab_session.dart';
export 'collab_session_controller.dart';
export 'collab_session_launch.dart';
export 'collab_recovery_key.dart';
export 'collab_snapshot.dart';
export 'collab_trust_store.dart';
export 'collab_transport.dart';
export 'deck_op.dart';
export 'handover_coordinator.dart';
export 'webdav_async_transport.dart';
export '../xmpp/companion_demux.dart';
export '../xmpp/xmpp_chat.dart';
export '../xmpp/xmpp_collab_launch.dart';
export '../xmpp/xmpp_key_exchange.dart';
export '../xmpp/xmpp_presence_beacon.dart';
export '../xmpp/xmpp_snapshot.dart';
export '../xmpp/xmpp_transport.dart';
