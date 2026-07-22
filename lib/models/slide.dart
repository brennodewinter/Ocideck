import 'package:uuid/uuid.dart';
import 'asset_overview_spec.dart';
import 'checklist_spec.dart';
import 'cockpit.dart';
import 'deck.dart';
import 'discoveries_spec.dart';
import 'privacy_disposition.dart';
import 'quality_disposition.dart';
import 'finding_spec.dart';
import 'findings_summary_spec.dart';
import 'question.dart';
import 'scope_matrix_spec.dart';
import 'scorecard_spec.dart';
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
  scorecard,
  assets,
  discoveries,
  // Informatieveiligheid-module (pentestrapportage, PENTEST_MIAUW §4). Elk type
  // heeft een eigen gestructureerde editor, preview en serialiser; inhoud én
  // type round-trippen verliesvrij onder hun eigen `_class`-token. `signOff`
  // draagt per ontwerp geen eigen dia-inhoud (§1.6/§8).
  finding,
  findingsSummary,
  checklist,
  scopeMatrix,
  signOff,
}

/// Broad grouping a [SlideType] belongs to, used by the add-slide picker to
/// offer category tabs. The pentest-reporting layouts carry
/// [SlideCategory.informationSecurity]; the picker derives its tab bar from the
/// categories actually present, so a tab appears only once the module reveals
/// its types.
enum SlideCategory { general, informationSecurity }

/// Hoeveel kolommen *doorlopende* bullettekst een [SlideType] toont — de vorm
/// die zich over pagina's laat verdelen.
///
/// Nadrukkelijk niet "draagt iets in [Slide.bullets]": `timeline` bewaart zijn
/// gebeurtenissen dáár ook, maar dat is gecodeerde gegevens, geen lopende
/// lijst, en die knip je niet in tweeën. Vandaar [none] voor zulke types.
enum BulletColumns { none, one, two }

/// The part a slide plays inside a finding *group* (PENTEST_MIAUW §3.1). A real
/// finding spans a header/summary card plus detail slides (description,
/// reproduction, impact, recommendation) and evidence screenshots; every slide
/// in the group shares one [Slide.findingId]. The `finding` slide type is always
/// the [header]; [detail] and [evidence] ride on ordinary slide types (bullets,
/// image) that opt into the group by carrying a finding id + role. Round-trips
/// as `<!-- ocideck_finding_role: … -->` and is only meaningful when
/// [Slide.findingId] is set.
enum FindingRole { header, detail, evidence }

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

/// Sentinel that marks a bullet-list item as a **group heading** ("tussenkop"):
/// a labelled break that visually separates groups of bullets on one slide, so a
/// single bullets slide can be split into sections without splitting the slide.
///
/// It is a private-use codepoint stored inline at the start of the item's text
/// — mirroring the checklist `[x]` convention — so a heading is just another
/// entry in [Slide.bullets]. Ordering, drag-reorder, delete and the file
/// round-trip therefore all ride the existing list machinery: no parallel list
/// of positions to keep in sync. An empty label renders as a plain divider rule
/// (a break with no words). Group headings are always at level 0.
///
/// The codepoint is deliberately in the Unicode Private Use Area so it can never
/// collide with text a user actually types (the same reasoning as the caption
/// pipe sentinels in `markdown_service_helpers.dart`).
const String kGroupHeadingMarker = '\u{E010}';

/// Whether [value] is a group-heading item (see [kGroupHeadingMarker]).
bool isGroupHeading(String value) =>
    bulletText(value).startsWith(kGroupHeadingMarker);

/// The label of a group-heading item, or the plain bullet text when [value] is
/// an ordinary bullet. Empty for a wordless divider.
String groupHeadingText(String value) {
  final body = bulletText(value);
  return body.startsWith(kGroupHeadingMarker)
      ? body.substring(kGroupHeadingMarker.length)
      : body;
}

