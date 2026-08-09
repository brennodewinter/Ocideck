// The typed operation model for real-time deck collaboration
// (`docs/design/COLLABORATION.md` §5.1). A [DeckOp] is one authoritative change
// to the in-memory [Deck], ordered by [DeckOp.version].
//
// Ops act on the typed `Deck`/`Slide` model, never on re-parsed Markdown (design
// invariant P5): a co-author's edit crosses the wire as a field-level *intent*,
// not a text diff whose escaping (`markdown_service.dart`'s caption-pipe
// sentinel, decimal video seconds, note `--\>`, cell `\<br>`) the receiver would
// have to re-derive. Applying ops in [DeckOp.version] order reproduces the
// authority's deck exactly.
//
// This file is the pure, network-free foundation of the collaboration layer
// (COLLABORATION.md Phase 0): it depends on nothing but the models and is fully
// unit-testable without a transport. [applyOp] is *fail-closed* — an op for a
// missing slide, an out-of-range index, or a value of the wrong type throws an
// [ArgumentError] rather than silently doing nothing, because a silent no-op
// would desynchronise the op stream (P3: the authority's deck must stay the one
// truth every replica converges to).
//
// The set of syncable fields is fixed by the [SlideField] and [DeckMetaField]
// enums. Making them enums rather than the design's raw `String field` buys a
// compile-time guarantee: the `switch` in [applyOp] is exhaustive, so adding an
// enum value without handling it is a compile error — the completeness of the
// mapping is enforced by the compiler, not by a test that might forget a case.
// Fields whose `copyWith` needs the "clear this nullable back to null" flag
// (e.g. `Slide.privacy`, `Slide.viewLimit`) are deliberately out of scope for
// this first version; a plain value cannot express "set to null", and the
// locking model (COLLABORATION.md §5.4, §12 Q2) makes the covered field surface
// sufficient for v1. The enums are the seam where later fields are added.

import '../models/deck.dart';
import '../models/privacy_disposition.dart';
import '../models/slide.dart';

/// A single authoritative change to a [Deck], ordered by [version].
///
/// [version] is assigned by the session authority and is monotonic per session;
/// [authorId] identifies the originator (a Matrix user id once networked, an
/// arbitrary participant id under the loopback transport used in tests).
sealed class DeckOp {
  const DeckOp({required this.version, required this.authorId});

  /// Monotonic per session, assigned by the authority (COLLABORATION.md §5.3).
  /// An op submitted by a non-authority carries [version] `0` (unassigned); the
  /// authority stamps the canonical version with [copyWithVersion] on commit.
  final int version;

  /// The op's originator.
  final String authorId;

  /// The same op with [version] replaced. Used by the session authority to
  /// stamp a monotonic version onto an intent before it broadcasts the
  /// authoritative op (COLLABORATION.md §5.3). Ops are immutable, so this
  /// returns a new instance.
  DeckOp copyWithVersion(int version);
}

/// Insert [slide] at [index] in the deck's slide list.
class InsertSlide extends DeckOp {
  const InsertSlide({
    required super.version,
    required super.authorId,
    required this.index,
    required this.slide,
  });

  final int index;
  final Slide slide;

  @override
  InsertSlide copyWithVersion(int version) => InsertSlide(
    version: version,
    authorId: authorId,
    index: index,
    slide: slide,
  );
}

/// Remove the slide whose [Slide.id] is [slideId].
class RemoveSlide extends DeckOp {
  const RemoveSlide({
    required super.version,
    required super.authorId,
    required this.slideId,
  });

  final String slideId;

  @override
  RemoveSlide copyWithVersion(int version) =>
      RemoveSlide(version: version, authorId: authorId, slideId: slideId);
}

/// Move the slide [slideId] to [newIndex] (its position after removal-and-
/// reinsertion, i.e. a plain list move).
class ReorderSlide extends DeckOp {
  const ReorderSlide({
    required super.version,
    required super.authorId,
    required this.slideId,
    required this.newIndex,
  });

  final String slideId;
  final int newIndex;

  @override
  ReorderSlide copyWithVersion(int version) => ReorderSlide(
    version: version,
    authorId: authorId,
    slideId: slideId,
    newIndex: newIndex,
  );
}

/// Set a single typed field of the slide [slideId] to [value].
///
/// [value] must match the runtime type [field] expects (see [SlideField]);
/// [applyOp] throws an [ArgumentError] otherwise.
class SetSlideField extends DeckOp {
  const SetSlideField({
    required super.version,
    required super.authorId,
    required this.slideId,
    required this.field,
    required this.value,
  });

