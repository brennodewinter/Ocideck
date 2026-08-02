import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/xmpp/xmpp_sasl.dart';

void main() {
  group('SCRAM-SHA-1 against the RFC 5802 §5 test vector', () {
    // username "user", password "pencil", the RFC's fixed client nonce.
    ScramClient client() => ScramClient(
      username: 'user',
      password: 'pencil',
      clientNonce: 'fyko+d2lbbFgONRv9qkxdawL',
    );

    const serverFirst =
        'r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,'
        's=QSXCR+Q6sek8bf92,i=4096';

    test('client-first matches the RFC', () {
      expect(client().clientFirst(), 'n,,n=user,r=fyko+d2lbbFgONRv9qkxdawL');
    });

    test('client-final proof matches the RFC exactly', () {
      final c = client();
      c.clientFirst();
      expect(
        c.clientFinal(serverFirst),
        'c=biws,r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,'
        'p=v0X8v3Bz2T0CJGbJQyF0X+HI4Ts=',
      );
    });

    test('the server signature verifies (mutual auth)', () {
      final c = client();
      c.clientFirst();
      c.clientFinal(serverFirst);
      expect(c.verifyServerFinal('v=rmF9pqV8S7suAoZWja4dJRkFsKQ='), isTrue);
      expect(c.verifyServerFinal('v=AAAAAAAAAAAAAAAAAAAAAAAAAAA='), isFalse);
    });
  });

  group('SCRAM guards', () {
    test('a server nonce that does not extend the client nonce is refused', () {
      final c = ScramClient(username: 'u', password: 'p', clientNonce: 'abc');
      c.clientFirst();
      expect(
        () => c.clientFinal('r=zzz,s=QSXCR+Q6sek8bf92,i=4096'),
        throwsFormatException,
      );
    });

    test('a server-first missing salt/iterations is refused', () {
      final c = ScramClient(username: 'u', password: 'p', clientNonce: 'abc');
      c.clientFirst();
      expect(() => c.clientFinal('r=abcXYZ'), throwsFormatException);
    });

    test('the username is SASL-name-escaped', () {
      final c = ScramClient(
        username: 'a,b=c',
        password: 'p',
        clientNonce: 'n1',
      );
      expect(c.clientFirst(), 'n,,n=a=2Cb=3Dc,r=n1');
    });

    test('mechanism name follows the hash', () {
      expect(
        ScramClient(
          username: 'u',
          password: 'p',
          clientNonce: 'n',
        ).mechanismName,
        'SCRAM-SHA-1',
      );
      expect(
        ScramClient(
          username: 'u',
          password: 'p',
          clientNonce: 'n',
          hash: ScramHash.sha256,
        ).mechanismName,
        'SCRAM-SHA-256',
      );
    });
  });

  group('PLAIN and ANONYMOUS', () {
    test('PLAIN is NUL-delimited base64', () {
      // base64 of "\0user\0pencil".
      expect(saslPlain('user', 'pencil'), 'AHVzZXIAcGVuY2ls');
    });

    test('ANONYMOUS with no trace is the empty response', () {
      expect(saslAnonymous(), '');
    });
  });
}
