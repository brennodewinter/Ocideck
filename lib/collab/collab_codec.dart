// The wire (de)serialiser for the collaboration layer: [DeckOp]s and
// [LockEvent]s to and from JSON (`docs/design/COLLABORATION.md` §5.2, §5.6).
//
// This is the "dedicated model (de)serialiser" §5.2 asks for, and it is JSON of
// the typed `Deck`/`Slide` fields *by design*, not a Markdown round-trip:
// re-parsing Markdown would regenerate every `Slide.id` (§5.5) and re-derive the
// escaping the typed op model exists to avoid (P5). A [WebdavAsyncTransport]
// persists these records to a sidecar op log; the loopback transport needs no
// serialisation at all, which is why this lives beside the transports rather
// than inside one.
//
// Every decoder is *fail-closed* (P3, mirroring `applyOp` in `deck_op.dart`): a
// record with an unknown discriminator, a missing field, or a value of the
// wrong shape throws a [FormatException] rather than yielding a half-built op
// that would silently desync the stream. Enums cross the wire as their `.name`;
// an unknown name throws rather than falling back to a default, because a
// silent default is exactly the kind of drift the op model rules out.
//
// Completeness of the per-field value mapping (`_slideFieldKinds`,
// `_deckMetaKinds`) is guarded by a test that iterates `SlideField.values` /
// `DeckMetaField.values`: adding an enum value without a kind is a red test, not
// a runtime surprise. The full-[Slide] mapping (used only by [InsertSlide]) has
// no such enum to iterate, so it is guarded by an exhaustive round-trip test
// over a maximally-populated slide, the same discipline the Markdown serialiser
// relies on.

import 'dart:convert';

import '../models/deck.dart';
import '../models/display_window_spec.dart';
import '../models/marp_style.dart';
import '../models/menu.dart';
import '../models/privacy_disposition.dart';
import '../models/quality_disposition.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/timeline.dart';
import '../services/improvement/gantt_dsl.dart';
import 'collab_transport.dart';
import 'deck_op.dart';

// ── Public API ───────────────────────────────────────────────────────────────

/// Encode [op] to a JSON-safe map. The inverse of [deckOpFromJson].
Map<String, Object?> deckOpToJson(DeckOp op) {
  final base = <String, Object?>{
    'version': op.version,
    'authorId': op.authorId,
  };
  return switch (op) {
    InsertSlide(:final index, :final slide) => {
      ...base,
      'op': 'insertSlide',
      'index': index,
      'slide': slideToJson(slide),
    },
    RemoveSlide(:final slideId) => {
      ...base,
      'op': 'removeSlide',
      'slideId': slideId,
    },
    ReorderSlide(:final slideId, :final newIndex) => {
      ...base,
      'op': 'reorderSlide',
      'slideId': slideId,
      'newIndex': newIndex,
    },
    SetSlideField(:final slideId, :final field, :final value) => {
      ...base,
      'op': 'setSlideField',
      'slideId': slideId,
      'field': field.name,
      'value': _encodeValue(_slideFieldKind(field), value),
    },
    SetDeckMeta(:final field, :final value) => {
      ...base,
      'op': 'setDeckMeta',
      'field': field.name,
      'value': _encodeValue(_deckMetaKind(field), value),
    },
  };
}

