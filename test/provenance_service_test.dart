import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/provenance_signature.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/provenance_service.dart';

void main() {
  late CollabDeviceKeys keys;
  final integrity = DocumentIntegrity(MarkdownService());

  setUp(() async {
    keys = await CollabDeviceKeys.fromSeeds(
      deviceId: 'DEV',
      ed25519Seed: [for (var i = 0; i < 32; i++) i],
      x25519Seed: [for (var i = 0; i < 32; i++) i + 1],
    );
  });

  /// A finalised deck whose seal hash has been recorded (as a save would).
  Deck sealedDeck() {
    var deck = Deck(
      title: 'd',
      slides: [Slide.create(SlideType.bullets).copyWith(title: 'a')],
    );
    deck = integrity.seal(deck);
    return DocumentIntegrity.recordWrittenBytes(deck, '# the exact bytes\n');
  }

  test(
    'sign then verify yields valid (unpinned) for an untouched deck',
    () async {
      final signed = await signDeckProvenance(sealedDeck(), keys);
      expect(signed.provenance, isNotNull);
      final outcome = await verifyDeckProvenance(signed, integrity: integrity);
      expect(outcome.status, ProvenanceStatus.valid);
      expect(outcome.fingerprint, isNotEmpty);
    },
  );

  test('a pinned identity is confirmed', () async {
    final signed = await signDeckProvenance(sealedDeck(), keys);
    final pinnedKey = signed.provenance!.identityKey;
    final outcome = await verifyDeckProvenance(
      signed,
      integrity: integrity,
      isPinned: (k) => _sameBytes(k, pinnedKey),
    );
    expect(outcome.status, ProvenanceStatus.confirmed);
  });

  test('editing the deck after signing reads as contentChanged', () async {
    var signed = await signDeckProvenance(sealedDeck(), keys);
    // Simulate a save of different bytes: the recomputed file hash now differs
    // from the sealed hash the signature covers.
    signed = DocumentIntegrity.recordWrittenBytes(
      signed,
      '# different bytes\n',
    );
    final outcome = await verifyDeckProvenance(signed, integrity: integrity);
    expect(outcome.status, ProvenanceStatus.contentChanged);
  });

  test('a tampered signature reads as invalid', () async {
    final signed = await signDeckProvenance(sealedDeck(), keys);
    final p = signed.provenance!;
    final broken = signed.copyWith(
      provenance: ProvenanceSignature(
        alg: p.alg,
        preimage: p.preimage,
        identityKey: p.identityKey,
        signature: [...p.signature]..[0] ^= 0xff,
        signedAt: p.signedAt,
      ),
    );
    final outcome = await verifyDeckProvenance(broken, integrity: integrity);
    expect(outcome.status, ProvenanceStatus.invalid);
  });

  test('no provenance reads as none', () async {
    final outcome = await verifyDeckProvenance(
      sealedDeck(),
      integrity: integrity,
    );
    expect(outcome.status, ProvenanceStatus.none);
  });

  test('signing without a seal hash throws', () async {
    final unsealed = Deck(
      title: 'd',
      slides: [Slide.create(SlideType.bullets)],
    );
    expect(() => signDeckProvenance(unsealed, keys), throwsStateError);
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
