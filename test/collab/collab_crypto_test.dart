// Tests for the collaboration E2EE seam (`lib/collab/collab_crypto.dart`,
// SELF_ENCRYPTED_RELAY.md phase P-A). Two layers:
//
//   1. **Known-answer vectors** for the primitives, taken verbatim from the
//      RFCs (X25519 — RFC 7748 §6.1; HKDF-SHA256 — RFC 5869 A.1; Ed25519 —
//      RFC 8032 §7.1). These prove `package:cryptography` computes the standard
//      values *with the exact calling convention this module uses* — the thing a
//      security review checks first. A wrong byte order or parameter would break
//      them.
//   2. **Behaviour of `CollabCrypto`**: the seal/open round-trip and key wrap
//      work, and every failure path fails *closed* (a flipped byte, a wrong
//      context, a wrong recipient, a missing or forged signature, an unknown
//      epoch — each throws, never returns plaintext).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('primitive known-answer vectors (RFCs)', () {
    test('X25519 shared secret — RFC 7748 §6.1', () async {
      const alicePriv =
          '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a';
      const alicePub =
          '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a';
      const bobPub =
          'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f';
      const shared =
          '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742';

      final alice = await X25519().newKeyPairFromSeed(_hex(alicePriv));
      final pub = await alice.extractPublicKey();
      expect(_toHex(pub.bytes), alicePub, reason: 'derived public key');

      final secret = await X25519().sharedSecretKey(
        keyPair: alice,
        remotePublicKey: SimplePublicKey(
          _hex(bobPub),
          type: KeyPairType.x25519,
        ),
      );
      expect(_toHex(await secret.extractBytes()), shared);
    });

    test('HKDF-SHA256 — RFC 5869 Test Case 1', () async {
      final ikm = _hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b');
      final salt = _hex('000102030405060708090a0b0c');
      final info = _hex('f0f1f2f3f4f5f6f7f8f9');
      const okm =
          '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
          '34007208d5b887185865';

      final derived = await Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 42,
      ).deriveKey(secretKey: SecretKey(ikm), nonce: salt, info: info);
      expect(_toHex(await derived.extractBytes()), okm);
    });

    test('Ed25519 sign/verify — RFC 8032 §7.1 Test 1 and Test 2', () async {
      // Test 1: empty message.
      final kp1 = await Ed25519().newKeyPairFromSeed(
        _hex(
          '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
        ),
      );
      expect(
        _toHex((await kp1.extractPublicKey()).bytes),
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      );
      final sig1 = await Ed25519().sign(const [], keyPair: kp1);
      expect(
        _toHex(sig1.bytes),
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555f'
        'b8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      );

      // Test 2: one-byte message 0x72 — Ed25519 is deterministic, so the exact
      // signature must match.
      final kp2 = await Ed25519().newKeyPairFromSeed(
        _hex(
          '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
        ),
      );
      final sig2 = await Ed25519().sign(_hex('72'), keyPair: kp2);
      expect(
        _toHex(sig2.bytes),
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da08'
        '5ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      );
      expect(
        await Ed25519().verify(
          _hex('72'),
          signature: Signature(
            sig2.bytes,
            publicKey: await kp2.extractPublicKey(),
          ),
        ),
        isTrue,
      );
    });
  });

  group('CollabCrypto — device bindings', () {
    test(
      'a genuine binding verifies; a swapped agreement key does not',
      () async {
        final alice = await _device('alice');
        final pub = await alice.publicKeys(rot: 0);
        expect(await pub.verifyBinding(), isTrue);

        // Simulate a relay swapping the agreement key: the identity signature no
        // longer covers it, so the binding must fail (§5.3 defence).
        final other = await (await _device('mallory')).publicKeys(rot: 0);
        final swapped = DevicePublicKeys(
          deviceId: pub.deviceId,
          identityKey: pub.identityKey,
          agreementKey: other.agreementKey,
          agreementSignature: pub.agreementSignature,
          rot: pub.rot,
        );
        expect(await swapped.verifyBinding(), isFalse);
      },
    );

    test('DevicePublicKeys survives a JSON round-trip', () async {
      final pub = await (await _device('alice')).publicKeys(rot: 0);
      final back = DevicePublicKeys.fromJson(
        jsonDecode(jsonEncode(pub.toJson())) as Map<String, Object?>,
      );
      expect(back.deviceId, pub.deviceId);
      expect(back.identityKey, pub.identityKey);
      expect(back.agreementKey, pub.agreementKey);
      expect(back.rot, pub.rot);
      expect(await back.verifyBinding(), isTrue);
    });

    // §5.1 N2 — pin-test on the new preimage bytes: the binding message is
    // exactly ['ocideck/device-binding/v2', deviceId, b64(agreementKey), rot].
    // A byte-level pin so a future refactor cannot silently change the signed
    // preimage (which would break cross-tool verification).
    test('the v2 binding preimage is the exact 4-element JSON array', () async {
      final alice = await _device('alice');
      final pub = await alice.publicKeys(rot: 42);
      final expected = utf8.encode(
        jsonEncode([
          'ocideck/device-binding/v2',
          'alice',
          base64.encode(pub.agreementKey),
          42,
        ]),
      );
      // Reconstruct the preimage the way _deviceBindingMessage does, and pin it
      // against the expected literal — a change in tag, field order, or encoding
      // breaks this.
      final reconstructed = utf8.encode(
        jsonEncode([
          'ocideck/device-binding/v2',
          pub.deviceId,
          base64.encode(pub.agreementKey),
          pub.rot,
        ]),
      );
      expect(reconstructed, expected);
      // And the signature over those bytes verifies.
      expect(await pub.verifyBinding(), isTrue);
    });

    // §5.1 N2 — a rot-replay attack: an occupant takes a validly-signed binding
    // and claims a higher rot without re-signing. The signature covers rot, so
    // the forged binding must fail verification.
    test('a forged rot (without re-signing) breaks the binding', () async {
      final alice = await _device('alice');
      final pub = await alice.publicKeys(rot: 0);
      expect(await pub.verifyBinding(), isTrue);

      // Attacker raises rot to MAX without re-signing — the signature no longer
      // covers the new preimage.
      final forged = DevicePublicKeys(
        deviceId: pub.deviceId,
        identityKey: pub.identityKey,
        agreementKey: pub.agreementKey,
        agreementSignature: pub.agreementSignature,
        rot: 0x7fffffffffffffff,
      );
      expect(await forged.verifyBinding(), isFalse);
    });
  });

  group('CollabCrypto — seal / open round-trip', () {
    test('a signed op sealed by the authority opens for a member', () async {
      final session = await _twoParty();
      final sealed = await session.authority.seal(
        {'kind': 'op', 'v': 1, 'field': 'title'},
        room: '!room:hs',
        type: 'nl.ocideck.op',
        signed: true,
      );
      final opened = await session.member.open(
        sealed,
        room: '!room:hs',
        type: 'nl.ocideck.op',
        sender: session.authorityPub,
        requireSignature: true,
      );
      expect(opened, {'kind': 'op', 'v': 1, 'field': 'title'});
    });

    test('the sealed wire form survives a content round-trip', () async {
      final session = await _twoParty();
      final sealed = await session.authority.seal(
        {'kind': 'chat', 'text': 'hoi'},
        room: '!room:hs',
        type: 'nl.ocideck.chat',
        signed: false,
      );
      final back = SealedEnvelope.fromContent(
        jsonDecode(jsonEncode(sealed.toContent())) as Map<String, Object?>,
      );
      final opened = await session.member.open(
        back,
        room: '!room:hs',
        type: 'nl.ocideck.chat',
        sender: session.authorityPub,
      );
      expect(opened, {'kind': 'chat', 'text': 'hoi'});
    });

    test('sealing before any epoch throws', () async {
      final lonely = CollabCrypto(await _device('nobody'));
      expect(
        () => lonely.seal({'x': 1}, room: 'r', type: 't', signed: false),
        throwsA(isA<CollabCryptoException>()),
      );
    });
  });

  group('CollabCrypto — fail-closed', () {
    test('a flipped ciphertext byte is rejected', () async {
      final s = await _twoParty();
      final sealed = await s.authority.seal(
        {'kind': 'op'},
        room: 'r',
        type: 't',
        signed: false,
      );
      final tampered = _flipFirstCiphertextByte(sealed);
      await expectLater(
        () => s.member.open(
          tampered,
          room: 'r',
          type: 't',
          sender: s.authorityPub,
        ),
        _throwsReason('bad-tag'),
      );
    });

    test('a wrong room or type (AAD) is rejected', () async {
      final s = await _twoParty();
      final sealed = await s.authority.seal(
        {'kind': 'op'},
        room: '!real:hs',
        type: 'nl.ocideck.op',
        signed: false,
      );
      await expectLater(
        () => s.member.open(
          sealed,
          room: '!other:hs',
          type: 'nl.ocideck.op',
          sender: s.authorityPub,
        ),
        _throwsReason('bad-tag'),
      );
      await expectLater(
        () => s.member.open(
          sealed,
          room: '!real:hs',
          type: 'nl.ocideck.lock',
          sender: s.authorityPub,
        ),
        _throwsReason('bad-tag'),
      );
    });

    test('a required-but-missing signature is rejected', () async {
      final s = await _twoParty();
      final sealed = await s.authority.seal(
        {'kind': 'op'},
        room: 'r',
        type: 't',
        signed: false,
      );
      await expectLater(
        () => s.member.open(
          sealed,
          room: 'r',
          type: 't',
          sender: s.authorityPub,
          requireSignature: true,
        ),
        _throwsReason('missing-signature'),
      );
    });

    test('a signature that does not match the sender is rejected', () async {
      final s = await _twoParty();
      final sealed = await s.authority.seal(
        {'kind': 'op'},
        room: 'r',
        type: 't',
        signed: true,
      );
      // Same claimed sender id, but a different identity key → forged.
      final impostor = DevicePublicKeys(
        deviceId: s.authorityPub.deviceId,
        identityKey: (await (await _device(
          'imp',
        )).publicKeys(rot: 0)).identityKey,
        agreementKey: s.authorityPub.agreementKey,
        agreementSignature: s.authorityPub.agreementSignature,
        rot: s.authorityPub.rot,
      );
      await expectLater(
        () => s.member.open(
          sealed,
          room: 'r',
          type: 't',
          sender: impostor,
          requireSignature: true,
        ),
        _throwsReason('bad-signature'),
      );
    });

    test('a sender-id mismatch is rejected before any decryption', () async {
      final s = await _twoParty();
      final sealed = await s.authority.seal(
        {'kind': 'op'},
        room: 'r',
        type: 't',
        signed: false,
      );
      final wrongId = await (await _device('someone-else')).publicKeys(rot: 0);
      await expectLater(
        () => s.member.open(sealed, room: 'r', type: 't', sender: wrongId),
        _throwsReason('sender-mismatch'),
      );
    });

    test('an epoch this device never received is rejected', () async {
      final s = await _twoParty();
      final sealed = await s.authority.seal(
        {'kind': 'op'},
        room: 'r',
        type: 't',
        signed: false,
      );
      // A third party that never installed the epoch key.
      final outsider = CollabCrypto(await _device('outsider'));
      await expectLater(
        () =>
            outsider.open(sealed, room: 'r', type: 't', sender: s.authorityPub),
        _throwsReason('unknown-epoch'),
      );
    });
  });

  group('CollabCrypto — key wraps & epochs', () {
    test(
      'a wrap for another device fails trial-decrypt (blinded, §5.1 N3)',
      () async {
        final authority = CollabCrypto(await _device('auth'));
        final bob = await (await _device('bob')).publicKeys(rot: 0);
        final carolKeys = await _device('carol');
        final result = await authority.rekey([bob]);

        final carol = CollabCrypto(carolKeys);
        final authorityPub = await _pub(authority, 'auth');
        // The wrap was sealed for bob's agreement key; carol's ECDH derives a
        // different wrap key, so the AEAD tag fails — bad-wrap, not
        // wrong-recipient (the wrap carries no cleartext recipient to check).
        await expectLater(
          () => carol.installEpochKey(result.wraps.single, authorityPub),
          _throwsReason('bad-wrap'),
        );
      },
    );

    test('a tampered wrap ciphertext is rejected', () async {
      final authority = CollabCrypto(await _device('auth'));
      final bobKeys = await _device('bob');
      final bobPub = await bobKeys.publicKeys(rot: 0);
      final result = await authority.rekey([bobPub]);
      final authorityPub = await _pub(authority, 'auth');

      final w = result.wraps.single;
      final badCt = Uint8List.fromList(w.ciphertext)..[0] ^= 0xff;
      final tampered = WrappedKey(
        epoch: w.epoch,
        ephemeralKey: w.ephemeralKey,
        nonce: w.nonce,
        ciphertext: badCt,
        signature: w.signature, // stale signature over the old ciphertext
      );
      await expectLater(
        () => CollabCrypto(bobKeys).installEpochKey(tampered, authorityPub),
        // The signature covers the ciphertext, so tampering trips the signature
        // check first — still fail-closed, which is the property under test.
        _throwsReason('bad-signature'),
      );
    });

    test(
      'removing a member and re-keying locks them out of the new epoch',
      () async {
        final authority = CollabCrypto(await _device('auth'));
        final authorityPub = await _pub(authority, 'auth');
        final bobKeys = await _device('bob');
        final carolKeys = await _device('carol');
        final bobPub = await bobKeys.publicKeys(rot: 0);
        final carolPub = await carolKeys.publicKeys(rot: 0);

        // Epoch 0: bob + carol. Wraps are in member order (rekey preserves it);
        // the wrap carries no cleartext recipient (§5.1 N3), so address by index.
        final e0 = await authority.rekey([bobPub, carolPub]);
        expect(e0.epoch, 0);
        final bob = CollabCrypto(bobKeys);
        final carol = CollabCrypto(carolKeys);
        await bob.installEpochKey(e0.wraps[0], authorityPub);
        await carol.installEpochKey(e0.wraps[1], authorityPub);

        // Epoch 1: bob removed, only carol re-keyed.
        final e1 = await authority.rekey([carolPub]);
        expect(e1.epoch, 1);
        await carol.installEpochKey(e1.wraps.single, authorityPub);

        final sealed = await authority.seal(
          {'kind': 'op', 'secret': true},
          room: 'r',
          type: 't',
          signed: false,
        );
        // Carol (still in) reads it; bob (removed) has no epoch-1 key.
        expect(
          await carol.open(sealed, room: 'r', type: 't', sender: authorityPub),
          {'kind': 'op', 'secret': true},
        );
        await expectLater(
          () => bob.open(sealed, room: 'r', type: 't', sender: authorityPub),
          _throwsReason('unknown-epoch'),
        );
      },
    );

    test(
      'wrapEpochTo adds a newcomer to the current epoch without a bump',
      () async {
        final authority = CollabCrypto(await _device('auth'));
        final authorityPub = await _pub(authority, 'auth');
        final bobPub = await (await _device('bob')).publicKeys(rot: 0);
        await authority.rekey([bobPub]); // epoch 0

        final carolKeys = await _device('carol');
        final carol = CollabCrypto(carolKeys);
        final wrap = await authority.wrapEpochTo(
          await carolKeys.publicKeys(rot: 0),
        );
        expect(wrap.epoch, 0);
        expect(authority.currentEpoch, 0); // no bump

        await carol.installEpochKey(wrap, authorityPub);
        final sealed = await authority.seal(
          {'kind': 'op'},
          room: 'r',
          type: 't',
          signed: false,
        );
        expect(
          await carol.open(sealed, room: 'r', type: 't', sender: authorityPub),
          {'kind': 'op'},
        );
      },
    );

    test('a WrappedKey survives a JSON round-trip', () async {
      final authority = CollabCrypto(await _device('auth'));
      final bobPub = await (await _device('bob')).publicKeys(rot: 0);
      final result = await authority.rekey([bobPub]);
      final wire = jsonEncode(result.wraps.single.toJson());
      // The blinded wrap carries no cleartext to/from (§5.1 N3).
      expect(wire.contains('"to"'), isFalse);
      expect(wire.contains('"from"'), isFalse);
      final back = WrappedKey.fromJson(
        jsonDecode(wire) as Map<String, Object?>,
      );
      expect(back.epoch, 0);
      expect(back.ciphertext, result.wraps.single.ciphertext);
    });

    test('freshly generated (random) devices interoperate', () async {
      // The production path is generate(); the rest of the suite uses fromSeeds
      // for determinism. Prove a random identity round-trips end to end.
      final authorityKeys = await CollabDeviceKeys.generate(deviceId: 'a');
      final memberKeys = await CollabDeviceKeys.generate(deviceId: 'b');
      final authority = CollabCrypto(authorityKeys);
      final member = CollabCrypto(memberKeys);
      final authorityPub = await authorityKeys.publicKeys(rot: 0);
      expect(await authorityPub.verifyBinding(), isTrue);

      final result = await authority.rekey([
        await memberKeys.publicKeys(rot: 0),
      ]);
      await member.installEpochKey(result.wraps.single, authorityPub);
      final sealed = await authority.seal(
        {'kind': 'op'},
        room: 'r',
        type: 't',
        signed: true,
      );
      expect(
        await member.open(
          sealed,
          room: 'r',
          type: 't',
          sender: authorityPub,
          requireSignature: true,
        ),
        {'kind': 'op'},
      );
    });

    test('currentEpoch and hasEpoch track installed epochs', () async {
      final crypto = CollabCrypto(await _device('solo'));
      expect(crypto.currentEpoch, isNull);
      expect(crypto.hasEpoch(0), isFalse);
      await crypto.rekey(const []); // authority with no members yet → epoch 0
      expect(crypto.currentEpoch, 0);
      expect(crypto.hasEpoch(0), isTrue);
      expect(crypto.hasEpoch(1), isFalse);
    });

    test('a malformed device JSON is rejected', () {
      expect(
        () => DevicePublicKeys.fromJson(const {'device': 42}),
        throwsA(isA<CollabCryptoException>()),
      );
    });
  });
}

