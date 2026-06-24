import 'package:uuid/uuid.dart';
import 'cockpit.dart';
import 'deck.dart';
import 'question.dart';
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

extension SlideTypeExtension on SlideType {
  String get label {
    switch (this) {
      case SlideType.title:
        return 'Titelpagina';
      case SlideType.section:
        return 'Tussentitel';
      case SlideType.bullets:
        return 'Alleen Bullets';
      case SlideType.twoBullets:
        return 'Twee Bulletkolommen';
      case SlideType.bulletsImage:
        return 'Bullets + Afbeelding';
      case SlideType.twoImages:
        return 'Twee Afbeeldingen';
      case SlideType.image:
        return 'Grote Afbeelding';
      case SlideType.video:
        return 'Video';
      case SlideType.quote:
        return 'Quote';
      case SlideType.table:
        return 'Tabel';
      case SlideType.freeMarkdown:
        return 'Vrije Markdown';
      case SlideType.code:
        return 'Broncode';
      case SlideType.chart:
        return 'Grafiek';
      case SlideType.cockpit:
        return 'Cockpit';
      case SlideType.question:
        return 'Vraag';
      case SlideType.timeline:
        return 'Tijdlijn';
    }
  }

  String get marpClass {
    switch (this) {
      case SlideType.title:
        return 'title';
      case SlideType.section:
        return 'section';
      case SlideType.bullets:
        return '';
      case SlideType.twoBullets:
        return 'two-bullets';
      case SlideType.bulletsImage:
        return 'split';
      case SlideType.twoImages:
        return '';
      case SlideType.image:
        return '';
      case SlideType.video:
        return 'video';
      case SlideType.quote:
        return 'quote';
      case SlideType.table:
        return 'table';
      case SlideType.freeMarkdown:
        return '';
      case SlideType.code:
        return 'code';
      case SlideType.chart:
        return 'chart';
      case SlideType.cockpit:
        return 'cockpit';
      case SlideType.question:
        return 'question';
      case SlideType.timeline:
        return 'timeline';
    }
  }
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
  final bool showLogo; // show the profile logo on this slide (default true)
  final bool showFooter; // show the profile footer on this slide (default true)
  final bool skipped; // skip this slide when presenting and exporting
  /// Per-slide Traffic Light Protocol classification. The slide is withheld
  /// when the presentation is shared at a lower (less restrictive) level than
  /// this. [TlpLevel.none] = no per-slide restriction (always shown).
  final TlpLevel tlp;
  final List<List<String>> tableRows; // first row is the header

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
    this.showLogo = true,
    this.showFooter = true,
    this.skipped = false,
    this.tlp = TlpLevel.none,
    this.tableRows = const [],
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
      showLogo: src.showLogo,
      showFooter: src.showFooter,
      skipped: src.skipped,
      tlp: src.tlp,
      tableRows: src.tableRows.map((r) => List<String>.from(r)).toList(),
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
    bool? showLogo,
    bool? showFooter,
    bool? skipped,
    TlpLevel? tlp,
    List<List<String>>? tableRows,
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
      showLogo: showLogo ?? this.showLogo,
      showFooter: showFooter ?? this.showFooter,
      skipped: skipped ?? this.skipped,
      tlp: tlp ?? this.tlp,
      tableRows: tableRows ?? this.tableRows,
      timelineLayout: timelineLayout ?? this.timelineLayout,
      timelineReveal: timelineReveal ?? this.timelineReveal,
      timelineAnimationMs: timelineAnimationMs ?? this.timelineAnimationMs,
    );
  }
}
