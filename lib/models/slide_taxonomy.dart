part of 'slide.dart';

/// Broad grouping a [SlideType] belongs to, used by the add-slide picker to
/// offer category tabs. The picker derives its tabs from the categories that
/// are actually present.
enum SlideCategory {
  general,
  informationSecurity,
  procesverbetering,
  managementsysteem,
  eLearning,
}

/// Hoeveel kolommen doorlopende bullettekst een [SlideType] toont.
enum BulletColumns { none, one, two }

/// The part a slide plays inside a finding group.
enum FindingRole { header, detail, evidence }

enum ListStyle { bullets, numbered, checklist, richText }

/// Native Marp image-column layout for a title slide (#1405).
enum TitleColumnLayout { none, left, right, both }

/// Per-kolomuitlijning uit de GFM-scheidingsrij van een tabel.
enum TableAlign { left, center, right }

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

  /// eLearning types whose body is plain Markdown in [Slide.customMarkdown],
  /// written by `_writeFreeMarkdownSlide` and read back by
  /// `_parsedCustomMarkdown`.
  ///
  /// Dit predicaat bestaat omdat schrijver en lezer hier uit elkaar liepen
  /// (#1999): er wérd een body geschreven, maar het inlezen kende de
  /// eLearning-types niet en gaf een lege `customMarkdown` terug. De dia leek
  /// daardoor gewoon te openen, en de eerstvolgende opslag schreef de tekst van
  /// de auteur weg — zonder melding. Eén gedeelde bron voorkomt dat de twee
  /// kanten opnieuw kunnen verschillen.
  ///
  /// De regel is de categorie, niet een lijst namen, zodat een nieuw
  /// tekstgedragen eLearning-type meteen goed staat. Komt er ooit een
  /// eLearning-type dat zijn inhoud níet als vrije Markdown bewaart — een
  /// tabelgedragen of gestructureerd type — dan hoort het hier expliciet
  /// uitgezonderd te worden, net als bij [usesScaffoldMarkdownBody].
  bool get usesFreeMarkdownBody =>
      category == SlideCategory.eLearning && !backedByTable;
}

// ── Per-type pure data (verplaatst uit slide.dart voor het bestandsplafond) ──

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
  SlideType.quote: SlideTypeMeta(label: 'Citaat', marpClass: 'quote'),
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
  // Keuze-menu (#1162). De blokken staan in [Slide.bullets] als gewone
  // link-bullets, dus geen tabel-opslag en geen doorlopende bullettekst
  // (`bulletColumns.none`): een menu splits of pagineert niet.
  SlideType.menu: SlideTypeMeta(label: 'Keuzemenu', marpClass: 'menu'),
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
  // Procesverbetering-module. Het token is bewust domeinneutraal: een matrix is
  // een getypeerd raster en leunt op geen enkele methodologie (§6). De inhoud
  // is een gewone Markdown-tabel, dus [backedByTable].
  SlideType.matrix: SlideTypeMeta(
    label: 'Matrix',
    marpClass: 'matrix',
    category: SlideCategory.procesverbetering,
    backedByTable: true,
  ),
  // Canvas: regio's zijn `##`-koppen in gewone Markdown (PROCESS_IMPROVEMENT
  // §3.2). Geen tabel — de body leeft in [Slide.customMarkdown], zoals bij
  // finding/freeMarkdown.
  SlideType.canvas: SlideTypeMeta(
    label: 'Canvas',
    marpClass: 'canvas',
    category: SlideCategory.procesverbetering,
  ),
  // Boom: geneste Markdown-lijst (PROCESS_IMPROVEMENT §3.3). Diepte = tabs in
  // [Slide.bullets]; layout tree/fishbone via [Slide.improvementLayout].
  SlideType.tree: SlideTypeMeta(
    label: 'Boom',
    marpClass: 'tree',
    category: SlideCategory.procesverbetering,
  ),
  // Flow: stappenlijst met `::`-kenmerken (PROCESS_IMPROVEMENT §3.4).
  SlideType.flow: SlideTypeMeta(
    label: 'Stroom',
    marpClass: 'flow',
    category: SlideCategory.procesverbetering,
  ),
  SlideType.phaseGate: SlideTypeMeta(
    label: 'Fasepoort',
    marpClass: 'phase-gate',
    category: SlideCategory.procesverbetering,
    bulletColumns: BulletColumns.one,
  ),
  // Managementsysteem-module (ISO_MANAGEMENTSYSTEEM §4). Per-control
  // implementatiestatus als gewone Markdown-tabel, dus [backedByTable].
  SlideType.controlStatus: SlideTypeMeta(
    label: 'Beheersmaatregel-status',
    marpClass: 'control-status',
    category: SlideCategory.managementsysteem,
    backedByTable: true,
  ),
  // Procesverbetering-module: Gantt-diagram (GANTT_SLIDETYPE). Opslag is een
  // gewone Markdown-tabel met vijf vaste kolommen; de render leidt er Mermaid
  // gantt-DSL uit af. De tabel degradeert leesbaar in plain Marp.
  SlideType.gantt: SlideTypeMeta(
    label: 'Gantt',
    marpClass: 'gantt',
    category: SlideCategory.procesverbetering,
    backedByTable: true,
  ),
  // eLearning-module (#1999). Structurele slides voor leerinhoud.
  // Inhoud is gewone Markdown; de _class-tokens zijn domeinspecifiek
  // zodat importers ze herkennen, maar de render is plain Markdown.
  SlideType.objective: SlideTypeMeta(
    label: 'Leerdoel',
    marpClass: 'objective',
    category: SlideCategory.eLearning,
  ),
  SlideType.module: SlideTypeMeta(
    label: 'Module',
    marpClass: 'module',
    category: SlideCategory.eLearning,
    isHeading: true,
  ),
  SlideType.feedback: SlideTypeMeta(
    label: 'Feedback',
    marpClass: 'feedback',
    category: SlideCategory.eLearning,
  ),
  SlideType.assessmentSummary: SlideTypeMeta(
    label: 'Assessment-samenvatting',
    marpClass: 'assessment-summary',
    category: SlideCategory.eLearning,
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