/// Builds a group-heading item carrying [text] (empty = a wordless divider).
String groupHeadingBullet(String text) => '$kGroupHeadingMarker$text';

/// Pure-data metadata for a [SlideType], co-located with the enum so adding a
/// type is one map entry instead of edits to several scattered switches. UI
/// behaviour (editor, preview, picker icon) lives in the widget layer's
/// registry — this layer stays Flutter-free.
class SlideTypeMeta {
  /// Dutch source label, localised via `l10n.d(...)` at the call site.
  final String label;

  /// The Marp `_class` token written to the `.md` (empty = no class token).
  final String marpClass;

  /// Renders its body beside an inline image (the bulletsImage split layout).
  /// Replaces the `type == SlideType.bulletsImage` checks scattered across the
  /// preview, presenter and notes code.
  final bool splitWithImage;

  /// A heading/divider slide (title or section) with no flowing body content.
  final bool isHeading;

  /// Which picker category this type belongs to. Drives the add-slide dialog's
  /// category tabs; defaults to [SlideCategory.general] so existing types need
  /// no per-entry change.
  final SlideCategory category;

  /// Hoeveel kolommen doorlopende bullettekst dit type toont; bepaalt of en hoe
  /// "in tweeën splitsen" werkt. Zie [BulletColumns].
  ///
  /// Dezelfde regel stond driemaal uitgeschreven — in `canSplitSlide`, in
  /// `DeckNotifier._splitSlide` en nog eens in de slidestrook, die laatste met
  /// een `_ => false` die een nieuw type stilzwijgend onsplitsbaar maakte. Drie
  /// kopieën die uit de pas konden lopen; nu één veld.
  final BulletColumns bulletColumns;

  /// Stores its content as a Markdown table in [Slide.tableRows], and therefore
  /// round-trips through the shared table writer/reader.
  ///
  /// Dit was tot nu toe een handgeschreven verzameling in de parser
  /// (`_tableBackedTypes`) naast een handgeschreven cases-groep in de
  /// serialisatie. Twee lijsten van hetzelfde feit, in twee bestanden, geen van
  /// beide door de compiler bewaakt — en de parserkant vergeten was de klassieke
  /// stille val: het deck parseert, de dia verschijnt, en de rijen zijn na
  /// herladen leeg. Als vlag hier staat het feit één keer, op de plek waar je
  /// een nieuw type toch al aanmeldt, en bewaakt de registrytest hem.
  final bool backedByTable;

  const SlideTypeMeta({
    required this.label,
    required this.marpClass,
    this.splitWithImage = false,
    this.isHeading = false,
    this.category = SlideCategory.general,
    this.bulletColumns = BulletColumns.none,
    this.backedByTable = false,
  });
}

