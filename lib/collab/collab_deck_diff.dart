// Turning a whole-deck edit into the ops that reproduce it
// (`docs/design/COLLABORATION.md` §5.1). The editor mutates the `Deck` model
// wholesale — one new `Deck` replaces the old on every keystroke or action — but
// the collaboration layer syncs *field-level* ops (P5), never a re-serialised
// deck. [deckDiffToOps] bridges the two: given the deck before and after an
// edit, it returns the [DeckOp]s that, applied in order to `before`, yield
// `after` exactly. A provider feeds each op to `CollabSession.submit`.
//
// This is the pragmatic v1 seam. The design's eventual model is the editor
// emitting ops at the source under a held slide lock (§5.4); diffing at the
// notifier boundary needs no lock and no rewrite of every editor mutation, at
// the cost of recomputing the change. It is exact for the syncable surface —
// the `SlideField`/`DeckMetaField` fields the op model covers — and by
// construction leaves everything outside that surface (table rows, annotations,
// the seal) alone, exactly as the op model does.
//
// The algorithm is ordered so it is correct for *any* before→after, not just a
// single-action edit: field edits on surviving slides first (keyed by id, so
// order-independent), then removes, then inserts appended to the end (an always-
// valid index), then reorders that sort the result into the target order. Insert
// carries the whole new slide (all its fields), so a fresh slide needs no
// follow-up field ops.

import '../models/deck.dart';
import '../models/slide.dart';
import 'deck_op.dart';

/// The ops that transform [before] into [after] when applied in order, each
/// stamped with [authorId] and an unassigned version (`0`) — the session
/// assigns the authoritative version on submit (§5.3). Empty when the decks are
/// already equal on the syncable surface.
List<DeckOp> deckDiffToOps(
  Deck before,
  Deck after, {
  required String authorId,
}) {
  final ops = <DeckOp>[];

  final beforeById = {for (final s in before.slides) s.id: s};
  final afterById = {for (final s in after.slides) s.id: s};

  // 1. Field edits on slides present in both, keyed by id.
  for (final slide in after.slides) {
    final old = beforeById[slide.id];
    if (old == null) continue; // a new slide — carried whole by InsertSlide
    for (final field in SlideField.values) {
      final now = slideFieldValue(slide, field);
      if (!_valuesEqual(slideFieldValue(old, field), now)) {
        ops.add(
          SetSlideField(
            version: 0,
            authorId: authorId,
            slideId: slide.id,
            field: field,
            value: now,
          ),
        );
      }
    }
  }

  // 2. Deck-level metadata edits.
  for (final field in DeckMetaField.values) {
    final now = deckMetaValue(after, field);
    if (!_valuesEqual(deckMetaValue(before, field), now)) {
      ops.add(
        SetDeckMeta(version: 0, authorId: authorId, field: field, value: now),
      );
    }
  }

  // 3. Removes: ids in before but not after.
  for (final slide in before.slides) {
    if (!afterById.containsKey(slide.id)) {
      ops.add(RemoveSlide(version: 0, authorId: authorId, slideId: slide.id));
    }
  }

  // 4. Inserts: ids in after but not before, appended (a valid index in the
  //    still-being-built list); step 5 moves them into place.
  final current = [
    for (final s in before.slides)
      if (afterById.containsKey(s.id)) s.id,
  ];
  for (final slide in after.slides) {
    if (!beforeById.containsKey(slide.id)) {
      ops.add(
        InsertSlide(
          version: 0,
          authorId: authorId,
          index: current.length,
          slide: slide,
        ),
      );
      current.add(slide.id);
    }
  }

  // 5. Reorders: sort `current` into `after`'s exact id order.
  ops.addAll(
    _reorderOps(current, [for (final s in after.slides) s.id], authorId),
  );

  return ops;
}

/// Selection-sort `current` into `target` (same id set) with [ReorderSlide] ops,
/// simulating each move so the emitted indices are the ones the receiver will
/// see when it applies them in order.
List<DeckOp> _reorderOps(
  List<String> current,
  List<String> target,
  String authorId,
) {
  final ops = <DeckOp>[];
  final work = [...current];
  for (var i = 0; i < target.length; i++) {
    if (work[i] == target[i]) continue;
    final j = work.indexOf(target[i], i);
    ops.add(
      ReorderSlide(
        version: 0,
        authorId: authorId,
        slideId: target[i],
        newIndex: i,
      ),
    );
    work.insert(i, work.removeAt(j));
  }
  return ops;
}

