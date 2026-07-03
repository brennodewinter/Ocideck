import 'chart.dart';
import 'cockpit.dart';
import 'question.dart';
import 'slide.dart';
import 'timeline.dart';

// The builder bodies live in part files, grouped by theme, so no single file
// outgrows the repo's line ratchet as the template catalogue grows.
part 'deck_template_general.dart';

/// A starting-point recipe for a new presentation: a title page plus a set of
/// example slides the user overwrites with real content. Templates are pure
/// data — [title] and [description] are Dutch source strings, localised via
/// `l10n.d(...)` at the call site (the same pattern as [slideTypeMeta]), and
/// [icon] is a semantic key resolved to a picker icon in the widget layer, so
/// this layer stays Flutter-free.
class DeckTemplate {
  final String id;

  /// Dutch source title, localised via `l10n.d(...)` at the call site.
  final String title;

  /// Dutch source one-liner shown under the title in the template picker,
  /// localised via `l10n.d(...)` at the call site.
  final String description;

  /// Semantic icon key, mapped to the picker icon in the widget layer.
  final String icon;

  /// Builds the fresh slides for a deck titled [deckTitle]. Every template
  /// starts with a title slide carrying that title.
  final List<Slide> Function(String deckTitle) buildSlides;

  const DeckTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.buildSlides,
  });
}

/// All templates offered by the new-presentation wizard, in picker order. The
/// first entry (the empty deck) is the default choice.
final List<DeckTemplate> deckTemplates = [
  DeckTemplate(
    id: 'empty',
    title: 'Leeg deck',
    description: 'Alleen een titelpagina en een agenda.',
    icon: 'empty',
    buildSlides: _buildEmpty,
  ),
  DeckTemplate(
    id: 'briefing',
    title: 'Korte briefing',
    description: 'Situatie, feiten en gevraagd besluit in zes slides.',
    icon: 'briefing',
    buildSlides: _buildBriefing,
  ),
  DeckTemplate(
    id: 'status',
    title: 'Status-briefing',
    description: 'Statusdashboard, voortgang per werkstroom en besluiten.',
    icon: 'status',
    buildSlides: _buildStatus,
  ),
  DeckTemplate(
    id: 'kickoff',
    title: 'Projectstart / kick-off',
    description: 'Waarom, doel, scope, stakeholders en tijdlijn.',
    icon: 'kickoff',
    buildSlides: _buildKickoff,
  ),
  DeckTemplate(
    id: 'communication',
    title: 'Voorbespreking communicatie',
    description: 'Doelgroepen, kernboodschap, kanalen en woordvoering.',
    icon: 'communication',
    buildSlides: _buildCommunication,
  ),
  DeckTemplate(
    id: 'projectTimeline',
    title: 'Projecttijdlijn',
    description: 'Fases, mijlpalen, afhankelijkheden en beslismomenten.',
    icon: 'projectTimeline',
    buildSlides: _buildProjectTimeline,
  ),
  DeckTemplate(
    id: 'rasci',
    title: 'Informatiebeveiliging: RASCI / TVB',
    description: 'Rollen, RASCI-matrix en taakafspraken vastleggen.',
    icon: 'rasci',
    buildSlides: _buildRasci,
  ),
  DeckTemplate(
    id: 'securityTasks',
    title: 'Security-takenplan',
    description: 'Taken, prioriteiten, eigenaren en bewijsstukken.',
    icon: 'securityTasks',
    buildSlides: _buildSecurityTasks,
  ),
  DeckTemplate(
    id: 'certification',
    title: 'Certificering voortgang',
    description: 'Voortgang per domein, controls en auditplanning.',
    icon: 'certification',
    buildSlides: _buildCertification,
  ),
  DeckTemplate(
    id: 'training',
    title: 'Training / workshop',
    description: 'Leerdoelen, kernconcepten, oefening en quizvraag.',
    icon: 'training',
    buildSlides: _buildTraining,
  ),
  DeckTemplate(
    id: 'report',
    title: 'Rapportage',
    description: 'Samenvatting, KPI-dashboard, trend en acties.',
    icon: 'report',
    buildSlides: _buildReport,
  ),
  DeckTemplate(
    id: 'research',
    title: 'Onderzoeksverhaal',
    description: 'Vraag, methode, tijdlijn van bevindingen en conclusies.',
    icon: 'research',
    buildSlides: _buildResearch,
  ),
  DeckTemplate(
    id: 'technical',
    title: 'Technische uitleg',
    description: 'Architectuur, componenten, codevoorbeeld en checklist.',
    icon: 'technical',
    buildSlides: _buildTechnical,
  ),
  DeckTemplate(
    id: 'quiz',
    title: 'Interactieve quiz',
    description: 'Drie vraagvormen met uitleg en nabespreking.',
    icon: 'quiz',
    buildSlides: _buildQuiz,
  ),
];