/// Decode a [DeckOp] from a map produced by [deckOpToJson]. Fail-closed.
DeckOp deckOpFromJson(Map<String, Object?> json) {
  final op = _str(json, 'op');
  final version = _int(json, 'version');
  final authorId = _str(json, 'authorId');
  switch (op) {
    case 'insertSlide':
      return InsertSlide(
        version: version,
        authorId: authorId,
        index: _int(json, 'index'),
        slide: slideFromJson(_map(json, 'slide')),
      );
    case 'removeSlide':
      return RemoveSlide(
        version: version,
        authorId: authorId,
        slideId: _str(json, 'slideId'),
      );
    case 'reorderSlide':
      return ReorderSlide(
        version: version,
        authorId: authorId,
        slideId: _str(json, 'slideId'),
        newIndex: _int(json, 'newIndex'),
      );
    case 'setSlideField':
      final field = _enumByName(
        SlideField.values,
        _str(json, 'field'),
        'field',
      );
      return SetSlideField(
        version: version,
        authorId: authorId,
        slideId: _str(json, 'slideId'),
        field: field,
        value: _decodeValue(_slideFieldKind(field), json['value'], 'value'),
      );
    case 'setDeckMeta':
      final field = _enumByName(
        DeckMetaField.values,
        _str(json, 'field'),
        'field',
      );
      return SetDeckMeta(
        version: version,
        authorId: authorId,
        field: field,
        value: _decodeValue(_deckMetaKind(field), json['value'], 'value'),
      );
    default:
      throw FormatException('unknown op discriminator "$op"');
  }
}

/// Encode a [LockEvent]. The transport tags who sent it; [participantId] is
/// carried here too so a decoded event is self-describing.
Map<String, Object?> lockEventToJson(LockEvent e) => {
  'slideId': e.slideId,
  'held': e.held,
  'participantId': e.participantId,
  'forced': e.forced,
};

/// Decode a [LockEvent] from a map produced by [lockEventToJson]. Fail-closed.
LockEvent lockEventFromJson(Map<String, Object?> json) => LockEvent(
  slideId: _str(json, 'slideId'),
  held: _bool(json, 'held'),
  participantId: _str(json, 'participantId'),
  forced: _bool(json, 'forced'),
);

// ── Slide (de)serialiser ─────────────────────────────────────────────────────

/// Serialise a whole [Slide] to a JSON-safe map. Every field is carried so the
/// receiver reproduces the slide exactly (P3); the transient projection/render
/// fields (`mediaRedacted`, `contentRedacted`, `renderPage`) are included for
/// completeness rather than assumed to be at their defaults.
Map<String, Object?> slideToJson(Slide s) => {
  'id': s.id,
  'type': s.type.name,
  'title': s.title,
  'subtitle': s.subtitle,
  'bullets': s.bullets,
  'bullets2': s.bullets2,
  'listStyle': s.listStyle.name,
  'showChecklistProgress': s.showChecklistProgress,
  'continueNumbering': s.continueNumbering,
  'continuesSplit': s.continuesSplit,
  'columnTitle1': s.columnTitle1,
  'columnTitle2': s.columnTitle2,
  'imagePath': s.imagePath,
  'imagePath2': s.imagePath2,
  'imageCaption': s.imageCaption,
  'imageCaption2': s.imageCaption2,
  'imageAltText': s.imageAltText,
  'imageAltText2': s.imageAltText2,
  'imageFocalX': s.imageFocalX,
  'imageFocalY': s.imageFocalY,
  'imageFocalX2': s.imageFocalX2,
  'imageFocalY2': s.imageFocalY2,
  'videoPath': s.videoPath,
  'videoAutoplay': s.videoAutoplay,
  'videoStartMs': s.videoStartMs,
  'videoEndMs': s.videoEndMs,
  'audioPath': s.audioPath,
  'audioAutoplay': s.audioAutoplay,
  'mediaRedacted': s.mediaRedacted,
  'contentRedacted': s.contentRedacted,
  'quote': s.quote,
  'quoteAuthor': s.quoteAuthor,
  'customMarkdown': s.customMarkdown,
  'codeLanguage': s.codeLanguage,
  'cssClass': s.cssClass,
  'notes': s.notes,
  'preservedMarpLines': s.preservedMarpLines,
  'marpStyle': s.marpStyle.toJson(),
  'advanceDuration': s.advanceDuration,
  'imageSize': s.imageSize,
  'imageZoom': s.imageZoom,
  'titleImageOverlay': s.titleImageOverlay,
  'imageTitleAbove': s.imageTitleAbove,
  'titleTextColorOverride': s.titleTextColorOverride,
  'titleColumnLayout': s.titleColumnLayout.name,
  'titleColumnWidth': s.titleColumnWidth,
  'bulletMarkerOverride': s.bulletMarkerOverride?.name,
  'showLogo': s.showLogo,
  'showFooter': s.showFooter,
  'skipped': s.skipped,
  'tlp': s.tlp.name,
  'privacy': s.privacy?.name,
  'quality': s.quality.name,
  'tableRows': s.tableRows,
  'tableEditable': s.tableEditable,
  'tableMarkOverdue': s.tableMarkOverdue,
  'viewLimit': s.viewLimit == null ? null : _viewLimitToJson(s.viewLimit!),
  'isDetail': s.isDetail,
  'timelineLayout': s.timelineLayout.name,
  'timelineReveal': s.timelineReveal.name,
  'timelineAnimationMs': s.timelineAnimationMs,
  'timelineCurrentIndex': s.timelineCurrentIndex,
  'findingId': s.findingId,
  'findingRole': s.findingRole.name,
  'aiAssistedFields': s.aiAssistedFields,
  'checklistScope': s.checklistScope,
  'improvementTemplateId': s.improvementTemplateId,
  'improvementLayout': s.improvementLayout,
  'anchor': s.anchor,
  'nextAnchor': s.nextAnchor,
  'ganttScale': s.ganttScale,
  'ganttSections': s.ganttSections,
  'menuLayout': s.menuLayout.name,
  'tableColumnAlignments': s.tableColumnAlignments.map((e) => e.name).toList(),
  'tableNumberColumns': s.tableNumberColumns,
  'renderPage': s.renderPage,
};