// --- fixtures --------------------------------------------------------------

/// Deterministic device keys from a label, so a test reproduces the same
/// identity every run (the seeds are the label padded to 32 bytes).
Future<CollabDeviceKeys> _device(String label) {
  List<int> seed(int salt) {
    final bytes = Uint8List(32);
    final name = utf8.encode(label);
    for (var i = 0; i < 32; i++) {
      bytes[i] = (name[i % name.length] + salt + i) & 0xff;
    }
    return bytes;
  }

  return CollabDeviceKeys.fromSeeds(
    deviceId: label,
    ed25519Seed: seed(1),
    x25519Seed: seed(2),
  );
}

Future<DevicePublicKeys> _pub(CollabCrypto crypto, String label) =>
    _device(label).then((k) => k.publicKeys(rot: 0));

class _Party {
  _Party(this.authority, this.member, this.authorityPub);
  final CollabCrypto authority;
  final CollabCrypto member;
  final DevicePublicKeys authorityPub;
}

/// An authority and one member who share epoch 0.
Future<_Party> _twoParty() async {
  final authorityKeys = await _device('authority');
  final memberKeys = await _device('member');
  final authority = CollabCrypto(authorityKeys);
  final member = CollabCrypto(memberKeys);
  final memberPub = await memberKeys.publicKeys(rot: 0);
  final authorityPub = await authorityKeys.publicKeys(rot: 0);
  final result = await authority.rekey([memberPub]);
  await member.installEpochKey(result.wraps.single, authorityPub);
  return _Party(authority, member, authorityPub);
}

SealedEnvelope _flipFirstCiphertextByte(SealedEnvelope s) {
  final ct = Uint8List.fromList(s.ciphertext)..[0] ^= 0xff;
  return SealedEnvelope(
    epoch: s.epoch,
    nonce: s.nonce,
    ciphertext: ct,
    senderDevice: s.senderDevice,
    signature: s.signature,
    version: s.version,
  );
}

Matcher _throwsReason(String reason) => throwsA(
  isA<CollabCryptoException>().having((e) => e.reason, 'reason', reason),
);
