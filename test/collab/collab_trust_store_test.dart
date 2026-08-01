import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_participant.dart';
import 'package:ocideck/collab/collab_trust_store.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  const homeserver = 'https://hs.example';
  const userId = '@me:hs.example';
  final keyA = [for (var i = 0; i < 32; i++) i];
  final keyB = [for (var i = 0; i < 32; i++) 255 - i];

  late SecretStore secrets;
  CollabTrustStore newStore() => CollabTrustStore(secrets, homeserver, userId);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
  });

  group('evaluate', () {
    test('an unpinned device is unverified', () async {
      final store = newStore();
      await store.load();
      expect(store.evaluate('@a:hs', 'DEV', keyA), TrustState.unverified);
    });

    test('a pinned device with the same key is verified', () async {
      final store = newStore();
      await store.load();
      await store.pin('@a:hs', 'DEV', keyA);
      expect(store.evaluate('@a:hs', 'DEV', keyA), TrustState.verified);
      expect(store.isPinned('@a:hs', 'DEV', keyA), isTrue);
    });

    test('a pinned device presenting a different key is a mismatch', () async {
      final store = newStore();
      await store.load();
      await store.pin('@a:hs', 'DEV', keyA);
      expect(store.evaluate('@a:hs', 'DEV', keyB), TrustState.mismatch);
    });

    test('pins are per device, not per user', () async {
      final store = newStore();
      await store.load();
      await store.pin('@a:hs', 'DEV1', keyA);
      // Same user, other device: still unverified.
      expect(store.evaluate('@a:hs', 'DEV2', keyA), TrustState.unverified);
    });
  });

  test('pins survive a reload from the keychain', () async {
    final first = newStore();
    await first.load();
    await first.pin('@a:hs', 'DEV', keyA);

    final second = newStore();
    await second.load();
    expect(second.evaluate('@a:hs', 'DEV', keyA), TrustState.verified);
  });

  test('another account does not see these pins', () async {
    final mine = newStore();
    await mine.load();
    await mine.pin('@a:hs', 'DEV', keyA);

    final other = CollabTrustStore(secrets, homeserver, '@other:hs.example');
    await other.load();
    expect(other.evaluate('@a:hs', 'DEV', keyA), TrustState.unverified);
  });

  test('isIdentityPinned matches a pinned key across any device', () async {
    final store = newStore();
    await store.load();
    expect(store.isIdentityPinned(keyA), isFalse);
    await store.pin('@a:hs', 'DEV', keyA);
    expect(store.isIdentityPinned(keyA), isTrue);
    expect(store.isIdentityPinned(keyB), isFalse);
  });

  test('unpin returns a device to unverified', () async {
    final store = newStore();
    await store.load();
    await store.pin('@a:hs', 'DEV', keyA);
    await store.unpin('@a:hs', 'DEV');
    expect(store.evaluate('@a:hs', 'DEV', keyA), TrustState.unverified);
  });

  test('re-pinning overwrites a changed key (a re-onboarded peer)', () async {
    final store = newStore();
    await store.load();
    await store.pin('@a:hs', 'DEV', keyA);
    await store.pin('@a:hs', 'DEV', keyB);
    expect(store.evaluate('@a:hs', 'DEV', keyB), TrustState.verified);
    expect(store.evaluate('@a:hs', 'DEV', keyA), TrustState.mismatch);
  });

  test(
    'a corrupt keychain blob loads as an empty store, not a throw',
    () async {
      await secrets.writeCollabTrust(homeserver, userId, 'not json');
      final store = newStore();
      await store.load();
      expect(store.isLoaded, isTrue);
      expect(store.evaluate('@a:hs', 'DEV', keyA), TrustState.unverified);
    },
  );
}