/// Rebuild a [Slide] from a map produced by [slideToJson]. Fail-closed.
Slide slideFromJson(Map<String, Object?> j) => Slide(
  id: _str(j, 'id'),
  type: _enumByName(SlideType.values, _str(j, 'type'), 'type'),
  title: _str(j, 'title'),
  subtitle: _str(j, 'subtitle'),
  bullets: _strList(j, 'bullets'),
  bullets2: _strList(j, 'bullets2'),
  listStyle: _enumByName(ListStyle.values, _str(j, 'listStyle'), 'listStyle'),
  showChecklistProgress: _bool(j, 'showChecklistProgress'),
  continueNumbering: _bool(j, 'continueNumbering'),
  continuesSplit: _bool(j, 'continuesSplit'),
  columnTitle1: _str(j, 'columnTitle1'),
  columnTitle2: _str(j, 'columnTitle2'),
  imagePath: _str(j, 'imagePath'),
  imagePath2: _str(j, 'imagePath2'),
  imageCaption: _str(j, 'imageCaption'),
  imageCaption2: _str(j, 'imageCaption2'),
  imageAltText: _str(j, 'imageAltText'),
  imageAltText2: _str(j, 'imageAltText2'),
  imageFocalX: _double(j, 'imageFocalX'),
  imageFocalY: _double(j, 'imageFocalY'),
  imageFocalX2: _double(j, 'imageFocalX2'),
  imageFocalY2: _double(j, 'imageFocalY2'),
  videoPath: _str(j, 'videoPath'),
  videoAutoplay: _bool(j, 'videoAutoplay'),
  videoStartMs: _int(j, 'videoStartMs'),
  videoEndMs: _int(j, 'videoEndMs'),
  audioPath: _str(j, 'audioPath'),
  audioAutoplay: _bool(j, 'audioAutoplay'),
  mediaRedacted: _bool(j, 'mediaRedacted'),
  contentRedacted: _bool(j, 'contentRedacted'),
  quote: _str(j, 'quote'),
  quoteAuthor: _str(j, 'quoteAuthor'),
  customMarkdown: _str(j, 'customMarkdown'),
  codeLanguage: _str(j, 'codeLanguage'),
  cssClass: _str(j, 'cssClass'),
  notes: _str(j, 'notes'),
  preservedMarpLines: j['preservedMarpLines'] == null
      ? const []
      : _strList(j, 'preservedMarpLines'),
  marpStyle: j['marpStyle'] == null
      ? const MarpStyle()
      : MarpStyle.fromJson(_map(j, 'marpStyle')),
  advanceDuration: _double(j, 'advanceDuration'),
  imageSize: _int(j, 'imageSize'),
  imageZoom: _int(j, 'imageZoom'),
  titleImageOverlay: _bool(j, 'titleImageOverlay'),
  imageTitleAbove: _bool(j, 'imageTitleAbove'),
  titleTextColorOverride: _str(j, 'titleTextColorOverride'),
  titleColumnLayout: _enumByName(
    TitleColumnLayout.values,
    _str(j, 'titleColumnLayout'),
    'titleColumnLayout',
  ),
  titleColumnWidth: _int(j, 'titleColumnWidth'),
  bulletMarkerOverride: _enumOrNull(
    BulletMarker.values,
    j['bulletMarkerOverride'],
    'bulletMarkerOverride',
  ),
  showLogo: _bool(j, 'showLogo'),
  showFooter: _bool(j, 'showFooter'),
  skipped: _bool(j, 'skipped'),
  tlp: _enumByName(TlpLevel.values, _str(j, 'tlp'), 'tlp'),
  privacy: _enumOrNull(PrivacyDisposition.values, j['privacy'], 'privacy'),
  quality: _enumByName(
    QualityDisposition.values,
    _str(j, 'quality'),
    'quality',
  ),
  tableRows: _rows(j, 'tableRows'),
  tableEditable: _bool(j, 'tableEditable'),
  tableMarkOverdue: _bool(j, 'tableMarkOverdue'),
  viewLimit: j['viewLimit'] == null
      ? null
      : _viewLimitFromJson(_map(j, 'viewLimit')),
  isDetail: _bool(j, 'isDetail'),
  timelineLayout: _enumByName(
    TimelineLayout.values,
    _str(j, 'timelineLayout'),
    'timelineLayout',
  ),
  timelineReveal: _enumByName(
    TimelineReveal.values,
    _str(j, 'timelineReveal'),
    'timelineReveal',
  ),
  timelineAnimationMs: _intOrNull(
    j['timelineAnimationMs'],
    'timelineAnimationMs',
  ),
  timelineCurrentIndex: _intOrNull(
    j['timelineCurrentIndex'],
    'timelineCurrentIndex',
  ),
  findingId: _str(j, 'findingId'),
  findingRole: _enumByName(
    FindingRole.values,
    _str(j, 'findingRole'),
    'findingRole',
  ),
  aiAssistedFields: _strList(j, 'aiAssistedFields'),
  checklistScope: _str(j, 'checklistScope'),
  improvementTemplateId: _str(j, 'improvementTemplateId'),
  improvementLayout: _str(j, 'improvementLayout'),
  anchor: j['anchor'] == null ? '' : _str(j, 'anchor'),
  nextAnchor: j['nextAnchor'] == null ? '' : _str(j, 'nextAnchor'),
  ganttScale: j['ganttScale'] == null ? ganttScaleAuto : _str(j, 'ganttScale'),
  ganttSections: j['ganttSections'] == null ? false : _bool(j, 'ganttSections'),
  menuLayout: j['menuLayout'] == null
      ? MenuLayout.grid
      : _enumByName(MenuLayout.values, _str(j, 'menuLayout'), 'menuLayout'),
  tableColumnAlignments: j['tableColumnAlignments'] == null
      ? const []
      : _enumList(j, 'tableColumnAlignments', TableAlign.values),
  tableNumberColumns: j['tableNumberColumns'] == null
      ? const []
      : _boolList(j, 'tableNumberColumns'),
  renderPage: _int(j, 'renderPage'),
);

