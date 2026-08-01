// Live presence over Matrix (`docs/design/SELF_ENCRYPTED_RELAY.md` §6, phase P-E):
// which slide each co-author is looking at, so everyone sees everyone (the model
// chosen 2026-08-01). It rides a **room state event** `nl.ocideck.presence` keyed
// by device id, so a device's latest position replaces its previous one instead
// of accumulating in the timeline — presence is a current fact, not history.
//
// Encrypted like everything else: the slide id is sealed with the epoch key, so
// the homeserver learns only *that* a device is present, never *where*. Presence
// is not authoritative — a wrong position misplaces a dot, nothing more — so it
// is sealed without a signature and opened without requiring one, exactly like an
// op. A device only trusts a presence event whose state key matches the sealed
// sender and whose sender is a verified peer in the directory; anything else is
// dropped fail-closed.

import '../utils/log.dart';
import 'collab_crypto.dart';
import 'matrix_client.dart';
import 'matrix_key_exchange.dart';

/// Where one peer device is looking, for the presence UI.
class PeerPresence {
  const PeerPresence({
    required this.userId,
    required this.deviceId,
    required this.slideId,
  });

  final String userId;
  final String deviceId;

  /// The id of the slide this peer is currently viewing/editing.
  final String slideId;
}

/// Announces this device's current slide and ingests peers' — the presence plane
/// of a Matrix session. Wire [handleSystemEvent] to the transport's
/// `onSystemEvent`; the app calls [announce] when the local selection changes.
class MatrixPresence {
  MatrixPresence({
    required MatrixClient client,
    required CollabCrypto crypto,
    required this.roomId,
    required this.directory,
  }) : _matrix = client,
       _e2ee = crypto;

  /// Room state event carrying one device's sealed current-slide id.
  static const presenceType = 'nl.ocideck.presence';

  final MatrixClient _matrix;
  final CollabCrypto _e2ee;
  final String roomId;
  final MatrixDeviceDirectory directory;

  final Map<String, PeerPresence> _peers = {};

  /// Presence that arrived before its epoch key or its sender's device keys were
  /// known — a joiner sees a peer's presence on the same sync as (or before) its
  /// key-share. Keyed by device, latest wins; [retryPending] re-opens them once a
  /// key may have installed, exactly like the snapshot channel.
  final Map<String, SealedEnvelope> _pending = {};

  /// Called after a peer's presence changes, so the provider can refresh the UI.
  void Function()? onChanged;

  /// The last slide this device announced, to skip a redundant re-send.
  String? _lastAnnounced;

  /// Every peer's latest known position (this device excluded).
  List<PeerPresence> get peers => _peers.values.toList();

  /// Announce that this device is now on [slideId]. Overwrites this device's own
  /// presence state; a no-op when unchanged. Sealed so the server sees ciphertext.
  Future<void> announce(String slideId) async {
    if (slideId == _lastAnnounced) return;
    _lastAnnounced = slideId;
    final sealed = await _e2ee.seal(
      {'slide': slideId},
      room: roomId,
      type: presenceType,
      signed: false,
    );
    await _matrix.sendStateEvent(
      roomId: roomId,
      type: presenceType,
      stateKey: _e2ee.deviceId,
      content: sealed.toContent(),
    );
  }

  /// Wire to `MatrixRelayTransport.onSystemEvent`. Records a peer's presence and
  /// tries to open it; a not-yet-openable one is buffered for [retryPending].
  Future<void> handleSystemEvent(MatrixTimelineEvent event) async {
    if (event.type != presenceType) return;
    final stateKey = event.stateKey;
    // Not a state event, or our own presence echoed back — ignore either way.
    if (stateKey == null || stateKey == _e2ee.deviceId) return;
    try {
      final sealed = SealedEnvelope.fromContent(event.content);
      // The state key is the device claiming this presence; it must equal the
      // sealed sender, or someone is writing under another device's key.
      if (sealed.senderDevice != stateKey) return;
      _pending[stateKey] = sealed; // latest wins; _tryOpen consumes it
      await _tryOpen(stateKey);
    } on Exception catch (e) {
      logWarning('collab.matrix.presence', e);
    }
  }

  /// Re-open any presence buffered before its key or sender was known. Call after
  /// a sync round that may have installed a key-share or learned a device.
  Future<void> retryPending() async {
    for (final device in _pending.keys.toList()) {
      await _tryOpen(device);
    }
  }

  Future<void> _tryOpen(String device) async {
    final sealed = _pending[device];
    if (sealed == null) return;
    final sender = directory.resolve(device);
    if (sender == null) return; // device not known yet — keep and retry
    try {
      final opened = await _e2ee.open(
        sealed,
        room: roomId,
        type: presenceType,
        sender: sender,
      );
      _pending.remove(device);
      final slide = opened['slide'];
      if (slide is! String) return;
      _peers[device] = PeerPresence(
        userId: directory.userOf(device) ?? '',
        deviceId: device,
        slideId: slide,
      );
      onChanged?.call();
    } on CollabCryptoException catch (e) {
      if (e.reason == 'unknown-epoch') return; // key not installed yet — keep
      _pending.remove(device); // a real failure (bad tag): drop fail-closed
      logWarning('collab.matrix.presence.open', e);
    }
  }
}
