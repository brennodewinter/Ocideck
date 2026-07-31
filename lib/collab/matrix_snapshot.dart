// Delivering the session baseline over Matrix (`docs/design/SELF_ENCRYPTED_RELAY.md`
// §6.3, §9, phase P-D). A joiner needs the authority's [CollabSnapshot] — the
// slide list at a version — to share its slide-id space before any op applies
// (§5.5). Matrix events cap at ~64 KiB, so a full-deck snapshot cannot ride one
// event; it is **sealed once and then chunked** across `nl.ocideck.snapshot.chunk`
// events, and reassembled on the far side.
//
// Sealed once, chunked after: the whole snapshot is encrypted as a single
// [SealedEnvelope] (so its AEAD tag covers the entire baseline — a dropped or
// reordered chunk makes the reassembled blob fail to open, fail-closed), and only
// the resulting ciphertext-blob is split across events. Each chunk event carries
// plaintext routing metadata (`id`, index, count) and one slice of the blob; the
// content itself never leaves ciphertext. Reassembly is by chunk id, opened and
// signature-verified against the authority's directory-held keys (a snapshot is
// authoritative, so the signature is required — anti-impersonation, P3).
//
// Wire [handleSystemEvent] to the transport's `onSystemEvent` hook; the authority
// calls [sendSnapshot]. Fail-closed and bounded: a malformed, oversized, or
// un-openable snapshot is logged and dropped, and the pending-chunk buffers are
// capped so a hostile homeserver cannot exhaust memory by flooding chunks.

import 'dart:async';
import 'dart:convert';

import '../utils/log.dart';
import 'collab_crypto.dart';
import 'collab_snapshot.dart';
import 'matrix_client.dart';
import 'matrix_key_exchange.dart';

class MatrixSnapshotChannel {
  MatrixSnapshotChannel({
    required MatrixClient client,
    required CollabCrypto crypto,
    required this.roomId,
    required this.directory,
    this.maxChunkChars = 48000,
    this.maxChunks = 512,
    this.maxPendingSnapshots = 4,
  }) : _matrix = client,
       _e2ee = crypto;

  /// The event type carrying one slice of a sealed snapshot blob.
  static const chunkEventType = 'nl.ocideck.snapshot.chunk';

  /// The type bound into the snapshot's AEAD (its carriage is the chunk events).
  static const snapshotType = 'nl.ocideck.snapshot';

  final MatrixClient _matrix;
  final CollabCrypto _e2ee;
  final String roomId;
  final MatrixDeviceDirectory directory;

  /// Roughly the plaintext chars per chunk event — kept well under the ~64 KiB
  /// event cap after JSON + base64 overhead.
  final int maxChunkChars;

  /// Cap on chunks per snapshot and on snapshots buffered at once — a hostile
  /// homeserver must not be able to exhaust memory by flooding chunk events.
  final int maxChunks;
  final int maxPendingSnapshots;

  int _out = 0;
  final Map<String, Map<int, String>> _pending = {};

  /// Snapshots that have fully reassembled but not yet opened — because the epoch
  /// key had not arrived (a joiner sees the snapshot chunks before its key-share).
  /// [retryPending] re-attempts these once a key may have been installed.
  final Map<String, SealedEnvelope> _assembled = {};
  final _first = Completer<CollabSnapshot>();

  /// Completes with the first fully-reassembled, opened snapshot — what a joiner
  /// awaits before starting its session.
  Future<CollabSnapshot> get firstSnapshot => _first.future;

  /// Whether a snapshot has been opened yet — a non-blocking check for a join
  /// loop that syncs until it is true.
  bool get hasSnapshot => _first.isCompleted;

  /// Re-attempt opening any snapshot that reassembled before its epoch key was
  /// available. Call after a sync round that may have installed a key-share.
  Future<void> retryPending() async {
    for (final id in _assembled.keys.toList()) {
      await _tryOpen(id);
    }
  }