Map<String, Object?> _viewLimitToJson(DisplayWindowSpec v) => {
  'limit': v.limit,
  'mode': v.mode.name,
  'key': v.key,
  'remainder': v.remainder.name,
  'showCount': v.showCount,
};

DisplayWindowSpec _viewLimitFromJson(Map<String, Object?> j) =>
    DisplayWindowSpec(
      limit: _intOrNull(j['limit'], 'limit'),
      mode: _enumByName(DisplayWindowMode.values, _str(j, 'mode'), 'mode'),
      key: _str(j, 'key'),
      remainder: _enumByName(
        DisplayWindowRemainder.values,
        _str(j, 'remainder'),
        'remainder',
      ),
      showCount: _bool(j, 'showCount'),
    );

// ── Per-field value kinds ────────────────────────────────────────────────────

/// The wire shape of a [SetSlideField]/[SetDeckMeta] value. The field enums map
/// onto these, so the encoder/decoder switch over a handful of kinds instead of
/// dozens of fields; the field→kind maps are what the completeness test checks.
enum _ValueKind {
  str,
  boolean,
  integer,
  real,
  stringList,
  slideType,
  listStyle,
  tlp,
  privacy,
  marpStyle,
  titleColumnLayout,
  menuLayout,
  tableAlignList,
  boolList,
  timelineLayout,
  timelineReveal,
  bulletMarker,
  quality,
  findingRole,
  viewLimit,
}

