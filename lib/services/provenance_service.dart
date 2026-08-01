// Signing and verifying a deck's cryptographic provenance (COLLABORATION Phase 2
// "Blok C"; `docs/design/PROVENANCE_SIGNATURE.md`). Thin glue over the crypto in
// `collab_crypto.dart` (the single crypto file — this service must never import
// `package:cryptography` itself) and the seal integrity check in
// `document_integrity.dart`.

import '../collab/collab_crypto.dart';
import '../collab/collab_participant.dart' show deviceFingerprint;
import '../models/deck.dart';
import '../models/provenance_signature.dart';
import 'document_integrity.dart';
import 'markdown_service.dart';

/// What a deck's provenance amounts to when it is opened.
enum ProvenanceStatus {
  /// No provenance signature present.
  none,

  /// The signature does not verify against its own identity key — forged, or the
  /// block was tampered with.
  invalid,

  /// The signature is valid over the hash it was made for, but the file's
  /// content no longer matches that hash: the deck was edited after signing.
  contentChanged,

  /// Valid, but the seal cannot be checked *here* (a git working copy or an
  /// `.ocideck` package rewrites asset paths — verify against the original
  /// `.md`). The signature itself is well-formed over the stored hash.
  notVerifiableHere,

  /// Valid and the content matches, but the signer's identity is not pinned — no
  /// authorship claim yet; compare the fingerprint out-of-band (Blok A).
  valid,

  /// Valid, content matches, and the signer's identity is pinned as verified.
  confirmed,
}

/// The result of [verifyDeckProvenance]: a [status] and the signer's readable
/// [fingerprint] (empty when there is no signature) for the UI to show.
class ProvenanceOutcome {
  const ProvenanceOutcome(this.status, this.fingerprint);
  final ProvenanceStatus status;
  final String fingerprint;
}

/// Sign [deck]'s provenance with [keys] and return a copy carrying the signature.
///
/// Requires a **sealed and saved** deck: the signature is over [Deck.sealHash],
/// which exists only once the file has been written (`recordWrittenBytes`) — so
/// callers save first, then sign. Throws [StateError] otherwise rather than
/// signing an empty hash.
Future<Deck> signDeckProvenance(
  Deck deck,
  CollabDeviceKeys keys, {
  DateTime? at,
}) async {
  if (deck.sealHash.isEmpty) {
    throw StateError('signDeckProvenance: the deck has no seal hash to sign');
  }
  final signedAt = (at ?? DateTime.now()).toUtc().toIso8601String();
  final form = deck.sealForm.key;
  final signature = await keys.signProvenance(
    form: form,
    algo: deck.sealAlgo,
    hash: deck.sealHash,
    signedAt: signedAt,
  );
  return deck.copyWith(
    provenance: ProvenanceSignature(
      alg: 'ed25519',
      preimage: kProvenancePreimageTag,
      identityKey: await keys.identityKeyBytes(),
      signature: signature,
      signedAt: signedAt,
    ),
  );
}

/// Verify [deck]'s provenance and report where it stands. [isPinned] answers
/// whether the signer's identity key is pinned as verified (from the device
/// trust store, Blok A); omit it to degrade to [ProvenanceStatus.valid] for a
/// good signature — never a false "confirmed".
Future<ProvenanceOutcome> verifyDeckProvenance(
  Deck deck, {
  bool Function(List<int> identityKey)? isPinned,
  DocumentIntegrity? integrity,
}) async {
  final prov = deck.provenance;
  if (prov == null || prov.isEmpty) {
    return const ProvenanceOutcome(ProvenanceStatus.none, '');
  }
  final fingerprint = deviceFingerprint(prov.identityKey);
  final sigOk = await verifyProvenance(
    identityKey: prov.identityKey,
    signature: prov.signature,
    form: deck.sealForm.key,
    algo: deck.sealAlgo,
    hash: deck.sealHash,
    signedAt: prov.signedAt,
  );
  if (!sigOk) return ProvenanceOutcome(ProvenanceStatus.invalid, fingerprint);

  // The signature matches the *stored* seal hash; now is the file still that
  // exact byte-state? That is exactly the seal's own integrity question.
  final status = (integrity ?? DocumentIntegrity(MarkdownService())).verify(
    deck,
  );
  switch (status) {
    case IntegrityStatus.changed:
      return ProvenanceOutcome(ProvenanceStatus.contentChanged, fingerprint);
    case IntegrityStatus.intact:
      final pinned = isPinned?.call(prov.identityKey) ?? false;
      return ProvenanceOutcome(
        pinned ? ProvenanceStatus.confirmed : ProvenanceStatus.valid,
        fingerprint,
      );
    default:
      // notSealed / notVerifiable / redactedDerivative: the signature is valid
      // but the current artefact cannot be matched to it here.
      return ProvenanceOutcome(ProvenanceStatus.notVerifiableHere, fingerprint);
  }
}