/// The single source of truth for per-type pure data. A guard test
/// (`slide_type_meta_test.dart`) fails if any [SlideType] is missing here.
const Map<SlideType, SlideTypeMeta> slideTypeMeta = {
  SlideType.title: SlideTypeMeta(
    label: 'Titelpagina',
    marpClass: 'title',
    isHeading: true,
  ),
  SlideType.section: SlideTypeMeta(
    label: 'Tussentitel',
    marpClass: 'section',
    isHeading: true,
  ),
  SlideType.bullets: SlideTypeMeta(
    label: 'Alleen Bullets',
    marpClass: '',
    bulletColumns: BulletColumns.one,
  ),
  SlideType.twoBullets: SlideTypeMeta(
    label: 'Twee Bulletkolommen',
    marpClass: 'two-bullets',
    bulletColumns: BulletColumns.two,
  ),
  SlideType.bulletsImage: SlideTypeMeta(
    label: 'Bullets + Afbeelding',
    marpClass: 'split',
    splitWithImage: true,
    bulletColumns: BulletColumns.one,
  ),
  SlideType.twoImages: SlideTypeMeta(label: 'Twee Afbeeldingen', marpClass: ''),
  SlideType.image: SlideTypeMeta(label: 'Grote Afbeelding', marpClass: ''),
  SlideType.video: SlideTypeMeta(label: 'Video', marpClass: 'video'),
  SlideType.quote: SlideTypeMeta(label: 'Quote', marpClass: 'quote'),
  SlideType.table: SlideTypeMeta(
    label: 'Tabel',
    marpClass: 'table',
    backedByTable: true,
  ),
  SlideType.freeMarkdown: SlideTypeMeta(label: 'Vrije Markdown', marpClass: ''),
  SlideType.code: SlideTypeMeta(label: 'Broncode', marpClass: 'code'),
  SlideType.chart: SlideTypeMeta(label: 'Grafiek', marpClass: 'chart'),
  SlideType.cockpit: SlideTypeMeta(label: 'Cockpit', marpClass: 'cockpit'),
  SlideType.question: SlideTypeMeta(label: 'Vraag', marpClass: 'question'),
  SlideType.timeline: SlideTypeMeta(label: 'Tijdlijn', marpClass: 'timeline'),
  SlideType.scorecard: SlideTypeMeta(
    label: 'Scorecard',
    marpClass: 'scorecard',
    backedByTable: true,
  ),
  // Informatieveiligheid-module — categorie [SlideCategory.informationSecurity],
  // waardoor de kiezer automatisch een tabblad toont (P0-PICK). marpClass-tokens
  // volgen PENTEST_MIAUW §4.
  SlideType.assets: SlideTypeMeta(
    label: 'Aanvalsoppervlak',
    marpClass: 'assets',
    category: SlideCategory.informationSecurity,
    backedByTable: true,
  ),
  SlideType.discoveries: SlideTypeMeta(
    label: 'Ontdekkingen',
    marpClass: 'discoveries',
    category: SlideCategory.informationSecurity,
    backedByTable: true,
  ),
  SlideType.finding: SlideTypeMeta(
    label: 'Bevinding',
    marpClass: 'finding',
    category: SlideCategory.informationSecurity,
  ),
  SlideType.findingsSummary: SlideTypeMeta(
    label: 'Bevindingenoverzicht',
    marpClass: 'findings-summary',
    category: SlideCategory.informationSecurity,
    backedByTable: true,
  ),
  SlideType.checklist: SlideTypeMeta(
    label: 'Uitvoering testen conform standaard',
    marpClass: 'checklist',
    category: SlideCategory.informationSecurity,
    backedByTable: true,
  ),
  SlideType.scopeMatrix: SlideTypeMeta(
    label: 'Scope-matrix',
    marpClass: 'scope-matrix',
    category: SlideCategory.informationSecurity,
    backedByTable: true,
  ),
  SlideType.signOff: SlideTypeMeta(
    label: 'Ondertekening',
    marpClass: 'sign-off',
    category: SlideCategory.informationSecurity,
  ),
};

/// De registry andersom: `_class`-token → slidetype.
///
/// De serialisatie schrijft `type.marpClass`; het inlezen moet daar niet zijn
/// eigen lijst van stringliteralen naast leggen. Een nieuw type dat wél
/// geschreven maar niet gelezen wordt, komt terug als iets anders — en dat is
/// stil dataverlies, want de dia opent dan in de verkeerde editor.
///
/// Types zonder token (bullets, image, twoImages, freeMarkdown) staan er niet
/// in: die worden aan hun inhoud herkend.
final Map<String, SlideType> slideTypeByMarpClass = {
  for (final entry in slideTypeMeta.entries)
    if (entry.value.marpClass.isNotEmpty) entry.value.marpClass: entry.key,
};

extension SlideTypeExtension on SlideType {
  String get label => slideTypeMeta[this]!.label;
  String get marpClass => slideTypeMeta[this]!.marpClass;

  /// True for the bulletsImage split layout (body beside an inline image).
  bool get splitWithImage => slideTypeMeta[this]!.splitWithImage;

  /// True for a title/section heading slide.
  bool get isHeading => slideTypeMeta[this]!.isHeading;

