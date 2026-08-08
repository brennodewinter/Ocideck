// Establishing the session's keys over the room (`docs/design/SELF_ENCRYPTED_RELAY.md`
// §4.3, §8, phase P-D). This is the Matrix plumbing that turns the relay from
// "keys pre-shared" (the P-C test crutch) into "keys established over the wire":
//
//   • each device publishes its public keys as `nl.ocideck.device` room state, so
//     peers can address key-shares to it and open its signed ops;
//   • peers' device state is ingested into a [CollabDeviceDirectory], which
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
import 'collab_device_directory.dart';
import 'matrix_client.dart';

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
  final CollabDeviceDirectory directory;
  final DevicePublicKeys _own;

  /// This device's own public keys — the verification UI fingerprints them as the
  /// "you" entry co-authors compare against.
  DevicePublicKeys get ownKeys => _own;

  /// Every known peer device, verified into the directory.
  Iterable<PeerDevice> get peers => directory.peers;

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
    // Wraps are in the same order as [members] (CollabCrypto.rekey preserves
    // order); the wrap itself carries no cleartext recipient (§5.1 N3), so we
    // address by the member we asked for, not by a field on the wrap.
    for (var i = 0; i < members.length; i++) {
      if (await _sendWrap(result.wraps[i], members[i].deviceId)) {
        _keyed.add(members[i].deviceId);
      }
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
      if (await _sendWrap(wrap, deviceId)) _keyed.add(deviceId);
    }
  }

  /// Send one key-share to its recipient's user; returns whether it was sent
  /// (false when the recipient's user id is not yet known — retried next round).
  /// [recipientDeviceId] is the device id to address the to-device message to —
  /// the wrap itself carries no cleartext recipient (§5.1 N3).
  Future<bool> _sendWrap(WrappedKey wrap, String recipientDeviceId) async {
    final userId = directory.addressOf(recipientDeviceId);
    if (userId == null) {
      logWarning('collab.matrix.keyshare.unaddressable', recipientDeviceId);
      return false;
    }
    await _matrix.sendToDevice(
      type: keyshareType,
      messages: {
        userId: {recipientDeviceId: wrap.toJson()},
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
    await directory.ingest(peerAddress: event.sender, keys: keys);
  }

  /// Wire to `MatrixRelayTransport.onToDevice`. Installs an epoch key from a
  /// key-share, verifying it against the sender's **directory-held** identity —
  /// never keys carried in the (relay-deliverable) message itself.
  ///
  /// The blinded wrap (§5.1 N3) carries no cleartext sender device-id, so the
  /// sender is resolved from the to-device event's Matrix user id: the directory
  /// supplies the candidate devices for that user, and `installEpochKey`
  /// trial-verifies the signature against each — only the genuine sender's key
  /// passes.
  Future<void> handleToDevice(MatrixToDeviceEvent event) async {
    if (event.type != keyshareType) return;
    final WrappedKey wrap;
    try {
      wrap = WrappedKey.fromJson(event.content);
    } on Exception catch (e) {
      logWarning('collab.matrix.keyshare.parse', e);
      return;
    }
    final candidates = directory.devicesForAddress(event.sender).toList();
    if (candidates.isEmpty) {
      logWarning('collab.matrix.keyshare.unknownSender', event.sender);
      return;
    }
    for (final sender in candidates) {
      try {
        await _e2ee.installEpochKey(wrap, sender);
        return; // installed successfully
      } on CollabCryptoException {
        continue; // wrong sender device or bad wrap — try next candidate
      }
    }
    logWarning('collab.matrix.keyshare.noMatchingDevice', event.sender);
  }
}