  final String slideId;
  final SlideField field;
  final Object? value;

  @override
  SetSlideField copyWithVersion(int version) => SetSlideField(
    version: version,
    authorId: authorId,
    slideId: slideId,
    field: field,
    value: value,
  );
}

/// Set a single typed deck-level metadata field to [value].
class SetDeckMeta extends DeckOp {
  const SetDeckMeta({
    required super.version,
    required super.authorId,
    required this.field,
    required this.value,
  });

  final DeckMetaField field;
  final Object? value;

  @override
  SetDeckMeta copyWithVersion(int version) => SetDeckMeta(
    version: version,
    authorId: authorId,
    field: field,
    value: value,
  );
}

/// The slide fields a [SetSlideField] op can carry. The expected value type is
/// noted per group; [applyOp] validates it fail-closed.
enum SlideField {
  // — enums —
  type, // SlideType
  listStyle, // ListStyle
  tlp, // TlpLevel
  // — String —
  title,
  subtitle,
  columnTitle1,
  columnTitle2,
  imagePath,
  imagePath2,
  imageCaption,
  imageCaption2,
  imageAltText,
  imageAltText2,
  videoPath,
  audioPath,
  quote,
  quoteAuthor,
  customMarkdown,
  codeLanguage,
  cssClass,
  notes,
  titleTextColorOverride,
  findingId,
  checklistScope,
  improvementTemplateId,
  // — List<String> —
  bullets,
  bullets2,
  preservedMarpLines,
  // — bool —
  showChecklistProgress,
  continueNumbering,
  continuesSplit,
  videoAutoplay,
  audioAutoplay,
  titleImageOverlay,
  showLogo,
  showFooter,
  skipped,
  isDetail,
  tableEditable,
  tableMarkOverdue,
  // — int —
  videoStartMs,
  videoEndMs,
  imageSize,
  // — double —
  imageFocalX,
  imageFocalY,
  imageFocalX2,
  imageFocalY2,
  advanceDuration,
}

/// The deck-level metadata fields a [SetDeckMeta] op can carry.
enum DeckMetaField {
  // — String —
  title,
  theme,
  author,
  organization,
  version,
  date,
  description,
  keywords,
  language,
  improvementFramework,
  // — enums —
  tlp, // TlpLevel
  privacy, // PrivacyDisposition
  // — bool —
  paginate,
  showRehearsalSummary,
  playOnly,
  // — int —
  presentationTargetSeconds,
  // — List<String> —
  standardsUsed,
}

/// Apply [op] to [deck] and return the resulting deck. Pure: [deck] is not
/// mutated. Throws [ArgumentError] on any op that cannot be applied exactly
/// (missing slide, out-of-range index, wrong value type) — see the file header
/// on why this is fail-closed rather than a silent no-op.
Deck applyOp(Deck deck, DeckOp op) {
  return switch (op) {
    InsertSlide(:final index, :final slide) => _insertSlide(deck, index, slide),
    RemoveSlide(:final slideId) => _removeSlide(deck, slideId),
    ReorderSlide(:final slideId, :final newIndex) => _reorderSlide(
      deck,
      slideId,
      newIndex,
    ),
    SetSlideField(:final slideId, :final field, :final value) => _setSlideField(
      deck,
      slideId,
      field,
      value,
    ),
    SetDeckMeta(:final field, :final value) => _setDeckMeta(deck, field, value),
  };
}

Deck _insertSlide(Deck deck, int index, Slide slide) {
  if (index < 0 || index > deck.slides.length) {
    throw ArgumentError.value(
      index,
      'index',
      'InsertSlide index out of range for a deck of ${deck.slides.length} '
          'slide(s)',
    );
  }
  final slides = [...deck.slides]..insert(index, slide);
  return deck.copyWith(slides: slides);
}

Deck _removeSlide(Deck deck, String slideId) {
  final index = _indexOfSlide(deck, slideId);
  final slides = [...deck.slides]..removeAt(index);
  return deck.copyWith(slides: slides);
}

Deck _reorderSlide(Deck deck, String slideId, int newIndex) {
  if (newIndex < 0 || newIndex >= deck.slides.length) {
    throw ArgumentError.value(
      newIndex,
      'newIndex',
      'ReorderSlide index out of range for a deck of ${deck.slides.length} '
          'slide(s)',
    );
  }
  final from = _indexOfSlide(deck, slideId);
  final slides = [...deck.slides];
  final moved = slides.removeAt(from);
  slides.insert(newIndex, moved);
  return deck.copyWith(slides: slides);
}