  /// The picker category this type belongs to.
  SlideCategory get category => slideTypeMeta[this]!.category;

  /// Hoeveel kolommen doorlopende bullettekst dit type toont.
  BulletColumns get bulletColumns => slideTypeMeta[this]!.bulletColumns;

  /// True when the type's content lives in [Slide.tableRows] and round-trips
  /// through the shared table writer/reader. See [SlideTypeMeta.backedByTable].
  bool get backedByTable => slideTypeMeta[this]!.backedByTable;

  /// Informatieveiligheid scaffold types (P1-S) whose body is still stored as
  /// free Markdown in [Slide.customMarkdown] and round-trips like a free-Markdown
  /// slide until each type's structured serialiser lands. `checklist` (P1-CHK),
  /// `scopeMatrix` (P1-SCOPE) and `findingsSummary` (P1-SUM) graduated to real
  /// Markdown tables in [Slide.tableRows]; `signOff` (P1-SIGN) stores only an
  /// optional heading (its attestation is deck-level), so all four are excluded
  /// here. Only `finding` (P1-FIND) still uses the scaffold body.
  ///
  /// De drie afgestudeerde types worden aan [backedByTable] herkend in plaats
  /// van bij naam: een nieuw tabelgedragen module-type is dan meteen goed
  /// ingedeeld, in plaats van stil als scaffold-Markdown te worden gelezen.
  bool get usesScaffoldMarkdownBody =>
      category == SlideCategory.informationSecurity &&
      !backedByTable &&
      this != SlideType.signOff;
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

  /// For a numbered list: continue counting from where the previous slide's
  /// numbered list left off (e.g. a list split across two slides runs 1–6 then
  /// 7–9) instead of restarting at 1. Only meaningful on a numbered
  /// bullets/bulletsImage slide whose previous slide is also numbered.
  final bool continueNumbering;

  /// Marks this slide as a continuation half produced by splitting a bullet
  /// slide. All members of a split run (the original plus its continuations)
  /// render their text at one shared font scale — the size of the fullest half
  /// — so the reader never sees the same list change size across pages. Set on
  /// every half after the first; round-trips as an `ocideck_continue_split`
  /// comment. Independent of [continueNumbering] (numbering vs sizing).
  final bool continuesSplit;

  /// Optional headings above the two bullet columns (twoBullets only). Empty =
  /// no heading for that column.
  final String columnTitle1;
  final String columnTitle2;
  final String imagePath;
  final String imagePath2;
  final String imageCaption;
  final String imageCaption2;

  /// Per-usage WCAG alt-text for the slide's image(s) (AI_ASSIST §6.1). Empty =
  /// fall back to the caption in [imageSemanticsLabel]; an explicitly empty alt
  /// on a *decorative* image is valid (`alt=""`). Round-trips as
  /// `<!-- ocideck_image_alt: … -->` / `…_alt2`.
  final String imageAltText;
  final String imageAltText2;

  /// Normalized focal point (0..1, 0.5 = centre) that decides which part of a
  /// cropped image stays in view instead of always centring. It applies when
  /// the picture overflows its slot — cover mode, zoom-in, or a fixed panel
  /// (bulletsImage / twoImages). [imageFocalX]/[imageFocalY] belong to
  /// [imagePath]; [imageFocalX2]/[imageFocalY2] to [imagePath2] (twoImages).
  /// The centre default keeps older decks rendering exactly as before.
  final double imageFocalX;
  final double imageFocalY;
  final double imageFocalX2;
  final double imageFocalY2;
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