_ValueKind _slideFieldKind(SlideField f) {
  final kind = _slideFieldKinds[f];
  if (kind == null) {
    throw FormatException('no wire kind for SlideField.${f.name}');
  }
  return kind;
}

_ValueKind _deckMetaKind(DeckMetaField f) {
  final kind = _deckMetaKinds[f];
  if (kind == null) {
    throw FormatException('no wire kind for DeckMetaField.${f.name}');
  }
  return kind;
}

/// Mirrors the value types `applyOp` casts each [SlideField] to in
/// `deck_op.dart`. A test asserts every `SlideField.values` entry is present.
const Map<SlideField, _ValueKind> _slideFieldKinds = {
  SlideField.type: _ValueKind.slideType,
  SlideField.listStyle: _ValueKind.listStyle,
  SlideField.tlp: _ValueKind.tlp,
  SlideField.title: _ValueKind.str,
  SlideField.subtitle: _ValueKind.str,
  SlideField.columnTitle1: _ValueKind.str,
  SlideField.columnTitle2: _ValueKind.str,
  SlideField.imagePath: _ValueKind.str,
  SlideField.imagePath2: _ValueKind.str,
  SlideField.imageCaption: _ValueKind.str,
  SlideField.imageCaption2: _ValueKind.str,
  SlideField.imageAltText: _ValueKind.str,
  SlideField.imageAltText2: _ValueKind.str,
  SlideField.videoPath: _ValueKind.str,
  SlideField.audioPath: _ValueKind.str,
  SlideField.quote: _ValueKind.str,
  SlideField.quoteAuthor: _ValueKind.str,
  SlideField.customMarkdown: _ValueKind.str,
  SlideField.codeLanguage: _ValueKind.str,
  SlideField.cssClass: _ValueKind.str,
  SlideField.notes: _ValueKind.str,
  SlideField.titleTextColorOverride: _ValueKind.str,
  SlideField.titleColumnLayout: _ValueKind.titleColumnLayout,
  SlideField.findingId: _ValueKind.str,
  SlideField.checklistScope: _ValueKind.str,
  SlideField.improvementTemplateId: _ValueKind.str,
  SlideField.bullets: _ValueKind.stringList,
  SlideField.bullets2: _ValueKind.stringList,
  SlideField.preservedMarpLines: _ValueKind.stringList,
  SlideField.marpStyle: _ValueKind.marpStyle,
  SlideField.showChecklistProgress: _ValueKind.boolean,
  SlideField.continueNumbering: _ValueKind.boolean,
  SlideField.continuesSplit: _ValueKind.boolean,
  SlideField.videoAutoplay: _ValueKind.boolean,
  SlideField.audioAutoplay: _ValueKind.boolean,
  SlideField.titleImageOverlay: _ValueKind.boolean,
  SlideField.imageTitleAbove: _ValueKind.boolean,
  SlideField.showLogo: _ValueKind.boolean,
  SlideField.showFooter: _ValueKind.boolean,
  SlideField.skipped: _ValueKind.boolean,
  SlideField.isDetail: _ValueKind.boolean,
  SlideField.tableEditable: _ValueKind.boolean,
  SlideField.tableMarkOverdue: _ValueKind.boolean,
  SlideField.videoStartMs: _ValueKind.integer,
  SlideField.videoEndMs: _ValueKind.integer,
  SlideField.imageSize: _ValueKind.integer,
  SlideField.imageZoom: _ValueKind.integer,
  SlideField.titleColumnWidth: _ValueKind.integer,
  SlideField.imageFocalX: _ValueKind.real,
  SlideField.imageFocalY: _ValueKind.real,
  SlideField.imageFocalX2: _ValueKind.real,
  SlideField.imageFocalY2: _ValueKind.real,
  SlideField.advanceDuration: _ValueKind.real,
  SlideField.anchor: _ValueKind.str,
  SlideField.nextAnchor: _ValueKind.str,
  SlideField.ganttScale: _ValueKind.str,
  SlideField.ganttSections: _ValueKind.boolean,
  SlideField.menuLayout: _ValueKind.menuLayout,
  SlideField.tableColumnAlignments: _ValueKind.tableAlignList,
  SlideField.tableNumberColumns: _ValueKind.boolList,
  SlideField.timelineLayout: _ValueKind.timelineLayout,
  SlideField.timelineReveal: _ValueKind.timelineReveal,
  SlideField.timelineAnimationMs: _ValueKind.integer,
  SlideField.bulletMarkerOverride: _ValueKind.bulletMarker,
  SlideField.improvementLayout: _ValueKind.str,
  SlideField.privacy: _ValueKind.privacy,
  SlideField.quality: _ValueKind.quality,
  SlideField.findingRole: _ValueKind.findingRole,
  SlideField.aiAssistedFields: _ValueKind.stringList,
  SlideField.viewLimit: _ValueKind.viewLimit,
};

