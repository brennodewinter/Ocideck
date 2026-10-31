// The bridge between a tab's editable deck and a [CollabSession]
// (`docs/design/COLLABORATION.md` §5.7). It is where the two directions meet:
// a local edit becomes ops the session submits, and a change the session
// applies (the authority's own commit, or a remote co-author's op) flows back
// into the tab's deck. Kept free of Riverpod and Flutter — it takes plain
// read/write callbacks — so the subtle part (avoiding the echo loop, and
// merging without losing local non-syncable state) is unit-tested headlessly;
// the provider that owns one per tab and wires it to `deckProvider` is §5.7's
// remaining app glue.
//
// **The echo loop.** Writing the session's deck back into the tab would fire the
// tab's change listener, which would diff and submit again — forever. Two guards
// stop it: [_applyingRemote] suppresses [onLocalEdit] while a remote change is
// being written, and, belt-and-braces, [onLocalEdit] diffs against the session's
// own deck, so a write that merely echoes the session produces an empty diff and
// submits nothing regardless of listener timing.
//
// **Merge, not replace.** The op model syncs only the `SlideField`/`DeckMetaField`
// surface; a deck also holds fields it never syncs (table rows, annotations, the
// seal). Replacing the local deck with the session's would drop those. So a
// remote change is *merged*: adopt the session's syncable surface and slide
// structure onto the local deck, keeping local non-syncable fields of surviving
// slides. That merge is exactly `applyOps(local, deckDiffToOps(local, session))`
// — the diff carries only syncable/structural ops, so everything else is left as
// the local deck had it.

import 'dart:async';

import '../models/deck.dart';
import 'collab_deck_diff.dart';
import 'collab_session.dart';
import 'deck_op.dart';

/// Bridges a tab's deck (via [readDeck]/[writeDeck]) and a [session]. Construct
/// one after a session starts; call [onLocalEdit] whenever the tab's deck
/// changes from a local edit, and [dispose] to end it.
class CollabSessionController {
  CollabSessionController({
    required this.session,
    required this.readDeck,
    required this.writeDeck,
  }) {
    _sub = session.deckChanges.listen(_applySessionDeck);
    // Adopt whatever the session already holds (a joiner's caught-up baseline).
    _applySessionDeck(session.deck);
  }

  final CollabSession session;

  /// The tab's current deck.
  final Deck Function() readDeck;

  /// Replace the tab's deck (with a merged result, never a raw session deck).
  final void Function(Deck deck) writeDeck;

  late final StreamSubscription<Deck> _sub;
  bool _applyingRemote = false;
  bool _disposed = false;

  /// Ingediende waarden per dia-veld, oudste eerst. Een echo van een eerdere
  /// aanslag mag een nieuwere lokale intentie niet terugzetten (#2680).
  final Map<String, List<Object?>> _inflight = {};

  /// Veldwaarde in de sessie op het moment van de eerste openstaande
  /// indiening. Zolang de sessie die nog toont, is ze niet bij — dat is geen
  /// wijziging van een co-auteur.
  final Map<String, Object?> _baseline = {};

  String get participantId => session.participantId;

  /// Feed a local edit into the session: diff the tab's [newLocal] deck against
  /// the session's and submit the resulting ops. A no-op while a remote change
  /// is being applied (the echo guard), and naturally empty when [newLocal]
  /// only echoes the session.
  void onLocalEdit(Deck newLocal) {
    if (_disposed || _applyingRemote) return;
    final ops = deckDiffToOps(session.deck, newLocal, authorId: participantId);
    for (final op in ops) {
      _rememberPending(op);
      session.submit(op);
    }
  }

  void _rememberPending(DeckOp op) {
    if (op is! SetSlideField) return;
    final key = _fieldKey(op.slideId, op.field);
    final sent = _inflight.putIfAbsent(key, () => []);
    if (sent.isEmpty && !_baseline.containsKey(key)) {
      Object? before;
      for (final candidate in session.deck.slides) {
        if (candidate.id == op.slideId) {
          before = slideFieldValue(candidate, op.field);
        }
      }
      _baseline[key] = before;
    }
    sent.add(op.value);
  }

  void _clearField(String key) {
    _inflight.remove(key);
    _baseline.remove(key);
  }

  void _applySessionDeck(Deck sessionDeck) {
    if (_disposed) return;
    _applyingRemote = true;
    try {
      final local = readDeck();
      final ops = deckDiffToOps(local, sessionDeck, authorId: participantId);
      // Een echo die niets verandert mag de revisie niet ophogen en het
      // deck niet vuil maken. Bij de host is dat elke eigen aanslag.
      if (ops.isEmpty) {
        _dropPendingMatchedBy(sessionDeck);
        return;
      }
      final applicable = <DeckOp>[
        for (final op in ops)
          if (_shouldApply(op)) op,
      ];
      if (applicable.isEmpty) return;
      writeDeck(applicable.fold(local, applyOp));
    } finally {
      _applyingRemote = false;
    }
  }

  /// Een echo van onze eigen laatste waarde is al lokaal toegepast. Een
  /// oudere echo, terwijl er een nieuwere waarde onderweg is, slaan we over
  /// zodat de gast niet terugspringt. Een waarde die we niet zelf indienden
  /// is van een co-auteur en blijft staan.
  bool _shouldApply(DeckOp op) {
    if (op is! SetSlideField) return true;
    final key = _fieldKey(op.slideId, op.field);
    final sent = _inflight[key];
    if (sent == null || sent.isEmpty) return true;
    if (_baseline.containsKey(key) &&
        collabValuesEqual(_baseline[key], op.value)) {
      return false;
    }
    final index = sent.indexWhere((v) => collabValuesEqual(v, op.value));
    if (index < 0) {
      _clearField(key);
      return true;
    }
    sent.removeRange(0, index + 1);
    if (sent.isEmpty) _clearField(key);
    return false;
  }

  void _dropPendingMatchedBy(Deck sessionDeck) {
    if (_inflight.isEmpty) return;
    final byId = {for (final slide in sessionDeck.slides) slide.id: slide};
    final done = <String>[];
    for (final entry in _inflight.entries) {
      final parts = entry.key.split('\u0000');
      if (parts.length != 2) continue;
      final slide = byId[parts[0]];
      if (slide == null) continue;
      final field = SlideField.values.where((f) => f.name == parts[1]);
      if (field.isEmpty) continue;
      final sent = entry.value;
      final now = slideFieldValue(slide, field.first);
      final index = sent.indexWhere((v) => collabValuesEqual(v, now));
      if (index < 0) continue;
      done.add(entry.key);
    }
    for (final key in done) {
      final sent = _inflight[key]!;
      final slide = byId[key.split('\u0000').first]!;
      final field = SlideField.values.firstWhere(
        (f) => f.name == key.split('\u0000')[1],
      );
      final now = slideFieldValue(slide, field);
      final index = sent.indexWhere((v) => collabValuesEqual(v, now));
      if (index >= 0) sent.removeRange(0, index + 1);
      if (sent.isEmpty) _clearField(key);
    }
  }

  String _fieldKey(String slideId, SlideField field) =>
      '$slideId\u0000${field.name}';

  /// Stop bridging and dispose the underlying session. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub.cancel();
    await session.dispose();
  }
}