  /// Of de media op deze slide door de privacyprojectie is weggehaald.
  ///
  /// **Alleen voor de projectie — dit veld wordt niet geserialiseerd en staat
  /// dus in geen enkel opgeslagen deck.** Zie `markdown_service_serialize.dart`:
  /// die schrijft veld voor veld, en dit veld staat er bewust niet bij.
  ///
  /// Waarom het er toch is. De redactie van media is het wíssen van het pad
  /// (`privacy_projection.dart`), en daarmee ging precies één ding verloren:
  /// het verschíl tussen "hier is een foto weggehaald" en "hier heeft de auteur
  /// nog geen foto gekozen". De renderer zag alleen een leeg pad en toonde in
  /// beide gevallen hetzelfde grijze vak met het woord "Afbeelding". Op een
  /// geredigeerde slide leest dat als een vergeten plaatje, niet als een
  /// bewuste ingreep — terwijl de tekst ernaast wél zwarte blokken laat zien.
  ///
  /// Dat verschil kán niet uit het lege pad worden afgeleid, dus reist het mee.
  final bool mediaRedacted;

  /// Of er tekst op deze slide is weggelakt door de projectie.
  ///
  /// Net als [mediaRedacted] reist dit alleen mee in een geprojecteerd deck; het
  /// staat nooit in het bestand. Het bestaat om de terugschrijfgrens te bewaken:
  /// een oppervlak dat de gegevens niet kán zien, mag ze ook niet terugschrijven
  /// (zie `privacy_projection.dart`). De presenter schrijft een aangevinkt
  /// checklistpunt als *hele slide* terug naar het deck, dus zonder deze vlag
  /// zou één vinkje de bron met zwarte blokken overschrijven.
  ///
  /// [tableEditable] doet hetzelfde voor tabellen, maar dat is een veld van de
  /// auteur dat de projectie uitzet; voor de checklist bestaat zo'n veld niet.
  final bool contentRedacted;
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

  /// Marks this slide as **depth**: the detail behind the story rather than the
  /// story. It is left out when the deck is exported as the condensed version,
  /// and kept in the full one.
  ///
  /// A third, independent axis next to [skipped] and [tlp], and deliberately so:
  /// TLP asks *who may see this*, redaction asks *which data may leave*, and
  /// this asks *how much detail this reader wants*. A slide can be perfectly
  /// shareable and still be more than a management audience came for. Folding
  /// any two of those into one field would mean a slide could not be, say,
  /// public and deep at once.
  ///
  /// Round-trips as `<!-- ocideck_detail -->`, written only when true, so a deck
  /// that never uses it is byte-identical to before.
  final bool isDetail;

  /// Wat er met privacybevindingen op déze slide gebeurt. `null` = erf de stand
  /// van het deck. Round-trips als `<!-- ocideck_privacy: … -->`.
  final PrivacyDisposition? privacy;

  /// Wat er met de kwaliteitsmeldingen van déze slide gebeurt. Round-trips als
  /// `<!-- ocideck_quality: … -->`.
  ///
  /// Anders dan [privacy] niet nullable: er is geen deckbrede kwaliteitsstand om
  /// van te erven. Een kwaliteitsoordeel gaat over déze slide — een deck dat in
  /// één keer alle contrastfouten accepteert is geen keuze maar een uitschakelaar,
  /// en daar is de instelling voor.
  final QualityDisposition quality;
  final List<List<String>> tableRows; // first row is the header

  /// Table slides only: whether the table may be edited live during a
  /// presentation. Off by default, so tables are read-only unless the author
  /// explicitly opts in from the builder. Older presentations lack the token
  /// and therefore keep the safe default (not editable).
  final bool tableEditable;

  /// Table slides only: whether a cell holding an ISO date in the past is
  /// marked as expired. Off by default — a table of historical dates would
  /// otherwise turn entirely red, which says nothing. Derived at render time
  /// against the day the deck is shown, never stored per cell: a flag you type
  /// freezes at whatever was true the day you wrote it, so a deck presented two
  /// months later would go on claiming everything is on schedule.
  final bool tableMarkOverdue;

  /// Timeline slides only: how the events are arranged and animated. The events
  /// themselves are stored in [bullets] as `marker :: title :: description`
  /// strings; the layout/reveal options round-trip as `_class` tokens and the
  /// draw-in duration as an `ocideck_timeline_duration` comment.
  final TimelineLayout timelineLayout;
  final TimelineReveal timelineReveal;