bool _valuesEqual(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return a == b;
}

/// Read the value of [field] on [slide]. The read counterpart of `applyOp`'s
/// per-field set in `deck_op.dart`; the exhaustive switch means a new
/// [SlideField] is a compile error here until it is handled.
Object? slideFieldValue(Slide slide, SlideField field) {
  return switch (field) {
    SlideField.type => slide.type,
    SlideField.listStyle => slide.listStyle,
    SlideField.tlp => slide.tlp,
    SlideField.title => slide.title,
    SlideField.subtitle => slide.subtitle,
    SlideField.columnTitle1 => slide.columnTitle1,
    SlideField.columnTitle2 => slide.columnTitle2,
    SlideField.imagePath => slide.imagePath,
    SlideField.imagePath2 => slide.imagePath2,
    SlideField.imageCaption => slide.imageCaption,
    SlideField.imageCaption2 => slide.imageCaption2,
    SlideField.imageAltText => slide.imageAltText,
    SlideField.imageAltText2 => slide.imageAltText2,
    SlideField.videoPath => slide.videoPath,
    SlideField.audioPath => slide.audioPath,
    SlideField.quote => slide.quote,
    SlideField.quoteAuthor => slide.quoteAuthor,
    SlideField.customMarkdown => slide.customMarkdown,
    SlideField.codeLanguage => slide.codeLanguage,
    SlideField.cssClass => slide.cssClass,
    SlideField.notes => slide.notes,
    SlideField.titleTextColorOverride => slide.titleTextColorOverride,
    SlideField.titleColumnLayout => slide.titleColumnLayout,
    SlideField.findingId => slide.findingId,
    SlideField.checklistScope => slide.checklistScope,
    SlideField.improvementTemplateId => slide.improvementTemplateId,
    SlideField.bullets => slide.bullets,
    SlideField.bullets2 => slide.bullets2,
    SlideField.showChecklistProgress => slide.showChecklistProgress,
    SlideField.continueNumbering => slide.continueNumbering,
    SlideField.continuesSplit => slide.continuesSplit,
    SlideField.videoAutoplay => slide.videoAutoplay,
    SlideField.audioAutoplay => slide.audioAutoplay,
    SlideField.titleImageOverlay => slide.titleImageOverlay,
    SlideField.showLogo => slide.showLogo,
    SlideField.showFooter => slide.showFooter,
    SlideField.skipped => slide.skipped,
    SlideField.isDetail => slide.isDetail,
    SlideField.tableEditable => slide.tableEditable,
    SlideField.tableMarkOverdue => slide.tableMarkOverdue,
    SlideField.videoStartMs => slide.videoStartMs,
    SlideField.videoEndMs => slide.videoEndMs,
    SlideField.imageSize => slide.imageSize,
    SlideField.titleColumnWidth => slide.titleColumnWidth,
    SlideField.imageFocalX => slide.imageFocalX,
    SlideField.imageFocalY => slide.imageFocalY,
    SlideField.imageFocalX2 => slide.imageFocalX2,
    SlideField.imageFocalY2 => slide.imageFocalY2,
    SlideField.advanceDuration => slide.advanceDuration,
  };
}

/// Read the value of [field] on [deck]. See [slideFieldValue].
Object? deckMetaValue(Deck deck, DeckMetaField field) {
  return switch (field) {
    DeckMetaField.title => deck.title,
    DeckMetaField.theme => deck.theme,
    DeckMetaField.author => deck.author,
    DeckMetaField.organization => deck.organization,
    DeckMetaField.version => deck.version,
    DeckMetaField.date => deck.date,
    DeckMetaField.description => deck.description,
    DeckMetaField.keywords => deck.keywords,
    DeckMetaField.language => deck.language,
    DeckMetaField.improvementFramework => deck.improvementFramework,
    DeckMetaField.tlp => deck.tlp,
    DeckMetaField.privacy => deck.privacy,
    DeckMetaField.paginate => deck.paginate,
    DeckMetaField.showRehearsalSummary => deck.showRehearsalSummary,
    DeckMetaField.playOnly => deck.playOnly,
    DeckMetaField.presentationTargetSeconds => deck.presentationTargetSeconds,
    DeckMetaField.standardsUsed => deck.standardsUsed,
  };
}
