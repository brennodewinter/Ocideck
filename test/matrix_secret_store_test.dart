// Key-derivation tests for the Matrix/collab keychain entries
// (`SecretStore.matrixTokenKey` / `collabDeviceSeedsKey`, P-D), mirroring
// `git_secret_store_test.dart`. The namespaces must stay apart from every other
// secret on the same host, or configuring one account would clobber another.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecretStore.matrixTokenKey', () {
    test('normalises trailing slashes and whitespace', () {
      expect(
        SecretStore.matrixTokenKey('https://hs.example/', '@a:hs.example'),
        SecretStore.matrixTokenKey('  https://hs.example ', ' @a:hs.example '),
      );
    });

    test('a different user or homeserver yields a different key', () {
      final a = SecretStore.matrixTokenKey(
        'https://hs.example',
        '@a:hs.example',
      );
      final b = SecretStore.matrixTokenKey(
        'https://hs.example',
        '@b:hs.example',
      );
      final c = SecretStore.matrixTokenKey(
        'https://other.example',
        '@a:hs.example',
      );
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });

  test('token and device-seed namespaces do not collide', () {
    // Same account: the token and the device seeds must land in distinct entries.
    expect(
      SecretStore.matrixTokenKey('https://hs.example', '@a:hs.example'),
      isNot(
        SecretStore.collabDeviceSeedsKey('https://hs.example', '@a:hs.example'),
      ),
    );
  });

  test('matrix/collab keys do not collide with webdav, git or ai', () {
    const host = 'https://x.example';
    const who = 'alice';
    final token = SecretStore.matrixTokenKey(host, who);
    final seeds = SecretStore.collabDeviceSeedsKey(host, who);
    for (final other in [
      SecretStore.webdavKey(host, who),
      SecretStore.gitTokenKey(host, who),
      SecretStore.aiApiKeyKey(host),
    ]) {
      expect(token, isNot(other));
      expect(seeds, isNot(other));
    }
  });

  group('round-trip against the keychain', () {
    late SecretStore store;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      store = SecretStore(
        storage: const FlutterSecureStorage(),
        canStore: true,
      );
    });

    test('the Matrix token writes, reads back and deletes', () async {
      await store.writeMatrixToken(
        'https://hs.example',
        '@a:hs.example',
        'tok',
      );
      expect(
        await store.readMatrixToken('https://hs.example', '@a:hs.example'),
        'tok',
      );
      await store.deleteMatrixToken('https://hs.example', '@a:hs.example');
      expect(
        await store.readMatrixToken('https://hs.example', '@a:hs.example'),
        isNull,
      );
    });

    test('the device seeds write, read back and delete', () async {
      await store.writeCollabDeviceSeeds(
        'https://hs.example',
        '@a:hs.example',
        'blob',
      );
      expect(
        await store.readCollabDeviceSeeds(
          'https://hs.example',
          '@a:hs.example',
        ),
        'blob',
      );
      await store.deleteCollabDeviceSeeds(
        'https://hs.example',
        '@a:hs.example',
      );
      expect(
        await store.readCollabDeviceSeeds(
          'https://hs.example',
          '@a:hs.example',
        ),
        isNull,
      );
    });
  });
}
