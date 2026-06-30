import 'package:uuid/uuid.dart';
import 'cockpit.dart';
import 'deck.dart';
import 'question.dart';
import 'settings.dart';
import 'timeline.dart';

const _uuid = Uuid();

enum SlideType {
  title,
  section,
  bullets,
  twoBullets,
  bulletsImage,
  twoImages,
  image,
  video,
  quote,
  table,
  freeMarkdown,
  code,
  chart,
  cockpit,
  question,
  timeline,
}

enum ListStyle { bullets, numbered, checklist, richText }

int bulletLevel(String value) {
  var level = 0;
  while (level < value.length && value[level] == '\t') {
    level++;
  }
  return level;
}

String bulletText(String value) => value.substring(bulletLevel(value));

bool checklistItemChecked(String value) =>
    RegExp(r'^\[[xX]\]\s*').hasMatch(bulletText(value));

String checklistItemText(String value) =>
    bulletText(value).replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '');

String checklistBullet({
  required int level,
  required String text,
  required bool checked,
}) => '${'\t' * level}[${checked ? 'x' : ' '}] $text';

/// Pure-data metadata for a [SlideType], co-located with the enum so adding a
/// type is one map entry instead of edits to several scattered switches. UI
/// behaviour (editor, preview, picker icon) lives in the widget layer's
/// registry — this layer stays Flutter-free.
class SlideTypeMeta {
  /// Dutch source label, localised via `l10n.d(...)` at the call site.
  final String label;

  /// The Marp `_class` token written to the `.md` (empty = no class token).
  final String marpClass;

  const SlideTypeMeta({required this.label, required this.marpClass});
}

/// The single source of truth for per-type pure data. A guard test
/// (`slide_type_meta_test.dart`) fails if any [SlideType] is missing here.
const Map<SlideType, SlideTypeMeta> slideTypeMeta = {
  SlideType.title: SlideTypeMeta(label: 'Titelpagina', marpClass: 'title'),
  SlideType.section: SlideTypeMeta(label: 'Tussentitel', marpClass: 'section'),
  SlideType.bullets: SlideTypeMeta(label: 'Alleen Bullets', marpClass: ''),
  SlideType.twoBullets: SlideTypeMeta(
    label: 'Twee Bulletkolommen',
    marpClass: 'two-bullets',
  ),
  SlideType.bulletsImage: SlideTypeMeta(
    label: 'Bullets + Afbeelding',
    marpClass: 'split',
  ),
  SlideType.twoImages: SlideTypeMeta(label: 'Twee Afbeeldingen', marpClass: ''),
  SlideType.image: SlideTypeMeta(label: 'Grote Afbeelding', marpClass: ''),
  SlideType.video: SlideTypeMeta(label: 'Video', marpClass: 'video'),
  SlideType.quote: SlideTypeMeta(label: 'Quote', marpClass: 'quote'),
  SlideType.table: SlideTypeMeta(label: 'Tabel', marpClass: 'table'),
  SlideType.freeMarkdown: SlideTypeMeta(label: 'Vrije Markdown', marpClass: ''),
  SlideType.code: SlideTypeMeta(label: 'Broncode', marpClass: 'code'),
  SlideType.chart: SlideTypeMeta(label: 'Grafiek', marpClass: 'chart'),
  SlideType.cockpit: SlideTypeMeta(label: 'Cockpit', marpClass: 'cockpit'),
  SlideType.question: SlideTypeMeta(label: 'Vraag', marpClass: 'question'),
  SlideType.timeline: SlideTypeMeta(label: 'Tijdlijn', marpClass: 'timeline'),
};

extension SlideTypeExtension on SlideType {
  String get label => slideTypeMeta[this]!.label;
  String get marpClass => slideTypeMeta[this]!.marpClass;
}

class Slide {
  final String id;
  final SlideType type;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final List<String> bullets2;
  final ListStyle listStyle;
  final bool showChecklistProgress;

  /// Optional headings above the two bullet columns (twoBullets only). Empty =
  /// no heading for that column.
  final String columnTitle1;
  final String columnTitle2;
  final String imagePath;
  final String imagePath2;
  final String imageCaption;
  final String imageCaption2;
  final String videoPath;
  final bool videoAutoplay;

  /// Trim window for the video, in milliseconds. Lets one source play in parts
  /// across consecutive slides (the "cut" feature). [videoStartMs] = 0 plays
  /// from the start; [videoEndMs] = 0 plays to the natural end. Applies to
  /// local files, remote files and YouTube/Vimeo embeds alike.
  final int videoStartMs;
  final int videoEndMs;
  final String audioPath;
  final bool audioAutoplay;
  final String quote;
  final String quoteAuthor;
  final String customMarkdown;
  final String
  codeLanguage; // highlight.js language id for code slides ('' = plain)
  final String cssClass;
  final String notes;
  final double advanceDuration; // 0 = no auto-advance
  final int imageSize; // 0 = auto; image: bg %, bulletsImage: right panel %
  final bool titleImageOverlay; // darken title background image for readability
  /// Title slides only: overrides the theme's title text colour for this one
  /// slide (hex, e.g. `#FFFFFF`). Empty = use the theme colour. Lets the
  /// contrast auto-fix flip text light/dark on a single slide without touching
  /// the deck-wide theme.
  final String titleTextColorOverride;

