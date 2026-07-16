import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/secret_store.dart';

void main() {
  group('SecretStore.gitTokenKey', () {
    test('normalises trailing slashes so one repo owner is one entry', () {
      expect(
        SecretStore.gitTokenKey('https://git.example.org/', 'librekat'),
        SecretStore.gitTokenKey('https://git.example.org', 'librekat'),
      );
    });

    test('normalises surrounding whitespace', () {
      expect(
        SecretStore.gitTokenKey('  https://git.example.org  ', ' librekat '),
        SecretStore.gitTokenKey('https://git.example.org', 'librekat'),
      );
    });

    test('a different owner or forge yields a different key', () {
      final a = SecretStore.gitTokenKey('https://git.example.org', 'librekat');
      final b = SecretStore.gitTokenKey('https://git.example.org', 'someone');
      final c = SecretStore.gitTokenKey('https://github.com', 'librekat');
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('does not collide with the webdav or ai key namespaces', () {
      // Same server, same name: the namespaces must still keep them apart, or
      // configuring WebDAV would clobber a git token on the same host.
      expect(
        SecretStore.gitTokenKey('https://x.example', 'alice'),
        isNot(SecretStore.webdavKey('https://x.example', 'alice')),
      );
      expect(
        SecretStore.gitTokenKey('https://x.example', 'alice'),
        isNot(SecretStore.aiApiKeyKey('https://x.example')),
      );
    });
  });
}
