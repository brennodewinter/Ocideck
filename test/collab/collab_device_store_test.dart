// Tests for device-key persistence (`lib/collab/collab_device_store.dart`,
// SELF_ENCRYPTED_RELAY.md §8, phase P-D). The security-relevant guarantee is that
// storing two seeds is equivalent to storing the keys: [CollabDeviceKeys.fromSeeds]
// rebuilds the *same* identity from the same seeds — pinned here — so a persisted
// device survives a restart, and a fresh login gets a new identity.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_device_store.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollabDeviceSeeds', () {
    test('generate yields two distinct 32-byte seeds each time', () {
      final a = CollabDeviceSeeds.generate('dev');
      final b = CollabDeviceSeeds.generate('dev');
      expect(a.ed25519Seed.length, 32);
      expect(a.x25519Seed.length, 32);
      expect(a.ed25519Seed, isNot(a.x25519Seed));
      expect(a.ed25519Seed, isNot(b.ed25519Seed), reason: 'fresh randomness');
    });

    test('survives a stored round-trip', () {
      final s = CollabDeviceSeeds.generate('dev-1');
      final back = CollabDeviceSeeds.fromStored(s.toStored());
      expect(back.deviceId, 'dev-1');
      expect(back.ed25519Seed, s.ed25519Seed);
      expect(back.x25519Seed, s.x25519Seed);
    });

    test('the same seeds rebuild the same identity (deterministic)', () async {
      final s = CollabDeviceSeeds.generate('dev');
      final a = await (await s.toDeviceKeys()).publicKeys();
      final b = await (await s.toDeviceKeys()).publicKeys();
      expect(b.identityKey, a.identityKey);
      expect(b.agreementKey, a.agreementKey);
      expect(await b.verifyBinding(), isTrue);
    });

    test('fromStored rejects a malformed value', () {
      expect(
        () => CollabDeviceSeeds.fromStored('not json'),
        throwsFormatException,
      );
      expect(
        () => CollabDeviceSeeds.fromStored('{"v":1,"device":"d"}'),
        throwsFormatException,
      );
    });
  });

  group('loadOrCreateDeviceKeys', () {
    late SecretStore store;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      store = SecretStore(
        storage: const FlutterSecureStorage(),
        canStore: true,
      );
    });

    test('creates, persists, and reloads the same identity', () async {
      final first = await loadOrCreateDeviceKeys(
        secretStore: store,
        homeserver: 'https://hs.example',
        userId: '@a:hs.example',
        deviceId: 'DEV1',
      );
      final firstPub = await first.publicKeys();

      final again = await loadOrCreateDeviceKeys(
        secretStore: store,
        homeserver: 'https://hs.example',
        userId: '@a:hs.example',
        deviceId: 'DEV1',
      );
      final againPub = await again.publicKeys();

      expect(againPub.identityKey, firstPub.identityKey);
      expect(againPub.agreementKey, firstPub.agreementKey);
    });

    test('a different device id (a fresh login) regenerates', () async {
      final one = await loadOrCreateDeviceKeys(
        secretStore: store,
        homeserver: 'https://hs.example',
        userId: '@a:hs.example',
        deviceId: 'DEV1',
      );
      final two = await loadOrCreateDeviceKeys(
        secretStore: store,
        homeserver: 'https://hs.example',
        userId: '@a:hs.example',
        deviceId: 'DEV2',
      );
      expect(
        (await two.publicKeys()).identityKey,
        isNot((await one.publicKeys()).identityKey),
      );
    });
  });
}