/// Mirrors the value types `applyOp` casts each [DeckMetaField] to. A test
/// asserts every `DeckMetaField.values` entry is present.
const Map<DeckMetaField, _ValueKind> _deckMetaKinds = {
  DeckMetaField.title: _ValueKind.str,
  DeckMetaField.theme: _ValueKind.str,
  DeckMetaField.author: _ValueKind.str,
  DeckMetaField.organization: _ValueKind.str,
  DeckMetaField.version: _ValueKind.str,
  DeckMetaField.date: _ValueKind.str,
  DeckMetaField.description: _ValueKind.str,
  DeckMetaField.keywords: _ValueKind.str,
  DeckMetaField.language: _ValueKind.str,
  DeckMetaField.improvementFramework: _ValueKind.str,
  DeckMetaField.tlp: _ValueKind.tlp,
  DeckMetaField.privacy: _ValueKind.privacy,
  DeckMetaField.paginate: _ValueKind.boolean,
  DeckMetaField.showRehearsalSummary: _ValueKind.boolean,
  DeckMetaField.playOnly: _ValueKind.boolean,
  DeckMetaField.presentationTargetSeconds: _ValueKind.integer,
  DeckMetaField.standardsUsed: _ValueKind.stringList,
  DeckMetaField.marpStyle: _ValueKind.marpStyle,
};

/// The [SlideField]s the wire codec knows a value kind for. Test-only: a test
/// asserts it covers every `SlideField.values`, so a new field added without a
/// kind is a red test rather than silent data loss over the wire. (No
/// `@visibleForTesting` — that annotation lives in `package:meta`, which is not
/// a direct dependency, and adding one would move the SBOM gate for no gain.)
Set<SlideField> get mappedSlideFields => _slideFieldKinds.keys.toSet();

/// The [DeckMetaField]s the wire codec knows a value kind for. See
/// [mappedSlideFields].
Set<DeckMetaField> get mappedDeckMetaFields => _deckMetaKinds.keys.toSet();