  /// Per-slide draw-in duration override (ms). `null` = inherit the theme's
  /// ThemeProfile.animationDurationMs. Only a non-null value round-trips as an
  /// `ocideck_timeline_duration` comment.
  final int? timelineAnimationMs;

  /// Timeline slides only: 0-based index of the event highlighted as the
  /// "current point" (where we are now, e.g. a project's present phase).
  /// `null` = no current point. Round-trips as a 1-based
  /// `ocideck_timeline_current` comment so the `.md` reads as an event number.
  final int? timelineCurrentIndex;

  /// The finding group this slide belongs to (PENTEST_MIAUW §3.1). Empty = the
  /// slide is not part of a finding. Every slide sharing a non-empty id forms
  /// one finding — a header card plus its detail/evidence slides — that carries
  /// a single finding id and a single severity (derived from the header's CVSS
  /// vector, never stored). Round-trips as `<!-- ocideck_finding_id: F-03 -->`.
  final String findingId;

  /// This slide's [FindingRole] within its finding group; only meaningful when
  /// [findingId] is set. A `finding`-typed slide is the group's
  /// [FindingRole.header]. Round-trips as `<!-- ocideck_finding_role: … -->`.
  final FindingRole findingRole;

  /// The names of fields on this slide whose text was drafted by AI and not yet
  /// human-reviewed (AI_ASSIST / PENTEST_MIAUW §16.3). Empty for hand-authored
  /// slides. While any slide carries such a marker the deck **cannot be sealed**
  /// (the EIS 1.6 attestation must cover human-verified text) — see
  /// `deckHasUnreviewedAiMarkers`. AI drafting (P3-AIA) sets these and clears them
  /// on review. Round-trips as `<!-- ocideck_ai_assisted: field1, field2 -->`.
  final List<String> aiAssistedFields;

  /// For a `checklist` slide: the scope object this checklist covers (feedback
  /// #8, "per scope-object heb je een checklist"). Empty = not linked to any
  /// scope object. Matched against a [ScopeRow.object] via `normalizeScopeObject`
  /// (like the finding↔scope link), so it stores the plain object string.
  /// Round-trips as `<!-- ocideck_checklist_scope: https://app.example/login -->`.
  final String checklistScope;

  /// Which page of a paginated rich-text body this copy of the slide renders.
  ///
  /// Render-only, and deliberately absent from the file format: a long free-text
  /// slide is one slide in the deck, but presents as several full-size pages.
  /// `expandRichTextForRender` makes one copy per page for surfaces that
  /// enumerate slides rather than page through them — the export above all,
  /// which used to rasterise page 1 and silently drop the rest. Every copy keeps
  /// the *whole* body, because the page split and the shared font scale are
  /// properties of the body as a whole; handing a renderer one page's markdown
  /// in isolation would size that page on its own and the text would grow and
  /// shrink from page to page.
  ///
  /// Always 0 on a slide that came from a file, and never serialised — see
  /// `Slide.duplicate`, which resets it.
  final int renderPage;

