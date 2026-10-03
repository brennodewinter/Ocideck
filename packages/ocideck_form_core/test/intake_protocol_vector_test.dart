// The intake protocol vectors (docs/design/INTAKE_PROTOCOL.md, D5):
// `test/fixtures/intake_protocol_vectors.json` is what version 1 produces for a fixed seed and
// fixed requests — and what a second implementation checks itself against. Kept apart from the
// other tests because it reads a file (`dart:io`), and those run in a browser too.
//
// The signatures in it were also verified independently, with Node's OpenSSL Ed25519, when the
// file was made; this test makes them again and compares byte for byte.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

Uint8List unhex(String h) => Uint8List.fromList([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

void main() {
  final vector =
      jsonDecode(
            File(
              'test/fixtures/intake_protocol_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final keyJson = vector['signing_key']! as Map<String, Object?>;
  final requests = (vector['requests']! as List).cast<Map<String, Object?>>();

  test('is public domain', () {
    expect(vector['license'], 'CC0-1.0');
  });

  group('the signing key', () {
    test('is what its seed makes', () async {
      final key = await formSigningKeyFromSeed(
        unhex(keyJson['seed_hex']! as String),
      );
      expect(key.publicKeyText, keyJson['public_key']);
      expect(key.fingerprint, keyJson['fingerprint']);
    });
  });

  group('the requests', () {
    for (final r in requests) {
      group(r['name']! as String, () {
        final host = r['host']! as String;
        final method = r['method']! as String;
        final target = r['target']! as String;
        final body = utf8.encode(r['body']! as String);
        final ts = r['ts']! as int;
        final nonce = r['nonce']! as String;

        test('hashes its body as written', () {
          expect(sha256Hex(body), r['body_sha256']);
        });

        test('has the preimage written', () {
          expect(
            intakeRequestPreimage(
              host: host,
              method: method,
              target: target,
              bodySha256: r['body_sha256']! as String,
              ts: ts,
              nonce: nonce,
            ),
            r['preimage'],
          );
        });

        test('is signed again byte for byte', () async {
          final key = await formSigningKeyFromSeed(
            unhex(keyJson['seed_hex']! as String),
          );
          expect(
            await signIntakeRequest(
              key: key,
              host: host,
              method: method,
              target: target,
              ts: ts,
              nonce: nonce,
              body: body,
            ),
            r['authorization'],
          );
        });

        test('verifies as written, and as nothing else', () async {
          final verdict = await verifyIntakeRequest(
            header: r['authorization']! as String,
            host: host,
            method: method,
            target: target,
            bodySha256: r['body_sha256']! as String,
            nowSeconds: ts,
          );
          expect(verdict, isA<IntakeRequestVerified>());
          expect(
            (verdict as IntakeRequestVerified).signKey,
            keyJson['public_key'],
          );
          final other = await verifyIntakeRequest(
            header: r['authorization']! as String,
            host: host,
            method: method,
            target: '$target/',
            bodySha256: r['body_sha256']! as String,
            nowSeconds: ts,
          );
          expect(other, isA<IntakeRequestRefused>());
        });
      });
    }
  });

  group('the tokens', () {
    final tokens = vector['tokens']! as Map<String, Object?>;
    test('an invite token hashes as written', () {
      expect(isValidInviteToken(tokens['invite_token']! as String), isTrue);
      expect(
        inviteTokenHash(tokens['invite_token']! as String),
        tokens['invite_token_sha256'],
      );
    });
    test('a withdrawal secret hashes as written', () {
      expect(
        isValidWithdrawalSecret(tokens['withdrawal_secret']! as String),
        isTrue,
      );
      expect(
        withdrawalSecretHash(tokens['withdrawal_secret']! as String),
        tokens['withdrawal_secret_sha256'],
      );
    });
  });

  group('the invite links', () {
    for (final c
        in (vector['invite_links']! as List).cast<Map<String, Object?>>()) {
      test(c['name']! as String, () {
        final r = parseInviteLink(c['text']! as String);
        final issue = c['issue'];
        if (issue != null) {
          expect(r, isA<InviteLinkRefused>());
          expect((r as InviteLinkRefused).issue.name, issue);
          return;
        }
        final want = c['link']! as Map<String, Object?>;
        final got = (r as InviteLinkParsed).link;
        expect(got.shellBase, want['shell_base']);
        expect(got.fid, want['fid']);
        expect(got.apiHost, want['api_host']);
        expect(got.fingerprint, want['fingerprint']);
        expect(got.token, want['token']);
      });
    }
  });
}