Deck _setSlideField(
  Deck deck,
  String slideId,
  SlideField field,
  Object? value,
) {
  final index = _indexOfSlide(deck, slideId);
  final updated = _slideWithField(deck.slides[index], field, value);
  final slides = [...deck.slides];
  slides[index] = updated;
  return deck.copyWith(slides: slides);
}

/// Return [slide] with [field] set to [value], validating the value type.
Slide _slideWithField(Slide slide, SlideField field, Object? value) {
  return switch (field) {
    SlideField.type => slide.copyWith(type: _cast<SlideType>(value, field)),
    SlideField.listStyle => slide.copyWith(
      listStyle: _cast<ListStyle>(value, field),
    ),
    SlideField.tlp => slide.copyWith(tlp: _cast<TlpLevel>(value, field)),
    SlideField.title => slide.copyWith(title: _cast<String>(value, field)),
    SlideField.subtitle => slide.copyWith(
      subtitle: _cast<String>(value, field),
    ),
    SlideField.columnTitle1 => slide.copyWith(
      columnTitle1: _cast<String>(value, field),
    ),
    SlideField.columnTitle2 => slide.copyWith(
      columnTitle2: _cast<String>(value, field),
    ),
    SlideField.imagePath => slide.copyWith(
      imagePath: _cast<String>(value, field),
    ),
    SlideField.imagePath2 => slide.copyWith(
      imagePath2: _cast<String>(value, field),
    ),
    SlideField.imageCaption => slide.copyWith(
      imageCaption: _cast<String>(value, field),
    ),
    SlideField.imageCaption2 => slide.copyWith(
      imageCaption2: _cast<String>(value, field),
    ),
    SlideField.imageAltText => slide.copyWith(
      imageAltText: _cast<String>(value, field),
    ),
    SlideField.imageAltText2 => slide.copyWith(
      imageAltText2: _cast<String>(value, field),
    ),
    SlideField.videoPath => slide.copyWith(
      videoPath: _cast<String>(value, field),
    ),
    SlideField.audioPath => slide.copyWith(
      audioPath: _cast<String>(value, field),
    ),
    SlideField.quote => slide.copyWith(quote: _cast<String>(value, field)),
    SlideField.quoteAuthor => slide.copyWith(
      quoteAuthor: _cast<String>(value, field),
    ),
    SlideField.customMarkdown => slide.copyWith(
      customMarkdown: _cast<String>(value, field),
    ),
    SlideField.codeLanguage => slide.copyWith(
      codeLanguage: _cast<String>(value, field),
    ),
    SlideField.cssClass => slide.copyWith(
      cssClass: _cast<String>(value, field),
    ),
    SlideField.notes => slide.copyWith(notes: _cast<String>(value, field)),
    SlideField.titleTextColorOverride => slide.copyWith(
      titleTextColorOverride: _cast<String>(value, field),
    ),
    SlideField.findingId => slide.copyWith(
      findingId: _cast<String>(value, field),
    ),
    SlideField.checklistScope => slide.copyWith(
      checklistScope: _cast<String>(value, field),
    ),
    SlideField.improvementTemplateId => slide.copyWith(
      improvementTemplateId: _cast<String>(value, field),
    ),
    SlideField.bullets => slide.copyWith(
      bullets: _castList<String>(value, field),
    ),
    SlideField.bullets2 => slide.copyWith(
      bullets2: _castList<String>(value, field),
    ),
    SlideField.preservedMarpLines => slide.copyWith(
      preservedMarpLines: _castList<String>(value, field),
    ),
    SlideField.showChecklistProgress => slide.copyWith(
      showChecklistProgress: _cast<bool>(value, field),
    ),
    SlideField.continueNumbering => slide.copyWith(
      continueNumbering: _cast<bool>(value, field),
    ),
    SlideField.continuesSplit => slide.copyWith(
      continuesSplit: _cast<bool>(value, field),
    ),
    SlideField.videoAutoplay => slide.copyWith(
      videoAutoplay: _cast<bool>(value, field),
    ),
    SlideField.audioAutoplay => slide.copyWith(
      audioAutoplay: _cast<bool>(value, field),
    ),
    SlideField.titleImageOverlay => slide.copyWith(
      titleImageOverlay: _cast<bool>(value, field),
    ),
    SlideField.showLogo => slide.copyWith(showLogo: _cast<bool>(value, field)),
    SlideField.showFooter => slide.copyWith(
      showFooter: _cast<bool>(value, field),
    ),
    SlideField.skipped => slide.copyWith(skipped: _cast<bool>(value, field)),
    SlideField.isDetail => slide.copyWith(isDetail: _cast<bool>(value, field)),
    SlideField.tableEditable => slide.copyWith(
      tableEditable: _cast<bool>(value, field),
    ),
    SlideField.tableMarkOverdue => slide.copyWith(
      tableMarkOverdue: _cast<bool>(value, field),
    ),
    SlideField.videoStartMs => slide.copyWith(
      videoStartMs: _cast<int>(value, field),
    ),
    SlideField.videoEndMs => slide.copyWith(
      videoEndMs: _cast<int>(value, field),
    ),
    SlideField.imageSize => slide.copyWith(imageSize: _cast<int>(value, field)),
    SlideField.imageFocalX => slide.copyWith(
      imageFocalX: _cast<double>(value, field),
    ),
    SlideField.imageFocalY => slide.copyWith(
      imageFocalY: _cast<double>(value, field),
    ),
    SlideField.imageFocalX2 => slide.copyWith(
      imageFocalX2: _cast<double>(value, field),
    ),
    SlideField.imageFocalY2 => slide.copyWith(
      imageFocalY2: _cast<double>(value, field),
    ),
    SlideField.advanceDuration => slide.copyWith(
      advanceDuration: _cast<double>(value, field),
    ),
  };
}

