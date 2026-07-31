// Establishing the session's keys over the room (`docs/design/SELF_ENCRYPTED_RELAY.md`
// §4.3, §8, phase P-D). This is the Matrix plumbing that turns the relay from
// "keys pre-shared" (the P-C test crutch) into "keys established over the wire":
//
//   • each device publishes its public keys as `nl.ocideck.device` room state, so
//     peers can address key-shares to it and open its signed ops;
//   • peers' device state is ingested into a [MatrixDeviceDirectory], which
//     verifies the identity→agreement binding before trusting a key (a relay that
//     swaps the agreement key breaks the signature and is refused — §5.3);
//   • the authority hands the epoch key to each member with an encrypted to-device
//     key-share, and a member installs the one addressed to it.
//
// The cryptography itself — wrapping, signing, unwrapping — is entirely
// [CollabCrypto]'s (P-A); this file only carries it over [MatrixClient] (P-B). Wire
// [handleSystemEvent] and [handleToDevice] to the transport's `onSystemEvent` /
// `onToDevice` hooks so the single sync loop feeds the exchange. Fail-closed
// throughout: a malformed device event, an unverifiable binding, or a key-share
// from a sender whose keys are not (yet) known is logged and dropped, never
// trusted from the message itself.

import '../utils/log.dart';
import 'collab_crypto.dart';
import 'matrix_client.dart';

/// A peer's identity in a session: its Matrix user id (needed to address a
/// to-device key-share) and its binding-verified public keys (needed to open its
/// ops and verify its key-shares).
class PeerDevice {
  const PeerDevice({required this.userId, required this.keys});

  final String userId;
  final DevicePublicKeys keys;
}

/// Verifies and caches peer device public keys learned from `nl.ocideck.device`
/// room state; backs the relay transport's `PeerResolver`.
class MatrixDeviceDirectory {
  final Map<String, PeerDevice> _peers = {};

  /// Store [keys] for its device **only if** the identity key genuinely signs the
  /// agreement key for that device id (§4.3). An unverifiable binding is dropped:
  /// it is exactly what a relay substituting the agreement key would produce.
  Future<void> ingest({
    required String userId,
    required DevicePublicKeys keys,
  }) async {
    if (!await keys.verifyBinding()) {
      logWarning('collab.matrix.device.binding', keys.deviceId);
      return;
    }
    _peers[keys.deviceId] = PeerDevice(userId: userId, keys: keys);
  }

  /// The verified public keys of [deviceId], or null if unknown — which drops the
  /// event fail-closed at the transport.
  DevicePublicKeys? resolve(String deviceId) => _peers[deviceId]?.keys;

  /// The Matrix user id that owns [deviceId], for addressing a to-device
  /// key-share, or null if unknown.
  String? userOf(String deviceId) => _peers[deviceId]?.userId;

  /// Every device id currently known — the authority walks this to key newcomers.
  Iterable<String> get knownDevices => _peers.keys;
}

/// Publishes this device's keys, ingests peers', and distributes/installs epoch
/// keys over Matrix. Construct one per participant; wire [handleSystemEvent] and
/// [handleToDevice] to the transport hooks.
class MatrixKeyExchange {
  MatrixKeyExchange({
    required MatrixClient client,
    required CollabCrypto crypto,
    required this.roomId,
    required this.directory,
    required DevicePublicKeys ownKeys,
  }) : _matrix = client,
       _e2ee = crypto,
       _own = ownKeys;

  static const deviceEventType = 'nl.ocideck.device';
  static const keyshareType = 'nl.ocideck.keyshare';

  final MatrixClient _matrix;
  final CollabCrypto _e2ee;
  final String roomId;
  final MatrixDeviceDirectory directory;
  final DevicePublicKeys _own;

  /// Devices this authority has already handed the current epoch key to, so a
  /// newcomer is keyed exactly once per epoch. Reset on [distributeEpoch].
  final Set<String> _keyed = {};

