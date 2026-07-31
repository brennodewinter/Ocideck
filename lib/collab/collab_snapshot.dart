// The session baseline a joiner starts from (`docs/design/COLLABORATION.md`
// §5.2, §5.5). A [CollabSnapshot] is the authority's slide list at a known op
// [version], serialised to JSON and written once to the session sidecar; a
// joiner reads it before applying ops so it starts from the same deck.
//
// **Why it carries the slides and not the whole `Deck`.** `Slide.id` is a fresh
// UUID on every `parseDeck()` (§5.5), so two participants who each open the same
// `.md` hold structurally identical decks with *different* slide ids — and every
// op is keyed by slide id, so without a shared id space they desync on the first
// edit. The snapshot fixes that by shipping the authority's slides *with their
// ids*; the joiner adopts them wholesale. It deliberately does **not** re-ship
// the rest of the `Deck` (theme profile, annotations, seal, front matter): that
// is the durable content of the shared `.md` both sides already have (P2), not
// the transient collab baseline. Deck-level metadata that a co-author *changes*
// mid-session rides the op stream as `SetDeckMeta` (§5.1), and re-baselining the
// full metadata is a follow-up (§5.2) — this is the minimum that makes ops
// converge.
//
// JSON of the model, never a Markdown round-trip: re-parsing would regenerate
// the very ids this exists to pin (§5.5, P5). Decoding is fail-closed, like the
// op codec it sits beside.

import '../models/deck.dart';
import '../models/slide.dart';
import 'collab_codec.dart';

/// The authority's deck state at [version], enough for a joiner to share its
/// slide-id space (§5.5) before replaying ops.
class CollabSnapshot {
  const CollabSnapshot({
    required this.version,
    required this.seq,
    required this.slides,
  });

  /// The op version this baseline is taken at: a joiner starts its session at
  /// this version and applies only ops whose version is higher (§5.3).
  final int version;

  /// The highest log **sequence number** this baseline already subsumes (§5.2
  /// re-baselining). A joiner starts its transport just above this, so it fetches
  /// only the records posted since the baseline instead of replaying the whole
  /// log from the start. `0` for a fresh session (baseline at version 0).
  final int seq;

  /// The authority's slides, ids included. A joiner adopts these verbatim.
  final List<Slide> slides;

  /// Capture the current baseline of [deck] at op [version], subsuming the log up
  /// to [seq]. A fresh baseline is `capture(deck, 0, 0)`; a periodic re-baseline
  /// is `capture(deck, currentVersion, transport.lastSeq)`.
  factory CollabSnapshot.capture(Deck deck, int version, int seq) =>
      CollabSnapshot(version: version, seq: seq, slides: deck.slides);

  /// Rebase [base] onto this snapshot: the same deck, but carrying the
  /// authority's slides (and thus their ids). Everything else about [base] —
  /// the durable content it parsed from the shared `.md` — is left untouched.
  Deck applyTo(Deck base) => base.copyWith(slides: slides);

  Map<String, Object?> toJson() => {
    'version': version,
    'seq': seq,
    'slides': slides.map(slideToJson).toList(),
  };

  /// Decode a snapshot written by [toJson]. Fail-closed: a malformed baseline
  /// throws rather than yielding a half-built deck that would desync every op. A
  /// missing `seq` decodes as `0` — a baseline written before §5.2 re-baselining
  /// sat at version 0 and subsumed nothing.
  factory CollabSnapshot.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! int) {
      throw FormatException('snapshot "version" is not an int');
    }
    final rawSeq = json['seq'];
    if (rawSeq != null && rawSeq is! int) {
      throw FormatException('snapshot "seq" is not an int');
    }
    final rawSlides = json['slides'];
    if (rawSlides is! List) {
      throw FormatException('snapshot "slides" is not a list');
    }
    return CollabSnapshot(
      version: version,
      seq: (rawSeq as int?) ?? 0,
      slides: rawSlides.map((s) {
        if (s is Map<String, Object?>) return slideFromJson(s);
        if (s is Map) {
          return slideFromJson(s.map((k, v) => MapEntry(k.toString(), v)));
        }
        throw FormatException('snapshot slide is not an object');
      }).toList(),
    );
  }
}
