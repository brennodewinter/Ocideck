import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/deck.dart';
import '../models/document_signature.dart';
import '../models/redaction_manifest.dart';
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

  /// Een geredigeerde afleiding van een verzegeld deck.
  ///
  /// Dit bestaat om een vals alarm te voorkomen, en dat is geen bijzaak. Een
  /// geredigeerd artefact heeft per definitie andere inhoud dan de bron, dus de
  /// hertelde hash wijkt af — en zonder deze status zou een auditor die het
  /// pakket natrekt tot "GEMANIPULEERD" concluderen. Een vals tamper-alarm op een
  /// echt rapport is erger dan geen integriteitscontrole hebben: het maakt het
  /// mechanisme onbetrouwbaar precies wanneer het ertoe doet.
  ///
  /// De controle loopt hier niet tegen de inhoudshash maar tegen het
  /// redactiemanifest (`redaction_manifest.dart`): elke redactie moet uit de
  /// bron terug te rekenen zijn, en er mogen er niet meer of minder zijn.
  redactedDerivative,
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

  /// Verifieer een **geredigeerde afleiding** tegen de bron waaruit hij komt.
  ///
  /// Dit is het pad voor een auditor die twee dingen heeft: het geredigeerde
  /// rapport (met zijn manifest) en de gezegelde bron. De inhoudshash klópt hier
  /// per definitie niet — dat is geen manipulatie maar redactie — dus de controle
  /// loopt tegen het manifest.
  ///
  /// [IntegrityStatus.changed] betekent hier: het manifest hoort niet bij deze
  /// bron. Er is een redactie toegevoegd, weggelaten, of hij verbergt iets anders
  /// dan hij beweert.
  IntegrityStatus verifyRedactedDerivative(
    RedactionManifest manifest,
    Deck source, {
    required bool Function(RedactionManifest, Deck) verifier,
  }) {
    if (!source.finalized || source.sealHash.isEmpty) {
      return IntegrityStatus.notSealed;
    }
    if (manifest.derivedFrom != source.sealHash) return IntegrityStatus.changed;
    if (computeHash(source) != source.sealHash) return IntegrityStatus.changed;
    return verifier(manifest, source)
        ? IntegrityStatus.redactedDerivative
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

/// The 1-based slide numbers that still carry unreviewed AI-assist markers
/// (AI_ASSIST §16.3, [Slide.aiAssistedFields]). While this is non-empty the deck
/// must **not** be sealed: the EIS 1.6 attestation has to cover human-verified
/// text, so every AI-drafted field must be reviewed and cleared first. AI
/// drafting (P3-AIA) sets the markers and clears them on review; nothing writes
/// them yet, so today this is empty for every hand-authored deck.
List<int> slidesWithUnreviewedAiMarkers(Deck deck) => [
  for (var i = 0; i < deck.slides.length; i++)
    if (deck.slides[i].aiAssistedFields.isNotEmpty) i + 1,
];

/// Whether any slide carries an unreviewed AI-assist marker — i.e. sealing is
/// blocked (see [slidesWithUnreviewedAiMarkers]).
bool deckHasUnreviewedAiMarkers(Deck deck) =>
    deck.slides.any((s) => s.aiAssistedFields.isNotEmpty);