Object? _encodeValue(_ValueKind kind, Object? value) {
  return switch (kind) {
    _ValueKind.str => _need<String>(value),
    _ValueKind.boolean => _need<bool>(value),
    _ValueKind.integer => _need<int>(value),
    _ValueKind.real => _need<double>(value),
    _ValueKind.stringList => _needStrList(value),
    _ValueKind.slideType => _need<SlideType>(value).name,
    _ValueKind.listStyle => _need<ListStyle>(value).name,
    _ValueKind.tlp => _need<TlpLevel>(value).name,
    _ValueKind.privacy => _need<PrivacyDisposition>(value).name,
    _ValueKind.marpStyle => _need<MarpStyle>(value).toJson(),
    _ValueKind.titleColumnLayout => _need<TitleColumnLayout>(value).name,
    _ValueKind.menuLayout => _need<MenuLayout>(value).name,
    _ValueKind.tableAlignList => _needEnumList<TableAlign>(
      value,
    ).map((e) => e.name).toList(),
    _ValueKind.boolList => _needBoolList(value),
    _ValueKind.timelineLayout => _need<TimelineLayout>(value).name,
    _ValueKind.timelineReveal => _need<TimelineReveal>(value).name,
    _ValueKind.bulletMarker => _need<BulletMarker>(value).name,
    _ValueKind.quality => _need<QualityDisposition>(value).name,
    _ValueKind.findingRole => _need<FindingRole>(value).name,
    _ValueKind.viewLimit => _viewLimitToJson(_need<DisplayWindowSpec>(value)),
  };
}

