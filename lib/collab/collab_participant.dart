// What the verification UI shows for a live collaboration session
// (SELF_ENCRYPTED_RELAY.md §4.3): one entry per device, with the fingerprint of
// its identity key to compare out-of-band.
//
// The binding check (identity key signs the agreement key) already runs before a
// peer enters the directory, so it defeats a relay that swaps *one* key. What it
// cannot catch is a homeserver that consistently substitutes *both* keys for a
// device it fully impersonates — only a human comparing the identity-key
// fingerprint over a trusted channel (reading it aloud, a signed message) can.
// This is that fingerprint.

/// Where a peer device stands against the local trust store (Blok A). The self
/// device is always [verified] — you do not verify yourself. A peer starts
/// [unverified] (trust-on-first-use, shown with a dismissible banner), becomes
/// [verified] once its fingerprint is pinned, and turns to [mismatch] if a
/// device we pinned later presents a *different* identity key — the one state
/// that must never be dismissed, because it is the signature of an impersonating
/// relay (§5.3).
enum TrustState { unverified, verified, mismatch }

/// One device in a session, as the verification dialog lists it.
class CollabParticipant {
  const CollabParticipant({
    required this.userId,
    required this.deviceId,
    required this.identityKey,
    required this.fingerprint,
    required this.isSelf,
    this.trust = TrustState.unverified,
  });

  final String userId;
  final String deviceId;

  /// The raw Ed25519 identity key bytes — what the trust store pins, and what the
  /// [fingerprint] is a readable rendering of. Carried so the verification UI can
  /// pin without recomputing it from the fingerprint string.
  final List<int> identityKey;

  /// The readable fingerprint of this device's identity key — see
  /// [deviceFingerprint].
  final String fingerprint;

  /// True for this device (the one running the app), shown first and labelled so.
  final bool isSelf;

  /// This device's standing against the local trust store — see [TrustState].
  final TrustState trust;

  CollabParticipant copyWith({TrustState? trust}) => CollabParticipant(
    userId: userId,
    deviceId: deviceId,
    identityKey: identityKey,
    fingerprint: fingerprint,
    isSelf: isSelf,
    trust: trust ?? this.trust,
  );
}

/// A readable fingerprint of an Ed25519 identity key: uppercase hex in groups of
/// four, the value co-authors read to each other to confirm no key was swapped.
/// The identity key *is* the identity, so the full key is shown rather than a
/// truncated hash — there is no shorter value to collide against.
String deviceFingerprint(List<int> identityKey) {
  final hex = [
    for (final b in identityKey) (b & 0xff).toRadixString(16).padLeft(2, '0'),
  ].join().toUpperCase();
  final groups = <String>[];
  for (var i = 0; i < hex.length; i += 4) {
    groups.add(hex.substring(i, i + 4 > hex.length ? hex.length : i + 4));
  }
  return groups.join(' ');
}