  /// Publish this device's public keys as room state, keyed by device id (§6.1),
  /// so peers can address key-shares to it and verify its signed ops.
  Future<void> publishDeviceKeys() => _matrix.sendStateEvent(
    roomId: roomId,
    type: deviceEventType,
    stateKey: _e2ee.deviceId,
    content: _own.toJson(),
  );

  /// Authority: begin a fresh epoch and hand its key to each of [members] via an
  /// encrypted to-device key-share. Each member must already be in [directory]
  /// (its device state synced) so its user id can be addressed; an unaddressable
  /// member is skipped and logged rather than silently keyed out.
  Future<void> distributeEpoch(List<DevicePublicKeys> members) async {
    final result = await _e2ee.rekey(members);
    _keyed.clear(); // a new epoch: everyone must be (re)keyed
    for (final wrap in result.wraps) {
      if (await _sendWrap(wrap)) _keyed.add(wrap.recipientDevice);
    }
  }

  /// Authority: hand the **current** epoch key to any known device not yet keyed
  /// this epoch (a newcomer that just published its device state). Idempotent —
  /// call it after each sync round; devices already keyed are skipped.
  Future<void> ensureKeyed() async {
    for (final deviceId in directory.knownDevices) {
      if (deviceId == _e2ee.deviceId || _keyed.contains(deviceId)) continue;
      final member = directory.resolve(deviceId);
      if (member == null) continue;
      final wrap = await _e2ee.wrapEpochTo(member);
      if (await _sendWrap(wrap)) _keyed.add(deviceId);
    }
  }

  /// Send one key-share to its recipient's user; returns whether it was sent
  /// (false when the recipient's user id is not yet known — retried next round).
  Future<bool> _sendWrap(WrappedKey wrap) async {
    final userId = directory.userOf(wrap.recipientDevice);
    if (userId == null) {
      logWarning('collab.matrix.keyshare.unaddressable', wrap.recipientDevice);
      return false;
    }
    await _matrix.sendToDevice(
      type: keyshareType,
      messages: {
        userId: {wrap.recipientDevice: wrap.toJson()},
      },
    );
    return true;
  }

  /// Wire to `MatrixRelayTransport.onSystemEvent`. Ingests a device-state event
  /// into the directory; ignores every other system event.
  Future<void> handleSystemEvent(MatrixTimelineEvent event) async {
    if (event.type != deviceEventType) return;
    final DevicePublicKeys keys;
    try {
      keys = DevicePublicKeys.fromJson(event.content);
    } on Exception catch (e) {
      logWarning('collab.matrix.device.parse', e);
      return;
    }
    // The state key must be the device the keys claim to be, or a relay could
    // file one device's keys under another's state.
    if (keys.deviceId != event.stateKey) {
      logWarning('collab.matrix.device.mismatch', '${event.stateKey}');
      return;
    }
    await directory.ingest(userId: event.sender, keys: keys);
  }

  /// Wire to `MatrixRelayTransport.onToDevice`. Installs an epoch key from a
  /// key-share, verifying it against the sender's **directory-held** identity —
  /// never keys carried in the (relay-deliverable) message itself.
  Future<void> handleToDevice(MatrixToDeviceEvent event) async {
    if (event.type != keyshareType) return;
    final WrappedKey wrap;
    try {
      wrap = WrappedKey.fromJson(event.content);
    } on Exception catch (e) {
      logWarning('collab.matrix.keyshare.parse', e);
      return;
    }
    final sender = directory.resolve(wrap.senderDevice);
    if (sender == null) {
      logWarning('collab.matrix.keyshare.unknownSender', wrap.senderDevice);
      return;
    }
    try {
      await _e2ee.installEpochKey(wrap, sender);
    } on CollabCryptoException catch (e) {
      logWarning('collab.matrix.keyshare.install', e);
    }
  }
}