  const Slide({
    required this.id,
    required this.type,
    this.title = '',
    this.subtitle = '',
    this.bullets = const [],
    this.bullets2 = const [],
    this.listStyle = ListStyle.bullets,
    this.showChecklistProgress = false,
    this.continueNumbering = false,
    this.continuesSplit = false,
    this.columnTitle1 = '',
    this.columnTitle2 = '',
    this.imagePath = '',
    this.imagePath2 = '',
    this.imageCaption = '',
    this.imageCaption2 = '',
    this.imageAltText = '',
    this.imageAltText2 = '',
    this.imageFocalX = 0.5,
    this.imageFocalY = 0.5,
    this.imageFocalX2 = 0.5,
    this.imageFocalY2 = 0.5,
    this.videoPath = '',
    this.videoAutoplay = false,
    this.videoStartMs = 0,
    this.videoEndMs = 0,
    this.audioPath = '',
    this.audioAutoplay = false,
    this.mediaRedacted = false,
    this.contentRedacted = false,
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
    this.privacy,
    this.quality = QualityDisposition.warn,
    this.tableRows = const [],
    this.tableEditable = false,
    this.tableMarkOverdue = false,
    this.isDetail = false,
    this.timelineLayout = TimelineLayout.auto,
    this.timelineReveal = TimelineReveal.onEnter,
    this.timelineAnimationMs,
    this.timelineCurrentIndex,
    this.findingId = '',
    this.findingRole = FindingRole.header,
    this.aiAssistedFields = const [],
    this.checklistScope = '',
    this.renderPage = 0,
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
          : type == SlideType.checklist
          // Start met de vaste kop + twee lege testregels, zodat de
          // checklist-editor meteen invulbare rijen toont.
          ? const ChecklistSpec(
              rows: [ChecklistRow(), ChecklistRow()],
            ).toTableRows()
          : type == SlideType.scopeMatrix
          // Start met de vaste kop + één lege scope-regel; objecten voeg je toe
          // of verwijder je zelf.
          ? const ScopeMatrixSpec(rows: [ScopeRow()]).toTableRows()
          : type == SlideType.findingsSummary
          // Start met de vaste kop + één nulrij per ernstband; de editor vult ze
          // (of vernieuwt ze uit het deck).
          ? const FindingsSummarySpec().toTableRows()
          : type == SlideType.scorecard
          // Alleen de vaste kop. Lege cijferregels horen niet op schijf — de
          // editor deelt ze zelf uit zolang er nog niets is ingevuld.
          ? const ScorecardSpec().toTableRows()
          : type == SlideType.assets
          ? const AssetOverviewSpec().toTableRows()
          : type == SlideType.discoveries
          // Alleen de vaste kop; de editor deelt de eerste lege regel uit.
          ? const DiscoveriesSpec().toTableRows()
          : const [],
      customMarkdown: type == SlideType.cockpit
          ? CockpitSpec.samplePreset().toBlock()
          : type == SlideType.question
          ? QuestionSpec.defaultMultipleChoice().toBlock()
          : type == SlideType.finding
          ? const FindingSpec().toMarkdown()
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
      continueNumbering: src.continueNumbering,
      continuesSplit: src.continuesSplit,
      columnTitle1: src.columnTitle1,
      columnTitle2: src.columnTitle2,
      imagePath: src.imagePath,
      imagePath2: src.imagePath2,
      imageCaption: src.imageCaption,
      imageCaption2: src.imageCaption2,
      imageAltText: src.imageAltText,
      imageAltText2: src.imageAltText2,
      imageFocalX: src.imageFocalX,
      imageFocalY: src.imageFocalY,
      imageFocalX2: src.imageFocalX2,
      imageFocalY2: src.imageFocalY2,
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
      privacy: src.privacy,
      quality: src.quality,
      tableRows: src.tableRows.map((r) => List<String>.from(r)).toList(),
      tableEditable: src.tableEditable,
      tableMarkOverdue: src.tableMarkOverdue,
      isDetail: src.isDetail,
      timelineLayout: src.timelineLayout,
      timelineReveal: src.timelineReveal,
      timelineAnimationMs: src.timelineAnimationMs,
      timelineCurrentIndex: src.timelineCurrentIndex,
      findingId: src.findingId,
      findingRole: src.findingRole,
      aiAssistedFields: src.aiAssistedFields,
      checklistScope: src.checklistScope,
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
    bool? continueNumbering,
    bool? continuesSplit,
    String? columnTitle1,
    String? columnTitle2,
    String? imagePath,
    String? imagePath2,
    String? imageCaption,
    String? imageCaption2,
    String? imageAltText,
    String? imageAltText2,
    double? imageFocalX,
    double? imageFocalY,
    double? imageFocalX2,
    double? imageFocalY2,
    String? videoPath,
    bool? videoAutoplay,
    int? videoStartMs,
    int? videoEndMs,
    String? audioPath,
    bool? audioAutoplay,
    bool? mediaRedacted,
    bool? contentRedacted,
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
    PrivacyDisposition? privacy,
    bool clearPrivacy = false,
    QualityDisposition? quality,
    List<List<String>>? tableRows,
    bool? tableEditable,
    bool? tableMarkOverdue,
    bool? isDetail,
    TimelineLayout? timelineLayout,
    TimelineReveal? timelineReveal,
    int? timelineAnimationMs,
    bool clearTimelineAnimation = false,
    int? timelineCurrentIndex,
    bool clearTimelineCurrent = false,
    String? findingId,
    FindingRole? findingRole,
    List<String>? aiAssistedFields,
    String? checklistScope,
    int? renderPage,
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
      continueNumbering: continueNumbering ?? this.continueNumbering,
      continuesSplit: continuesSplit ?? this.continuesSplit,
      columnTitle1: columnTitle1 ?? this.columnTitle1,
      columnTitle2: columnTitle2 ?? this.columnTitle2,
      imagePath: imagePath ?? this.imagePath,
      imagePath2: imagePath2 ?? this.imagePath2,
      imageCaption: imageCaption ?? this.imageCaption,
      imageCaption2: imageCaption2 ?? this.imageCaption2,
      imageAltText: imageAltText ?? this.imageAltText,
      imageAltText2: imageAltText2 ?? this.imageAltText2,
      imageFocalX: imageFocalX ?? this.imageFocalX,
      imageFocalY: imageFocalY ?? this.imageFocalY,
      imageFocalX2: imageFocalX2 ?? this.imageFocalX2,
      imageFocalY2: imageFocalY2 ?? this.imageFocalY2,
      videoPath: videoPath ?? this.videoPath,
      videoAutoplay: videoAutoplay ?? this.videoAutoplay,
      videoStartMs: videoStartMs ?? this.videoStartMs,
      videoEndMs: videoEndMs ?? this.videoEndMs,
      audioPath: audioPath ?? this.audioPath,
      mediaRedacted: mediaRedacted ?? this.mediaRedacted,
      contentRedacted: contentRedacted ?? this.contentRedacted,
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
      privacy: clearPrivacy ? null : (privacy ?? this.privacy),
      quality: quality ?? this.quality,
      tableRows: tableRows ?? this.tableRows,
      tableEditable: tableEditable ?? this.tableEditable,
      tableMarkOverdue: tableMarkOverdue ?? this.tableMarkOverdue,
      isDetail: isDetail ?? this.isDetail,
      timelineLayout: timelineLayout ?? this.timelineLayout,
      timelineReveal: timelineReveal ?? this.timelineReveal,
      timelineAnimationMs: clearTimelineAnimation
          ? null
          : (timelineAnimationMs ?? this.timelineAnimationMs),
      timelineCurrentIndex: clearTimelineCurrent
          ? null
          : (timelineCurrentIndex ?? this.timelineCurrentIndex),
      findingId: findingId ?? this.findingId,
      findingRole: findingRole ?? this.findingRole,
      aiAssistedFields: aiAssistedFields ?? this.aiAssistedFields,
      checklistScope: checklistScope ?? this.checklistScope,
      renderPage: renderPage ?? this.renderPage,
    );
  }

  /// Add or remove [field] from [aiAssistedFields] (AI_ASSIST §16.3 provenance):
  /// an AI draft marks the field so the seal-gate blocks until reviewed; a manual
  /// edit clears it (the human has reviewed it). De-duplicates on add.
  Slide withAiAssistedField(String field, {required bool present}) => copyWith(
    aiAssistedFields: present
        ? {...aiAssistedFields, field}.toList()
        : aiAssistedFields.where((f) => f != field).toList(),
  );
}
