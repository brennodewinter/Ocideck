// The protocol-neutral device directory — verifies, pins and caches peer device
// public keys. Shared by `MatrixKeyExchange` (which feeds it Matrix room state)
// and the future `XmppKeyExchange` (which will feed it signed-rot presence).
//
// Extracted from `matrix_key_exchange.dart` as build step 1 of
// `docs/design/XMPP_COLLAB_TRANSPORT.md` §11. The hardening below was demanded
// by the three review rounds (§5 brick 8, §7, findings SA-F2/SA-F3/NEW-2/NEW-3)
// and applies to the Matrix path too — the Matrix homeserver's admission was
// the only thing that made the unbounded, last-write-wins directory tolerable.
//
// The crypto itself — binding verification — is `CollabCrypto`'s
// (`DevicePublicKeys.verifyBinding`); this file only stores the result. The
// signed-rotation-epoch (rot) extension (§5.1) is deliberately NOT implemented
// here: it touches `collab_crypto.dart`'s binding/wrap format and must clear
// the ketenkeuring chain-review first (sub-plak 2). The seam for it is the
// identity-key equality check in [ingest] — a legitimate rot bump will arrive
// with a higher signed rot and a new identity, and will be accepted there once
// rot-signing lands.

import '../utils/log.dart';
import 'collab_crypto.dart';

/// A peer's identity in a session: its protocol-neutral address (a Matrix user
/// id `@user:hs`, an XMPP room/nick `room@conf/nick` — whatever the transport
/// uses to address a peer) and its binding-verified public keys (needed to open
/// its ops and verify its key-shares).
class PeerDevice {
  const PeerDevice({required this.peerAddress, required this.keys});

  /// The transport-specific address of this peer. The directory does not
  /// interpret it — it is the grouping key for the per-address device-id cap
  /// and the value the transport reads back to address a key-share.
  final String peerAddress;

  final DevicePublicKeys keys;
}

/// Verifies, pins and caches peer device public keys. Protocol-neutral: the
/// peer address is an opaque string the transport supplies. Shared by both key
/// exchanges (Matrix today, XMPP tomorrow).
///
/// Hardening (XMPP_COLLAB_TRANSPORT.md §5 brick 8, §7):
///   • The pre-approval pin-store is capped at [pinStoreCap] (≥ the occupant
///     cap, so a public room's legitimate devices are not denied keying —
///     NEW-2). The scarcity gate belongs on keying / the approved-set, not here.
///   • A per-address device-id limit ([perAddressDeviceCap]) bounds a single
///     nick minting unbounded ids — pinning stops overwrite, not creation (SA-F2).
///   • Pin-on-first-use: a known deviceId's identity fingerprint may not change
///     (refuses a silent identity swap — SA-F3). A clean seam for a signed-rot
///     bump is left for the crypto extension (§5.1, sub-plak 2).
class CollabDeviceDirectory {
  CollabDeviceDirectory({
    this.pinStoreCap = defaultPinStoreCap,
    this.perAddressDeviceCap = defaultPerAddressDeviceCap,
  });

  /// The pin-store cap: ≥ the MUC occupant cap (500, `xmpp_muc.dart`
  /// `_maxOccupants`), so a public room's legitimate devices are not denied
  /// keying (NEW-2). The scarcity gate is on keying / the approved-set, not here.
  static const defaultPinStoreCap = 500;

  /// Max device-ids per peer address. A few devices per user is legitimate;
  /// unbounded minting is not — pinning stops overwrite, not creation (SA-F2).
  static const defaultPerAddressDeviceCap = 8;

  final int pinStoreCap;
  final int perAddressDeviceCap;

  final Map<String, PeerDevice> _peers = {};

  /// peerAddress → number of distinct device-ids stored for that address.
  /// Only incremented when a *new* deviceId is added; an update of an existing
  /// deviceId (same identity) does not grow the count.
  final Map<String, int> _perAddressCount = {};

  /// Store [keys] for its device. Returns `true` if stored (or updated),
  /// `false` if refused. An entry is refused when:
  ///   • the identity→agreement binding does not verify (a relay swapping the
  ///     agreement key — §5.3);
  ///   • the deviceId is already known and the identity fingerprint differs
  ///     (a silent identity swap — SA-F3). The seam for a signed-rot bump
  ///     (§5.1) is this identity-key check: a legitimate rotation will arrive
  ///     with a higher signed rot and a new identity, accepted here once
  ///     rot-signing lands in sub-plak 2;
  ///   • the pin-store is full ([pinStoreCap] — NEW-2);
  ///   • the peer address already holds [perAddressDeviceCap] device-ids (SA-F2).
  Future<bool> ingest({
    required String peerAddress,
    required DevicePublicKeys keys,
  }) async {
    if (!await keys.verifyBinding()) {
      logWarning('collab.device.binding', keys.deviceId);
      return false;
    }

    final existing = _peers[keys.deviceId];
    if (existing != null) {
      // Pin-on-first-use: a known device's identity fingerprint may not change.
      // A silent identity swap is exactly what a relay taking over a deviceId
      // would produce (SA-F3). A legitimate rot bump (§5.1, sub-plak 2) will
      // arrive with a higher signed rot and a new identity — the exception goes
      // here once rot-signing lands.
      if (!_identityKeysEqual(existing.keys.identityKey, keys.identityKey)) {
        logWarning('collab.device.identitySwap', keys.deviceId);
        return false;
      }
      // Same identity: safe to update (e.g. a re-signed agreement key).
      _peers[keys.deviceId] = PeerDevice(peerAddress: peerAddress, keys: keys);
      return true;
    }

    // New deviceId — enforce caps before storing.
    if (_peers.length >= pinStoreCap) {
      logWarning('collab.device.pinStoreCap', keys.deviceId);
      return false;
    }
    final count = _perAddressCount[peerAddress] ?? 0;
    if (count >= perAddressDeviceCap) {
      logWarning('collab.device.perAddressCap', keys.deviceId);
      return false;
    }

    _peers[keys.deviceId] = PeerDevice(peerAddress: peerAddress, keys: keys);
    _perAddressCount[peerAddress] = count + 1;
    return true;
  }

  /// The verified public keys of [deviceId], or null if unknown — which drops
  /// the event fail-closed at the transport.
  DevicePublicKeys? resolve(String deviceId) => _peers[deviceId]?.keys;

  /// The protocol-neutral address that owns [deviceId] (a Matrix user id, an
  /// XMPP room/nick), for addressing a key-share, or null if unknown.
  String? addressOf(String deviceId) => _peers[deviceId]?.peerAddress;

  /// Every device id currently known — the authority walks this to key newcomers.
  Iterable<String> get knownDevices => _peers.keys;

  /// Every known peer, for the verification UI to list and fingerprint.
  Iterable<PeerDevice> get peers => _peers.values;
}

/// Byte-for-byte comparison of two identity keys — the pin-on-first-use check.
/// A [List<int>] identity key is small (32 bytes) so a linear scan is fine.
bool _identityKeysEqual(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
