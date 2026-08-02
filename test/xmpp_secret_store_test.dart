// Key-derivation tests for the XMPP keychain entry (`SecretStore.xmppPasswordKey`,
// F2 `NATIVE_CALLS.md` §5), mirroring `matrix_secret_store_test.dart`. The XMPP
// account password must live in its own namespace, apart from every other secret
// on the same host, so configuring a call account never clobbers another login.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecretStore.xmppPasswordKey', () {
    test('normalises trailing slashes and whitespace', () {
      expect(
        SecretStore.xmppPasswordKey(
          'wss://xmpp.example/xmpp-websocket/',
          'a@example',
        ),
        SecretStore.xmppPasswordKey(
          '  wss://xmpp.example/xmpp-websocket ',
          ' a@example ',
        ),
      );
    });

    test('a different account or server yields a different key', () {
      final a = SecretStore.xmppPasswordKey('wss://x.example/ws', 'a@x.example');
      final b = SecretStore.xmppPasswordKey('wss://x.example/ws', 'b@x.example');
      final c = SecretStore.xmppPasswordKey('wss://y.example/ws', 'a@x.example');
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('does not collide with matrix, webdav, git or ai keys', () {
      const host = 'https://x.example';
      const wss = 'wss://x.example/ws';
      const who = 'alice';
      final xmpp = SecretStore.xmppPasswordKey(wss, who);
      for (final other in [
        SecretStore.matrixTokenKey(host, who),
        SecretStore.webdavKey(host, who),
        SecretStore.gitTokenKey(host, who),
        SecretStore.aiApiKeyKey(host),
      ]) {
        expect(xmpp, isNot(other));
      }
    });
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

    test('the XMPP password writes, reads back and deletes', () async {
      const wss = 'wss://xmpp.example/ws';
      const jid = 'a@example';
      await store.writeXmppPassword(wss, jid, 'pencil');
      expect(await store.readXmppPassword(wss, jid), 'pencil');
      await store.deleteXmppPassword(wss, jid);
      expect(await store.readXmppPassword(wss, jid), isNull);
    });
  });
}