  /// Bullet/twoBullets/bulletsImage slides only: overrides the theme's
  /// [ThemeProfile.bulletMarker] for this one slide. `null` = inherit the
  /// theme default. Lets a single slide turn cat-paws on or off without
  /// touching the deck-wide theme (mirrors [titleTextColorOverride]).
  final BulletMarker? bulletMarkerOverride;
  final bool showLogo; // show the profile logo on this slide (default true)
  final bool showFooter; // show the profile footer on this slide (default true)
  final bool skipped; // skip this slide when presenting and exporting
  /// Per-slide Traffic Light Protocol classification. The slide is withheld
  /// when the presentation is shared at a lower (less restrictive) level than
  /// this. [TlpLevel.none] = no per-slide restriction (always shown).
  final TlpLevel tlp;
  final List<List<String>> tableRows; // first row is the header

  /// Table slides only: whether the table may be edited live during a
  /// presentation. Off by default, so tables are read-only unless the author
  /// explicitly opts in from the builder. Older presentations lack the token
  /// and therefore keep the safe default (not editable).
  final bool tableEditable;

  /// Timeline slides only: how the events are arranged and animated. The events
  /// themselves are stored in [bullets] as `marker :: title :: description`
  /// strings; the layout/reveal options round-trip as `_class` tokens and the
  /// draw-in duration as an `ocideck_timeline_duration` comment.
  final TimelineLayout timelineLayout;
  final TimelineReveal timelineReveal;
  final int timelineAnimationMs;

  const Slide({
    required this.id,
    required this.type,
    this.title = '',
    this.subtitle = '',
    this.bullets = const [],
    this.bullets2 = const [],
    this.listStyle = ListStyle.bullets,
    this.showChecklistProgress = false,
    this.columnTitle1 = '',
    this.columnTitle2 = '',
    this.imagePath = '',
    this.imagePath2 = '',
    this.imageCaption = '',
    this.imageCaption2 = '',
    this.videoPath = '',
    this.videoAutoplay = false,
    this.videoStartMs = 0,
    this.videoEndMs = 0,
    this.audioPath = '',
    this.audioAutoplay = false,
    this.quote = '',
    this.quoteAuthor = '',
    this.customMarkdown = '',
    this.codeLanguage = '',
    this.cssClass = '',
    this.notes = '',
    this.advanceDuration = 0,
    this.imageSize = 0,
    this.titleImageOverlay = true,
    this.titleTextColorOverride = '',
    this.bulletMarkerOverride,
    this.showLogo = true,
    this.showFooter = true,
    this.skipped = false,
    this.tlp = TlpLevel.none,
    this.tableRows = const [],
    this.tableEditable = false,
    this.timelineLayout = TimelineLayout.auto,
    this.timelineReveal = TimelineReveal.onEnter,
    this.timelineAnimationMs = timelineDefaultAnimationDurationMs,
  });

  factory Slide.create(SlideType type) {
    return Slide(
      id: _uuid.v4(),
      type: type,
      bullets: type == SlideType.timeline
          ? timelineEventsToBullets(defaultTimelineEvents())
          : (type == SlideType.bullets ||
                type == SlideType.twoBullets ||
                type == SlideType.bulletsImage)
          ? const ['']
          : const [],
      bullets2: type == SlideType.twoBullets ? const [''] : const [],
      tableRows: type == SlideType.table
          ? const [
              // Lege koppen: de editor toont 'Kolom 1' etc. als hint, zodat de
              // gebruiker niets hoeft te verwijderen voordat hij begint.
              ['', ''],
              ['', ''],
            ]
          : const [],
      customMarkdown: type == SlideType.cockpit
          ? CockpitSpec.pentestPreset().toBlock()
          : type == SlideType.question
          ? QuestionSpec.defaultMultipleChoice().toBlock()
          : '',
    );
  }

