import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/models/provenance_signature.dart';
import 'package:ocideck/models/seal_record.dart';
import 'package:ocideck/services/seal_codec.dart';

void main() {
  const form = 'file-bytes-v1';
  const algo = 'sha-512';
  const hash = '76f87f105c8936f';
  const signedAt = '2026-08-01T12:00:00.000Z';

  group('crypto sign/verify', () {
    late CollabDeviceKeys keys;
    late List<int> idKey;

    setUp(() async {
      keys = await CollabDeviceKeys.fromSeeds(
        deviceId: 'DEV',
        ed25519Seed: [for (var i = 0; i < 32; i++) i],
        x25519Seed: [for (var i = 0; i < 32; i++) i + 1],
      );
      idKey = await keys.identityKeyBytes();
    });

    test('a real signature verifies against the identity key', () async {
      final sig = await keys.signProvenance(
        form: form,
        algo: algo,
        hash: hash,
        signedAt: signedAt,
      );
      expect(
        await verifyProvenance(
          identityKey: idKey,
          signature: sig,
          form: form,
          algo: algo,
          hash: hash,
          signedAt: signedAt,
        ),
        isTrue,
      );
    });

    test('changing any signed field fails verification', () async {
      final sig = await keys.signProvenance(
        form: form,
        algo: algo,
        hash: hash,
        signedAt: signedAt,
      );
      // A different hash (content changed after signing).
      expect(
        await verifyProvenance(
          identityKey: idKey,
          signature: sig,
          form: form,
          algo: algo,
          hash: '${hash}00',
          signedAt: signedAt,
        ),
        isFalse,
      );
      // A tampered signed-at.
      expect(
        await verifyProvenance(
          identityKey: idKey,
          signature: sig,
          form: form,
          algo: algo,
          hash: hash,
          signedAt: '2020-01-01T00:00:00.000Z',
        ),
        isFalse,
      );
    });

    test(
      'a different identity key does not verify (no self-forgery)',
      () async {
        final sig = await keys.signProvenance(
          form: form,
          algo: algo,
          hash: hash,
          signedAt: signedAt,
        );
        final other = await CollabDeviceKeys.fromSeeds(
          deviceId: 'OTHER',
          ed25519Seed: [for (var i = 0; i < 32; i++) 99],
          x25519Seed: [for (var i = 0; i < 32; i++) 7],
        );
        expect(
          await verifyProvenance(
            identityKey: await other.identityKeyBytes(),
            signature: sig,
            form: form,
            algo: algo,
            hash: hash,
            signedAt: signedAt,
          ),
          isFalse,
        );
      },
    );

    test('the preimage is domain-separated (starts with the tag)', () {
      final pre = utf8.decode(
        provenancePreimage(
          form: form,
          algo: algo,
          hash: hash,
          signedAt: signedAt,
        ),
      );
      expect(pre, startsWith('["$kProvenancePreimageTag"'));
    });

    test('test vector: the exact preimage bytes are pinned', () {
      // A third party reconstructs these bytes verbatim from the .seal.json
      // provenance block. If this string ever changes, the format changed — the
      // build must fail loudly (FILE_FORMAT §6.6 / PROVENANCE_SIGNATURE §3).
      expect(
        utf8.decode(
          provenancePreimage(
            form: form,
            algo: algo,
            hash: hash,
            signedAt: signedAt,
          ),
        ),
        '["ocideck-provenance-v1","file-bytes-v1","sha-512","76f87f105c8936f",'
        '"2026-08-01T12:00:00.000Z"]',
      );
    });
  });

  group('ProvenanceSignature model', () {
    test('round-trips through JSON', () {
      final p = ProvenanceSignature(
        alg: 'ed25519',
        preimage: kProvenancePreimageTag,
        identityKey: [1, 2, 3, 4],
        signature: [5, 6, 7, 8],
        signedAt: signedAt,
      );
      expect(ProvenanceSignature.fromJson(p.toJson()), p);
    });

    test('fromJson returns null on a malformed block, never throws', () {
      expect(ProvenanceSignature.fromJson('nope'), isNull);
      expect(ProvenanceSignature.fromJson({'alg': 'ed25519'}), isNull);
      expect(
        ProvenanceSignature.fromJson({
          'alg': 'ed25519',
          'preimage': 't',
          'identity_key': '!!not base64!!',
          'signature': 'AA==',
          'signed_at': signedAt,
        }),
        isNull,
      );
    });
  });

  group('SealCodec with provenance', () {
    final prov = ProvenanceSignature(
      alg: 'ed25519',
      preimage: kProvenancePreimageTag,
      identityKey: [1, 2, 3],
      signature: [4, 5, 6],
      signedAt: signedAt,
    );

    test('a provenance block round-trips in the sidecar', () {
      final record = SealRecord(
        finalized: true,
        hash: hash,
        algo: algo,
        at: signedAt,
        provenance: prov,
      );
      final json = SealCodec.encode(record)!;
      final back = SealCodec.decode(json)!;
      expect(back.provenance, prov);
      expect(back.hash, hash);
    });

    test('a corrupt provenance block does not drop the surrounding seal', () {
      // A sealed sidecar whose provenance block is malformed (bad base64).
      final json = jsonEncode({
        'version': 1,
        'finalized': true,
        'hash': hash,
        'algo': algo,
        'form': form,
        'provenance': {
          'alg': 'ed25519',
          'preimage': kProvenancePreimageTag,
          'identity_key': '!!!!',
          'signature': '!!!!',
          'signed_at': signedAt,
        },
      });
      final back = SealCodec.decode(json);
      expect(back, isNotNull);
      expect(back!.hash, hash, reason: 'the seal must survive');
      expect(back.finalized, isTrue);
      expect(back.provenance, isNull, reason: 'only the bad block is dropped');
    });

    test('version stays 1 — an older build can still read the seal', () {
      final json = SealCodec.encode(
        SealRecord(finalized: true, hash: hash, algo: algo, provenance: prov),
      )!;
      expect(jsonDecode(json)['version'], 1);
    });
  });
}
