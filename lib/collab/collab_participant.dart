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

/// One device in a session, as the verification dialog lists it.
class CollabParticipant {
  const CollabParticipant({
    required this.userId,
    required this.deviceId,
    required this.fingerprint,
    required this.isSelf,
  });

  final String userId;
  final String deviceId;

  /// The readable fingerprint of this device's identity key — see
  /// [deviceFingerprint].
  final String fingerprint;

  /// True for this device (the one running the app), shown first and labelled so.
  final bool isSelf;
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
