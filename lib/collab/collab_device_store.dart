// Persisting a device's collaboration key material (`docs/design/SELF_ENCRYPTED_RELAY.md`
// §8, phase P-D). A device's Ed25519 identity and X25519 agreement keys must
// survive an app restart, or every launch would be an "unverified new device" to
// collaborators. Rather than export the private keys out of [CollabCrypto], the
// device is defined by two random 32-byte **seeds**: [CollabDeviceKeys.fromSeeds]
// deterministically rebuilds the exact same keypairs from them, so persisting the
// seeds is equivalent to persisting the keys — and the reconstruction is provably
// identical (a round-trip test pins it). The seeds are secret and live only in the
// keychain via `SecretStore` (§4.3); losing them costs a device its identity,
// which re-onboarding regenerates.

import 'dart:convert';
import 'dart:math';

import '../services/secret_store.dart';
import 'collab_crypto.dart';
import 'collab_recovery_key.dart';

/// The persisted form of a device's key material: an id and the two 32-byte
/// seeds its keypairs derive from.
class CollabDeviceSeeds {
  const CollabDeviceSeeds({
    required this.deviceId,
    required this.ed25519Seed,
    required this.x25519Seed,
  });

  final String deviceId;
  final List<int> ed25519Seed;
  final List<int> x25519Seed;

  /// A fresh device identity: two independent 32-byte seeds from the platform
  /// CSPRNG ([Random.secure]). Any 32 bytes is a valid seed for both algorithms
  /// (Ed25519 hashes it; X25519 clamps it), so no rejection sampling is needed.
  factory CollabDeviceSeeds.generate(String deviceId) {
    final rng = Random.secure();
    List<int> seed() => [for (var i = 0; i < 32; i++) rng.nextInt(256)];
    return CollabDeviceSeeds(
      deviceId: deviceId,
      ed25519Seed: seed(),
      x25519Seed: seed(),
    );
  }

  /// Rebuild the device's keypairs — deterministic, so the same seeds always
  /// yield the same identity.
  Future<CollabDeviceKeys> toDeviceKeys() => CollabDeviceKeys.fromSeeds(
    deviceId: deviceId,
    ed25519Seed: ed25519Seed,
    x25519Seed: x25519Seed,
  );

  /// This identity as a portable recovery key (Blok B). The device id is *not*
  /// carried: recovery restores the identity keypairs, which a new device binds
  /// to its own Matrix device id on import (§4.3). See [collab_recovery_key.dart].
  String recoveryKey() => encodeRecoveryKey(ed25519Seed, x25519Seed);

  String toStored() => jsonEncode({
    'v': 1,
    'device': deviceId,
    'ed': base64.encode(ed25519Seed),
    'x': base64.encode(x25519Seed),
  });

  /// Decode a value written by [toStored]. Throws [FormatException] on anything
  /// malformed so the caller can fall back to regenerating rather than run with a
  /// half-built identity.
  factory CollabDeviceSeeds.fromStored(String stored) {
    final json = jsonDecode(stored);
    if (json is! Map<String, Object?>) {
      throw const FormatException('device seeds are not a JSON object');
    }
    final device = json['device'];
    final ed = json['ed'];
    final x = json['x'];
    if (device is! String || ed is! String || x is! String) {
      throw const FormatException('device seeds missing a field');
    }
    return CollabDeviceSeeds(
      deviceId: device,
      ed25519Seed: base64.decode(ed),
      x25519Seed: base64.decode(x),
    );
  }
}

/// Load this account's device keys from the keychain, or create and persist a
/// fresh set. Reuses stored seeds only when they belong to [deviceId]; a
/// different (or absent) stored device means a fresh login, which gets — and
/// persists — a new identity. Unparseable stored seeds are treated as absent.
Future<CollabDeviceKeys> loadOrCreateDeviceKeys({
  required SecretStore secretStore,
  required String homeserver,
  required String userId,
  required String deviceId,
}) async {
  final stored = await secretStore.readCollabDeviceSeeds(homeserver, userId);
  if (stored != null) {
    try {
      final seeds = CollabDeviceSeeds.fromStored(stored);
      if (seeds.deviceId == deviceId) return await seeds.toDeviceKeys();
    } on FormatException {
      // Corrupt entry: fall through and regenerate.
    }
  }
  final fresh = CollabDeviceSeeds.generate(deviceId);
  await secretStore.writeCollabDeviceSeeds(
    homeserver,
    userId,
    fresh.toStored(),
  );
  return fresh.toDeviceKeys();
}

/// Read the stored device seeds for [homeserver]/[userId], or null when none
/// exist yet or the entry is unreadable. Used to show the recovery key for
/// export (Blok B) without minting a new identity the way [loadOrCreateDeviceKeys]
/// would.
Future<CollabDeviceSeeds?> readDeviceSeeds({
  required SecretStore secretStore,
  required String homeserver,
  required String userId,
}) async {
  final stored = await secretStore.readCollabDeviceSeeds(homeserver, userId);
  if (stored == null) return null;
  try {
    return CollabDeviceSeeds.fromStored(stored);
  } on FormatException {
    return null;
  }
}

/// Restore an identity from a [recoveryKey] on this device (Blok B). The
/// recovered seeds are bound to the current [deviceId] and written to the
/// keychain, so the next [loadOrCreateDeviceKeys] reuses them — the device keeps
/// its own Matrix device id but adopts the recovered identity keypairs (and thus
/// the same fingerprint and provenance-signing key). Throws
/// [RecoveryKeyException] on a malformed or mistyped key, before anything is
/// written.
Future<CollabDeviceKeys> importRecoveryKey({
  required SecretStore secretStore,
  required String homeserver,
  required String userId,
  required String deviceId,
  required String recoveryKey,
}) async {
  final recovered = decodeRecoveryKey(recoveryKey);
  final seeds = CollabDeviceSeeds(
    deviceId: deviceId,
    ed25519Seed: recovered.ed25519Seed,
    x25519Seed: recovered.x25519Seed,
  );
  await secretStore.writeCollabDeviceSeeds(
    homeserver,
    userId,
    seeds.toStored(),
  );
  return seeds.toDeviceKeys();
}