DeckTemplate? deckTemplateById(String id) {
  for (final template in deckTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

// ── Slide shorthands ─────────────────────────────────────────────────────────
// Thin wrappers around Slide.create + copyWith so each template below reads
// as a table of contents instead of forty lines of constructor noise.

Slide _title(String deckTitle) =>
    Slide.create(SlideType.title).copyWith(title: deckTitle);

Slide _section(String title) =>
    Slide.create(SlideType.section).copyWith(title: title);

Slide _bullets(
  String title,
  List<String> bullets, {
  ListStyle listStyle = ListStyle.bullets,
  bool showChecklistProgress = false,
}) => Slide.create(SlideType.bullets).copyWith(
  title: title,
  bullets: bullets,
  listStyle: listStyle,
  showChecklistProgress: showChecklistProgress,
);

/// A checklist slide. Items may be given with or without the leading `[ ] `
/// marker; unchecked boxes are added where missing. [showProgress] renders
/// the checked-count progress bar — use it on central action/go-no-go lists.
Slide _checklist(
  String title,
  List<String> items, {
  bool showProgress = false,
}) => _bullets(
  title,
  [
    for (final item in items)
      item.startsWith('[ ]') || item.startsWith('[x]') ? item : '[ ] $item',
  ],
  listStyle: ListStyle.checklist,
  showChecklistProgress: showProgress,
);

Slide _twoBullets(
  String title, {
  required String columnTitle1,
  required List<String> bullets,
  required String columnTitle2,
  required List<String> bullets2,
}) => Slide.create(SlideType.twoBullets).copyWith(
  title: title,
  columnTitle1: columnTitle1,
  bullets: bullets,
  columnTitle2: columnTitle2,
  bullets2: bullets2,
);

/// A table slide; [editable] marks it as a live work table that may be
/// filled in during a presentation (round-trips as the table-editable token).
Slide _table(String title, List<List<String>> rows, {bool editable = false}) =>
    Slide.create(
      SlideType.table,
    ).copyWith(title: title, tableRows: rows, tableEditable: editable);

Slide _timeline(String title, List<TimelineEvent> events) => Slide.create(
  SlideType.timeline,
).copyWith(title: title, bullets: timelineEventsToBullets(events));

Slide _quote(String quote, String author) =>
    Slide.create(SlideType.quote).copyWith(quote: quote, quoteAuthor: author);

Slide _freeMarkdown(String markdown) =>
    Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: markdown);

Slide _code(String title, String language, String code) => Slide.create(
  SlideType.code,
).copyWith(title: title, codeLanguage: language, customMarkdown: code);

Slide _chart(String title, ChartSpec spec) => Slide.create(
  SlideType.chart,
).copyWith(title: title, customMarkdown: spec.toBlock());

Slide _cockpit(String title, CockpitSpec spec) => Slide.create(
  SlideType.cockpit,
).copyWith(title: title, customMarkdown: spec.toBlock());

Slide _question(String title, QuestionSpec spec) => Slide.create(
  SlideType.question,
).copyWith(title: title, customMarkdown: spec.toBlock());
