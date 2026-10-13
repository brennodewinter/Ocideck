import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ocideck/services/secret_store.dart';

class _Vault extends FlutterSecureStorage {
  final data = <String, String>{};

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map<String, String>.of(data);

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }
}

void main() {
  test(
    'complete reset deletes every OciDeck key without clearing others',
    () async {
      final backend = _Vault();
      final store = SecretStore(storage: backend, canStore: true);

      await backend.write(
        key: SecretStore.aiApiKeyKey('https://ai.example'),
        value: 'ai',
      );
      await backend.write(
        key: SecretStore.xmppPasswordKey(
          'wss://chat.example/xmpp',
          'a@example',
        ),
        value: 'xmpp',
      );
      await backend.write(key: SecretStore.formEditorialKeyKey, value: 'form');
      await backend.write(
        key: SecretStore.privacyOwnIdentityKey,
        value: 'person',
      );
      await backend.write(key: 'other-app-secret', value: 'keep');

      await store.deleteAllOciDeckSecrets();

      expect((await backend.readAll()).keys, {'other-app-secret'});
    },
  );
}
