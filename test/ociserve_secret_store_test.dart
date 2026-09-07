import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'refresh credential and pending sync round-trip only through keychain',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecretStore(
        storage: const FlutterSecureStorage(),
        canStore: true,
      );

      await store.writeOciServeRefreshToken(
        'https://learn.example/',
        'refresh',
      );
      await store.writeOciServeOutbox('https://learn.example', '[{"one":1}]');

      expect(
        await store.readOciServeRefreshToken('https://learn.example'),
        'refresh',
      );
      expect(
        await store.readOciServeOutbox('https://learn.example/'),
        '[{"one":1}]',
      );
      await store.deleteOciServeRefreshToken('https://learn.example');
      expect(
        await store.readOciServeRefreshToken('https://learn.example'),
        isNull,
      );
    },
  );

  test(
    'web-style refusing store never accepts an OciServe credential',
    () async {
      final store = SecretStore(canStore: false);
      await expectLater(
        store.writeOciServeRefreshToken('https://learn.example', 'secret'),
        throwsA(isA<SecretStoreUnsupported>()),
      );
      expect(
        await store.readOciServeRefreshToken('https://learn.example'),
        isNull,
      );
    },
  );
}