Deck _setDeckMeta(Deck deck, DeckMetaField field, Object? value) {
  return switch (field) {
    DeckMetaField.title => deck.copyWith(title: _cast<String>(value, field)),
    DeckMetaField.theme => deck.copyWith(theme: _cast<String>(value, field)),
    DeckMetaField.author => deck.copyWith(author: _cast<String>(value, field)),
    DeckMetaField.organization => deck.copyWith(
      organization: _cast<String>(value, field),
    ),
    DeckMetaField.version => deck.copyWith(
      version: _cast<String>(value, field),
    ),
    DeckMetaField.date => deck.copyWith(date: _cast<String>(value, field)),
    DeckMetaField.description => deck.copyWith(
      description: _cast<String>(value, field),
    ),
    DeckMetaField.keywords => deck.copyWith(
      keywords: _cast<String>(value, field),
    ),
    DeckMetaField.language => deck.copyWith(
      language: _cast<String>(value, field),
    ),
    DeckMetaField.improvementFramework => deck.copyWith(
      improvementFramework: _cast<String>(value, field),
    ),
    DeckMetaField.tlp => deck.copyWith(tlp: _cast<TlpLevel>(value, field)),
    DeckMetaField.privacy => deck.copyWith(
      privacy: _cast<PrivacyDisposition>(value, field),
    ),
    DeckMetaField.paginate => deck.copyWith(
      paginate: _cast<bool>(value, field),
    ),
    DeckMetaField.showRehearsalSummary => deck.copyWith(
      showRehearsalSummary: _cast<bool>(value, field),
    ),
    DeckMetaField.playOnly => deck.copyWith(
      playOnly: _cast<bool>(value, field),
    ),
    DeckMetaField.presentationTargetSeconds => deck.copyWith(
      presentationTargetSeconds: _cast<int>(value, field),
    ),
    DeckMetaField.standardsUsed => deck.copyWith(
      standardsUsed: _castList<String>(value, field),
    ),
  };
}

int _indexOfSlide(Deck deck, String slideId) {
  final index = deck.slides.indexWhere((s) => s.id == slideId);
  if (index < 0) {
    throw ArgumentError.value(slideId, 'slideId', 'no slide with this id');
  }
  return index;
}

/// Cast [value] to [T], failing closed with a clear message naming the [field].
T _cast<T>(Object? value, Object field) {
  if (value is T) return value;
  throw ArgumentError.value(
    value,
    'value',
    'op for "$field" expected a $T but got ${value.runtimeType}',
  );
}

/// Like [_cast] but for a `List<T>` — a plain `value is List<T>` accepts a
/// `List<dynamic>` (e.g. a JSON-decoded list) that happens to hold only [T]s,
/// so re-wrap into a real `List<T>` and reject any stray element.
List<T> _castList<T>(Object? value, Object field) {
  if (value is List) {
    return value.map((e) => _cast<T>(e, field)).toList();
  }
  throw ArgumentError.value(
    value,
    'value',
    'op for "$field" expected a List<$T> but got ${value.runtimeType}',
  );
}