  /// Authority: seal [snapshot] and send it as chunked events. The AEAD covers
  /// the whole baseline; the signature makes it verifiably the authority's.
  Future<void> sendSnapshot(CollabSnapshot snapshot) async {
    final sealed = await _e2ee.seal(
      {'snapshot': jsonEncode(snapshot.toJson())},
      room: roomId,
      type: snapshotType,
      signed: true,
    );
    final blob = jsonEncode(sealed.toContent());
    final id = 'snap-${_e2ee.deviceId}-${_out++}';
    final chunks = _split(blob, maxChunkChars);
    for (var i = 0; i < chunks.length; i++) {
      await _matrix.sendEvent(
        roomId: roomId,
        type: chunkEventType,
        content: {'id': id, 'i': i, 'n': chunks.length, 'data': chunks[i]},
      );
    }
  }

  /// Wire to `MatrixRelayTransport.onSystemEvent`. Buffers snapshot chunks and,
  /// once a whole snapshot is present, reassembles, opens and yields it.
  Future<void> handleSystemEvent(MatrixTimelineEvent event) async {
    if (event.type != chunkEventType) return;
    try {
      final id = event.content['id'];
      final index = event.content['i'];
      final count = event.content['n'];
      final data = event.content['data'];
      if (id is! String ||
          index is! int ||
          count is! int ||
          data is! String ||
          count <= 0 ||
          count > maxChunks ||
          index < 0 ||
          index >= count) {
        logWarning('collab.matrix.snapshot.badChunk', '$id');
        return;
      }
      final parts = _pending.putIfAbsent(id, () => {});
      if (_pending.length > maxPendingSnapshots) {
        _pending.remove(id);
        logWarning('collab.matrix.snapshot.tooManyPending', id);
        return;
      }
      parts[index] = data;
      if (parts.length < count) return; // still waiting for chunks
      _pending.remove(id);
      await _assemble(id, count, parts);
    } on Exception catch (e) {
      logWarning('collab.matrix.snapshot.chunk', e);
    }
  }

  Future<void> _assemble(String id, int count, Map<int, String> parts) async {
    final blob = StringBuffer();
    for (var i = 0; i < count; i++) {
      blob.write(parts[i]!);
    }
    final decoded = jsonDecode(blob.toString());
    if (decoded is! Map<String, Object?>) {
      logWarning('collab.matrix.snapshot.notObject', id);
      return;
    }
    _assembled[id] = SealedEnvelope.fromContent(decoded);
    await _tryOpen(id);
  }

  /// Open a reassembled snapshot. Keeps it buffered when it cannot be opened yet
  /// because the sender is unknown or the epoch key has not arrived (a joiner sees
  /// the chunks before its key-share) — [retryPending] re-attempts it. Any other
  /// failure (a genuinely bad tag/payload) drops it fail-closed.
  Future<void> _tryOpen(String id) async {
    if (_first.isCompleted) {
      _assembled.remove(id);
      return;
    }
    final sealed = _assembled[id];
    if (sealed == null) return;
    final sender = directory.resolve(sealed.senderDevice);
    if (sender == null) return; // sender not known yet — keep and retry
    try {
      final envelope = await _e2ee.open(
        sealed,
        room: roomId,
        type: snapshotType,
        sender: sender,
        requireSignature: true,
      );
      _assembled.remove(id);
      final raw = envelope['snapshot'];
      if (raw is! String) {
        logWarning('collab.matrix.snapshot.noPayload', id);
        return;
      }
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) {
        logWarning('collab.matrix.snapshot.badPayload', id);
        return;
      }
      if (!_first.isCompleted) _first.complete(CollabSnapshot.fromJson(json));
    } on CollabCryptoException catch (e) {
      if (e.reason == 'unknown-epoch') return; // key not installed yet — keep
      _assembled.remove(id); // a real failure (bad tag/signature): drop
      logWarning('collab.matrix.snapshot.open', e);
    }
  }

  List<String> _split(String s, int size) {
    if (s.length <= size) return [s];
    final out = <String>[];
    for (var i = 0; i < s.length; i += size) {
      out.add(s.substring(i, i + size > s.length ? s.length : i + size));
    }
    return out;
  }
}
