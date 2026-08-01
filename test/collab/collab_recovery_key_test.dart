import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_device_store.dart';
import 'package:ocideck/collab/collab_recovery_key.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  final ed = [for (var i = 0; i < 32; i++) i];
  final x = [for (var i = 0; i < 32; i++) (i * 7) & 0xff];

  group('encode/decode', () {
    test('round-trips the two seeds exactly', () {
      final key = encodeRecoveryKey(ed, x);
      final back = decodeRecoveryKey(key);
      expect(back.ed25519Seed, ed);
      expect(back.x25519Seed, x);
    });

    test('is grouped, uppercase, and free of look-alike letters', () {
      final key = encodeRecoveryKey(ed, x);
      expect(key, contains('-'));
      expect(key, key.toUpperCase());
      // Crockford Base32 omits I, L, O, U.
      expect(RegExp(r'[ILOU]').hasMatch(key.replaceAll('-', '')), isFalse);
    });

    test('tolerates spacing, lowercase and missing hyphens', () {
      final key = encodeRecoveryKey(ed, x);
      final messy = key.replaceAll('-', '').toLowerCase();
      final spaced = '  $messy  ';
      final back = decodeRecoveryKey(spaced);
      expect(back.ed25519Seed, ed);
      expect(back.x25519Seed, x);
    });

    test('a single-character typo fails the checksum', () {
      final key = encodeRecoveryKey(ed, x);
      final chars = key.replaceAll('-', '').split('');
      // Flip one character to another valid Base32 symbol.
      chars[10] = chars[10] == 'A' ? 'B' : 'A';
      expect(
        () => decodeRecoveryKey(chars.join()),
        throwsA(
          isA<RecoveryKeyException>().having(
            (e) => e.reason,
            'reason',
            RecoveryKeyError.checksum,
          ),
        ),
      );
    });

    test('a non-Base32 character is a format error', () {
      expect(
        () => decodeRecoveryKey('!!!!'),
        throwsA(
          isA<RecoveryKeyException>().having(
            (e) => e.reason,
            'reason',
            RecoveryKeyError.format,
          ),
        ),
      );
    });

    test('a truncated key is a format error, not a silent partial', () {
      final key = encodeRecoveryKey(ed, x).replaceAll('-', '');
      expect(
        () => decodeRecoveryKey(key.substring(0, 20)),
        throwsA(isA<RecoveryKeyException>()),
      );
    });
  });

  group('export/import against the keychain', () {
    const homeserver = 'https://hs.example';
    const userId = '@me:hs.example';
    late SecretStore secrets;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      secrets = SecretStore(
        storage: const FlutterSecureStorage(),
        canStore: true,
      );
    });

    test('exported key restores the same identity on another device', () async {
      // Device A mints an identity and exports it.
      final a = await loadOrCreateDeviceKeys(
        secretStore: secrets,
        homeserver: homeserver,
        userId: userId,
        deviceId: 'DEV-A',
      );
      final aPub = await a.publicKeys();
      final seedsA = await readDeviceSeeds(
        secretStore: secrets,
        homeserver: homeserver,
        userId: userId,
      );
      final key = seedsA!.recoveryKey();

      // Device B (fresh keychain) imports the key under its own device id.
      FlutterSecureStorage.setMockInitialValues({});
      final freshSecrets = SecretStore(
        storage: const FlutterSecureStorage(),
        canStore: true,
      );
      final b = await importRecoveryKey(
        secretStore: freshSecrets,
        homeserver: homeserver,
        userId: userId,
        deviceId: 'DEV-B',
        recoveryKey: key,
      );
      final bPub = await b.publicKeys();

      // Same identity key (fingerprint), even though the device id differs.
      expect(bPub.identityKey, aPub.identityKey);
      expect(bPub.deviceId, 'DEV-B');

      // And it persists: the next load on device B reuses the imported identity.
      final bAgain = await loadOrCreateDeviceKeys(
        secretStore: freshSecrets,
        homeserver: homeserver,
        userId: userId,
        deviceId: 'DEV-B',
      );
      expect((await bAgain.publicKeys()).identityKey, aPub.identityKey);
    });

    test('importing a malformed key writes nothing', () async {
      expect(
        () => importRecoveryKey(
          secretStore: secrets,
          homeserver: homeserver,
          userId: userId,
          deviceId: 'DEV',
          recoveryKey: 'not-a-real-key',
        ),
        throwsA(isA<RecoveryKeyException>()),
      );
      expect(
        await readDeviceSeeds(
          secretStore: secrets,
          homeserver: homeserver,
          userId: userId,
        ),
        isNull,
      );
    });
  });
}