Object? _decodeValue(_ValueKind kind, Object? json, String where) {
  return switch (kind) {
    _ValueKind.str => _asString(json, where),
    _ValueKind.boolean => _asBool(json, where),
    _ValueKind.integer => _asInt(json, where),
    _ValueKind.real => _asDouble(json, where),
    _ValueKind.stringList => _asStrList(json, where),
    _ValueKind.slideType => _enumByName(
      SlideType.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.listStyle => _enumByName(
      ListStyle.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.tlp => _enumByName(
      TlpLevel.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.privacy => _enumByName(
      PrivacyDisposition.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.marpStyle => MarpStyle.fromJson(_asMap(json, where)),
    _ValueKind.titleColumnLayout => _enumByName(
      TitleColumnLayout.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.menuLayout => _enumByName(
      MenuLayout.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.tableAlignList => _asStrList(
      json,
      where,
    ).map((name) => _enumByName(TableAlign.values, name, where)).toList(),
    _ValueKind.boolList => _asBoolList(json, where),
    _ValueKind.timelineLayout => _enumByName(
      TimelineLayout.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.timelineReveal => _enumByName(
      TimelineReveal.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.bulletMarker => _enumByName(
      BulletMarker.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.quality => _enumByName(
      QualityDisposition.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.findingRole => _enumByName(
      FindingRole.values,
      _asString(json, where),
      where,
    ),
    _ValueKind.viewLimit => _viewLimitFromJson(_asMap(json, where)),
  };
}

// ── Whole-message helpers ────────────────────────────────────────────────────

/// Encode [op] to a compact JSON string. Convenience over [deckOpToJson].
String encodeDeckOp(DeckOp op) => jsonEncode(deckOpToJson(op));

/// Decode a [DeckOp] from a JSON string. Fail-closed on malformed input.
DeckOp decodeDeckOp(String source) => deckOpFromJson(_decodeObject(source));

/// Encode [e] to a compact JSON string. Convenience over [lockEventToJson].
String encodeLockEvent(LockEvent e) => jsonEncode(lockEventToJson(e));

/// Decode a [LockEvent] from a JSON string. Fail-closed on malformed input.
LockEvent decodeLockEvent(String source) =>
    lockEventFromJson(_decodeObject(source));

Map<String, Object?> _decodeObject(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    throw FormatException('not JSON: ${e.message}');
  }
  if (decoded is Map<String, Object?>) return decoded;
  throw FormatException('expected a JSON object, got ${decoded.runtimeType}');
}

// ── Typed field readers (fail-closed) ────────────────────────────────────────

String _str(Map<String, Object?> j, String key) => _asString(j[key], key);
int _int(Map<String, Object?> j, String key) => _asInt(j[key], key);
bool _bool(Map<String, Object?> j, String key) => _asBool(j[key], key);
double _double(Map<String, Object?> j, String key) => _asDouble(j[key], key);
List<String> _strList(Map<String, Object?> j, String key) =>
    _asStrList(j[key], key);

Map<String, Object?> _map(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  throw FormatException('field "$key" is not an object (${v.runtimeType})');
}

Map<String, Object?> _asMap(Object? value, String where) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  throw FormatException(
    'field "$where" is not an object (${value.runtimeType})',
  );
}

List<List<String>> _rows(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is List) return v.map((row) => _asStrList(row, key)).toList();
  throw FormatException(
    'field "$key" is not a list of rows (${v.runtimeType})',
  );
}

String _asString(Object? v, String where) {
  if (v is String) return v;
  throw FormatException(
    'field "$where" expected a String, got ${v.runtimeType}',
  );
}

int _asInt(Object? v, String where) {
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  throw FormatException('field "$where" expected an int, got ${v.runtimeType}');
}

int? _intOrNull(Object? v, String where) => v == null ? null : _asInt(v, where);

bool _asBool(Object? v, String where) {
  if (v is bool) return v;
  throw FormatException('field "$where" expected a bool, got ${v.runtimeType}');
}

double _asDouble(Object? v, String where) {
  if (v is num) return v.toDouble();
  throw FormatException(
    'field "$where" expected a number, got ${v.runtimeType}',
  );
}

List<String> _asStrList(Object? v, String where) {
  if (v is List) return v.map((e) => _asString(e, where)).toList();
  throw FormatException('field "$where" expected a list, got ${v.runtimeType}');
}

List<bool> _asBoolList(Object? v, String where) {
  if (v is List) return v.map((e) => _asBool(e, where)).toList();
  throw FormatException('field "$where" expected a list, got ${v.runtimeType}');
}

List<E> _enumList<E extends Enum>(
  Map<String, Object?> j,
  String key,
  List<E> values,
) {
  final v = j[key];
  if (v is List) {
    return v.map((e) => _enumByName(values, _asString(e, key), key)).toList();
  }
  throw FormatException('field "$key" is not a list (${v.runtimeType})');
}

List<bool> _boolList(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is List) return v.map((e) => _asBool(e, key)).toList();
  throw FormatException('field "$key" is not a list (${v.runtimeType})');
}

/// Assert an in-memory op value has the runtime type the field expects, so a
/// malformed op is caught at encode time rather than producing lossy JSON.
T _need<T>(Object? value) {
  if (value is T) return value;
  throw FormatException('op value expected a $T, got ${value.runtimeType}');
}

List<String> _needStrList(Object? value) {
  if (value is List) return value.map((e) => _need<String>(e)).toList();
  throw FormatException(
    'op value expected a List<String>, got ${value.runtimeType}',
  );
}

List<E> _needEnumList<E extends Enum>(Object? value) {
  if (value is List) return value.map((e) => _need<E>(e)).toList();
  throw FormatException('op value expected a List, got ${value.runtimeType}');
}

List<bool> _needBoolList(Object? value) {
  if (value is List) return value.map((e) => _need<bool>(e)).toList();
  throw FormatException(
    'op value expected a List<bool>, got ${value.runtimeType}',
  );
}

E _enumByName<E extends Enum>(List<E> values, String name, String where) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('field "$where" has unknown value "$name"');
}

E? _enumOrNull<E extends Enum>(List<E> values, Object? raw, String where) {
  if (raw == null) return null;
  return _enumByName(values, _asString(raw, where), where);
}