  factory Slide.duplicate(Slide src) {
    return Slide(
      id: _uuid.v4(),
      type: src.type,
      title: src.title,
      subtitle: src.subtitle,
      bullets: List<String>.from(src.bullets),
      bullets2: List<String>.from(src.bullets2),
      listStyle: src.listStyle,
      showChecklistProgress: src.showChecklistProgress,
      columnTitle1: src.columnTitle1,
      columnTitle2: src.columnTitle2,
      imagePath: src.imagePath,
      imagePath2: src.imagePath2,
      imageCaption: src.imageCaption,
      imageCaption2: src.imageCaption2,
      videoPath: src.videoPath,
      videoAutoplay: src.videoAutoplay,
      videoStartMs: src.videoStartMs,
      videoEndMs: src.videoEndMs,
      audioPath: src.audioPath,
      audioAutoplay: src.audioAutoplay,
      quote: src.quote,
      quoteAuthor: src.quoteAuthor,
      customMarkdown: src.customMarkdown,
      codeLanguage: src.codeLanguage,
      cssClass: src.cssClass,
      notes: src.notes,
      advanceDuration: src.advanceDuration,
      imageSize: src.imageSize,
      titleImageOverlay: src.titleImageOverlay,
      titleTextColorOverride: src.titleTextColorOverride,
      bulletMarkerOverride: src.bulletMarkerOverride,
      showLogo: src.showLogo,
      showFooter: src.showFooter,
      skipped: src.skipped,
      tlp: src.tlp,
      tableRows: src.tableRows.map((r) => List<String>.from(r)).toList(),
      tableEditable: src.tableEditable,
      timelineLayout: src.timelineLayout,
      timelineReveal: src.timelineReveal,
      timelineAnimationMs: src.timelineAnimationMs,
    );
  }

  Slide copyWith({
    SlideType? type,
    String? title,
    String? subtitle,
    List<String>? bullets,
    List<String>? bullets2,
    ListStyle? listStyle,
    bool? showChecklistProgress,
    String? columnTitle1,
    String? columnTitle2,
    String? imagePath,
    String? imagePath2,
    String? imageCaption,
    String? imageCaption2,
    String? videoPath,
    bool? videoAutoplay,
    int? videoStartMs,
    int? videoEndMs,
    String? audioPath,
    bool? audioAutoplay,
    String? quote,
    String? quoteAuthor,
    String? customMarkdown,
    String? codeLanguage,
    String? cssClass,
    String? notes,
    double? advanceDuration,
    int? imageSize,
    bool? titleImageOverlay,
    String? titleTextColorOverride,
    BulletMarker? bulletMarkerOverride,
    bool clearBulletMarkerOverride = false,
    bool? showLogo,
    bool? showFooter,
    bool? skipped,
    TlpLevel? tlp,
    List<List<String>>? tableRows,
    bool? tableEditable,
    TimelineLayout? timelineLayout,
    TimelineReveal? timelineReveal,
    int? timelineAnimationMs,
  }) {
    return Slide(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      bullets: bullets ?? this.bullets,
      bullets2: bullets2 ?? this.bullets2,
      listStyle: listStyle ?? this.listStyle,
      showChecklistProgress:
          showChecklistProgress ?? this.showChecklistProgress,
      columnTitle1: columnTitle1 ?? this.columnTitle1,
      columnTitle2: columnTitle2 ?? this.columnTitle2,
      imagePath: imagePath ?? this.imagePath,
      imagePath2: imagePath2 ?? this.imagePath2,
      imageCaption: imageCaption ?? this.imageCaption,
      imageCaption2: imageCaption2 ?? this.imageCaption2,
      videoPath: videoPath ?? this.videoPath,
      videoAutoplay: videoAutoplay ?? this.videoAutoplay,
      videoStartMs: videoStartMs ?? this.videoStartMs,
      videoEndMs: videoEndMs ?? this.videoEndMs,
      audioPath: audioPath ?? this.audioPath,
      audioAutoplay: audioAutoplay ?? this.audioAutoplay,
      quote: quote ?? this.quote,
      quoteAuthor: quoteAuthor ?? this.quoteAuthor,
      customMarkdown: customMarkdown ?? this.customMarkdown,
      codeLanguage: codeLanguage ?? this.codeLanguage,
      cssClass: cssClass ?? this.cssClass,
      notes: notes ?? this.notes,
      advanceDuration: advanceDuration ?? this.advanceDuration,
      imageSize: imageSize ?? this.imageSize,
      titleImageOverlay: titleImageOverlay ?? this.titleImageOverlay,
      titleTextColorOverride:
          titleTextColorOverride ?? this.titleTextColorOverride,
      bulletMarkerOverride: clearBulletMarkerOverride
          ? null
          : (bulletMarkerOverride ?? this.bulletMarkerOverride),
      showLogo: showLogo ?? this.showLogo,
      showFooter: showFooter ?? this.showFooter,
      skipped: skipped ?? this.skipped,
      tlp: tlp ?? this.tlp,
      tableRows: tableRows ?? this.tableRows,
      tableEditable: tableEditable ?? this.tableEditable,
      timelineLayout: timelineLayout ?? this.timelineLayout,
      timelineReveal: timelineReveal ?? this.timelineReveal,
      timelineAnimationMs: timelineAnimationMs ?? this.timelineAnimationMs,
    );
  }
}
