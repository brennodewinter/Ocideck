// Tests for the protocol-neutral device directory
// (`lib/collab/collab_device_directory.dart`, XMPP_COLLAB_TRANSPORT.md §5 brick
// 8, §7). The directory verifies, pins and caches peer device public keys, and
// is shared by the Matrix key exchange and the future XMPP key exchange. The
// adversarial cases below mirror §8: a known-device identity swap is refused
// (SA-F3), a directory flood hits the cap (NEW-2), and a per-nick id flood is
// bounded (SA-F2).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_device_directory.dart';

void main() {
  test('a valid device is stored and resolvable', () async {
    final dir = CollabDeviceDirectory();
    final keys = await _deviceKeys('alice');

    final stored = await dir.ingest(peerAddress: '@alice:hs', keys: keys);

    expect(stored, isTrue);
    expect(dir.resolve(keys.deviceId)?.deviceId, 'alice');
    expect(dir.addressOf(keys.deviceId), '@alice:hs');
  });

  test('a device with an unverifiable binding is refused', () async {
    // A relay swaps the agreement key: the identity signature no longer covers
    // it, so the directory refuses to store it.
    final good = await _deviceKeys('alice');
    final other = await _deviceKeys('bob');
    final swapped = DevicePublicKeys(
      deviceId: good.deviceId,
      identityKey: good.identityKey,
      agreementKey: other.agreementKey,
      agreementSignature: good.agreementSignature,
      rot: good.rot,
    );

    final dir = CollabDeviceDirectory();
    final stored = await dir.ingest(peerAddress: '@alice:hs', keys: swapped);

    expect(stored, isFalse);
    expect(dir.resolve(good.deviceId), isNull);
  });

  group('pin-on-first-use', () {
    test('a known device identity swap is refused', () async {
      // SA-F3: once a deviceId is pinned, a later presence claiming the same
      // deviceId but a different identity key is refused — a silent identity
      // swap is exactly what a relay taking over a deviceId would produce.
      final original = await _deviceKeys('dev1', salt: 1);
      final impostor = await _deviceKeys('dev1', salt: 2);

      expect(
        impostor.identityKey,
        isNot(equals(original.identityKey)),
        reason: 'the two devices must have different identity keys',
      );

      final dir = CollabDeviceDirectory();
      await dir.ingest(peerAddress: '@alice:hs', keys: original);
      final swapped = await dir.ingest(
        peerAddress: '@alice:hs',
        keys: impostor,
      );

      expect(swapped, isFalse);
      expect(
        dir.resolve('dev1')?.identityKey,
        equals(original.identityKey),
        reason: 'the original identity is retained, not the impostor',
      );
    });

    test('same identity, updated agreement key is accepted', () async {
      // A legitimate device that rotates its agreement key (re-signed by the
      // same identity) is not an identity swap — the pin is on the identity
      // fingerprint, not the agreement key. The rot-signed rotation epoch
      // (§5.1, sub-plak 2) will build on this seam.
      final original = await _deviceKeys('dev1', salt: 1);
      // Same Ed25519 seed (same identity), different X25519 seed (new agreement).
      final rotated = await _deviceKeysWithSeeds(
        'dev1',
        ed25519Seed: _seed('dev1', 1),
        x25519Seed: _seed('dev1', 99),
      );

      expect(
        rotated.identityKey,
        equals(original.identityKey),
        reason: 'same identity key',
      );
      expect(
        rotated.agreementKey,
        isNot(equals(original.agreementKey)),
        reason: 'different agreement key',
      );

      final dir = CollabDeviceDirectory();
      await dir.ingest(peerAddress: '@alice:hs', keys: original);
      final updated = await dir.ingest(peerAddress: '@alice:hs', keys: rotated);

      expect(updated, isTrue);
      expect(
        dir.resolve('dev1')?.agreementKey,
        equals(rotated.agreementKey),
        reason: 'the updated agreement key is stored',
      );
    });
  });

  group('caps', () {
    test('a directory flood hits the pin-store cap', () async {
      // NEW-2: the pre-approval pin-store cap must be ≥ the occupant cap so
      // legitimate devices on a public room are not denied keying. A flood
      // past the cap is refused — the scarcity gate belongs on keying / the
      // approved-set, not here, but the store is still memory-bounded.
      final dir = CollabDeviceDirectory(pinStoreCap: 4);
      for (var i = 0; i < 4; i++) {
        final keys = await _deviceKeys('dev$i', salt: i);
        expect(await dir.ingest(peerAddress: '@user$i:hs', keys: keys), isTrue);
      }

      // The 5th device is refused — the cap is hit.
      final fifth = await _deviceKeys('dev4', salt: 4);
      final stored = await dir.ingest(peerAddress: '@user4:hs', keys: fifth);

      expect(stored, isFalse);
      expect(dir.resolve('dev4'), isNull);
      expect(dir.knownDevices.length, 4);
    });

    test('the default pin-store cap is at least the occupant cap', () {
      // The MUC occupant cap is 500 (xmpp_muc.dart _maxOccupants). The pin-store
      // cap must be ≥ that, or ~43 nicks × a few ids could fill it and deny
      // keying to legitimate devices on a public room (NEW-2).
      expect(
        CollabDeviceDirectory.defaultPinStoreCap,
        greaterThanOrEqualTo(500),
      );
    });

    test('a per-nick id flood is bounded', () async {
      // SA-F2: pinning stops overwrite (a known deviceId cannot change
      // identity), not creation — so a single nick could otherwise mint
      // unbounded new device-ids. The per-address device-id cap bounds this.
      final dir = CollabDeviceDirectory(perAddressDeviceCap: 3);
      for (var i = 0; i < 3; i++) {
        final keys = await _deviceKeys('dev$i', salt: i);
        expect(
          await dir.ingest(peerAddress: '@alice:hs', keys: keys),
          isTrue,
          reason: 'device $i under the per-nick limit',
        );
      }

      // The 4th device-id from the same nick is refused.
      final fourth = await _deviceKeys('dev3', salt: 3);
      final stored = await dir.ingest(peerAddress: '@alice:hs', keys: fourth);

      expect(stored, isFalse);
      expect(dir.resolve('dev3'), isNull);
    });

    test(
      'a different nick can still add devices after one nick is full',
      () async {
        // The per-nick cap is per-address, not global — a second nick is not
        // penalised because the first nick filled its quota.
        final dir = CollabDeviceDirectory(perAddressDeviceCap: 2);
        for (var i = 0; i < 2; i++) {
          final keys = await _deviceKeys('dev$i', salt: i);
          await dir.ingest(peerAddress: '@alice:hs', keys: keys);
        }

        final bobKeys = await _deviceKeys('bobdev', salt: 9);
        final stored = await dir.ingest(peerAddress: '@bob:hs', keys: bobKeys);

        expect(stored, isTrue);
        expect(dir.resolve('bobdev')?.deviceId, 'bobdev');
      },
    );

    test(
      'remove decrements the per-address count — cap is not permanent (#1422)',
      () async {
        // Na 8 device-rotaties per peer-address bereikte de oude code
        // permanent de cap — remove() verlaagt de teller zodat een vertrokken
        // device plaats maakt voor een nieuw.
        final dir = CollabDeviceDirectory(perAddressDeviceCap: 3);
        for (var i = 0; i < 3; i++) {
          final keys = await _deviceKeys('dev$i', salt: i);
          expect(
            await dir.ingest(peerAddress: '@alice:hs', keys: keys),
            isTrue,
          );
        }

        // De cap is bereikt — een 4e device wordt geweigerd.
        final fourth = await _deviceKeys('dev3', salt: 3);
        expect(
          await dir.ingest(peerAddress: '@alice:hs', keys: fourth),
          isFalse,
        );

        // Verwijder een device — de teller daalt.
        dir.remove('dev0');
        expect(dir.resolve('dev0'), isNull);

        // Nu kan een nieuw device worden toegevoegd — de cap is niet permanent.
        final newKeys = await _deviceKeys('dev3', salt: 3);
        expect(
          await dir.ingest(peerAddress: '@alice:hs', keys: newKeys),
          isTrue,
          reason: 'after remove, the per-address count is decremented',
        );
      },
    );

    test('remove is a no-op for an unknown device', () async {
      final dir = CollabDeviceDirectory();
      // Geen crash, geen wijziging.
      dir.remove('nonexistent');
      expect(dir.knownDevices, isEmpty);
    });
  });
}

/// The public keys of a deterministic device for [label], with an optional
/// [salt] so multiple devices with the same id but different identities can be
/// created.
Future<DevicePublicKeys> _deviceKeys(String label, {int salt = 1}) async {
  final keys = await CollabDeviceKeys.fromSeeds(
    deviceId: label,
    ed25519Seed: _seed(label, salt),
    x25519Seed: _seed(label, salt + 1),
  );
  return keys.publicKeys(rot: 0);
}

Future<DevicePublicKeys> _deviceKeysWithSeeds(
  String label, {
  required List<int> ed25519Seed,
  required List<int> x25519Seed,
}) async {
  final keys = await CollabDeviceKeys.fromSeeds(
    deviceId: label,
    ed25519Seed: ed25519Seed,
    x25519Seed: x25519Seed,
  );
  return keys.publicKeys(rot: 0);
}

List<int> _seed(String label, int salt) {
  final bytes = Uint8List(32);
  final name = label.codeUnits;
  for (var i = 0; i < 32; i++) {
    bytes[i] = (name[i % name.length] + salt + i) & 0xff;
  }
  return bytes;
}
