import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/deck.dart';
import '../models/document_signature.dart';
import 'markdown_service.dart';

/// Result of verifying a deck's document seal (§8 A1).
enum IntegrityStatus {
  /// The deck is not finalised/sealed — there is nothing to verify.
  notSealed,

  /// The recomputed content hash matches the stored seal: intact.
  intact,

  /// The recomputed content hash differs from the stored seal: the content was
  /// changed after finalising (tamper-evidence).
  changed,
}

/// The general "Document integrity" capability (§8 A1): compute and verify a
/// content seal over a deck, and produce a sealed copy.
///
/// The guarantee is deliberately **tamper-evidence**, not impossibility: a
/// `.md` handed to someone else can always be edited, but a mismatch between the
/// recomputed hash and the stored [Deck.sealHash] makes such an edit visible.
/// The hash is a SHA-512 over the canonicalised markdown content (styling and
/// the seal fields themselves excluded — see
/// [MarkdownService.canonicalContentForSeal]), using the `crypto` package.
class DocumentIntegrity {
  /// The one hash algorithm A1 uses. Recorded in the front matter so a future
  /// algorithm stays distinguishable.
  static const String algorithm = 'sha-512';

  final MarkdownService _md;

  DocumentIntegrity(this._md);

  /// Compute the SHA-512 seal hash over [deck]'s canonical content. Independent
  /// of any integrity metadata already on [deck], so sealing and re-verifying
  /// yield the same value for unchanged content.
  String computeHash(Deck deck) {
    final canonical = _md.canonicalContentForSeal(deck);
    return sha512.convert(utf8.encode(canonical)).toString();
  }

  /// Verify [deck] against its stored seal.
  IntegrityStatus verify(Deck deck) {
    if (!deck.finalized || deck.sealHash.isEmpty) {
      return IntegrityStatus.notSealed;
    }
    return computeHash(deck) == deck.sealHash
        ? IntegrityStatus.intact
        : IntegrityStatus.changed;
  }

  /// Return a finalised, sealed copy of [deck]: the content hash is computed
  /// over the current content (with the optional [signature] already folded in,
  /// so the signature is covered by the seal), then the finalise flag, hash,
  /// algorithm and timestamp are set. [at] defaults to now (UTC). Finalising is
  /// intentionally one-way in the UI — there is no matching "unseal" here.
  Deck seal(Deck deck, {DocumentSignature? signature, DateTime? at}) {
    // Start from a clean, non-finalised base without any prior seal fields so
    // the hash is over content only. The signature (if given) is content and
    // must be present before hashing.
    final base = deck.copyWith(
      finalized: false,
      sealHash: '',
      sealAlgo: '',
      sealAt: '',
      signature: (signature != null && signature.isNotEmpty) ? signature : null,
      clearSignature: signature != null && signature.isEmpty,
    );
    final hash = computeHash(base);
    final when = (at ?? DateTime.now()).toUtc();
    return base.copyWith(
      finalized: true,
      sealHash: hash,
      sealAlgo: algorithm,
      sealAt: when.toIso8601String(),
    );
  }
}

/// Convenience for widgets that only hold a [Deck] (e.g. the status bar badge):
/// verify [deck] with a fresh [MarkdownService]. Cheap; only meaningful for a
/// finalised deck, so callers typically guard on [Deck.finalized] first.
IntegrityStatus deckIntegrityStatus(Deck deck) =>
    DocumentIntegrity(MarkdownService()).verify(deck);
