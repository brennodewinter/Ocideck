import 'chart.dart';
import 'cockpit.dart';
import 'finding_spec.dart';
import 'question.dart';
import 'slide.dart';
import 'timeline.dart';

// The builder bodies live in part files, grouped by theme, so no single file
// outgrows the repo's line ratchet as the template catalogue grows.
part 'deck_template_general.dart';
part 'deck_template_work_a.dart';
part 'deck_template_work_b.dart';
part 'deck_template_sessions.dart';
part 'deck_template_briefings.dart';
part 'deck_template_conversations.dart';
part 'deck_template_info_safety.dart';

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

  /// True for templates that only make sense with the "Informatieveiligheid"
  /// module on (they scaffold module-only slide types like `finding` /
  /// `scopeMatrix`). The picker hides them until `infoSafetyRevealProvider` is
  /// true, so the flat catalogue stays uncluttered for everyone else.
  final bool requiresInfoSafety;

  const DeckTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.buildSlides,
    this.requiresInfoSafety = false,
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
    id: 'securityGuardBriefing',
    title: 'Beveiligingsbriefing / dienststart',
    description:
        'Actualiteiten, aandachtsvestigingen, bijzonderheden, onderhoud en '
        'bezetting voor de beveiligingsdienst.',
    icon: 'securityGuardBriefing',
    buildSlides: _buildSecurityGuardBriefing,
  ),
  DeckTemplate(
    id: 'policeBriefing',
    title: 'Operationele politiebriefing',
    description:
        'Actualiteiten, hotspots, signaleringen, opdrachten, eigen veiligheid '
        'en gebiedsinzet voor de dienst.',
    icon: 'policeBriefing',
    buildSlides: _buildPoliceBriefing,
  ),
  DeckTemplate(
    id: 'enforcementBriefing',
    title: 'Handhavingsbriefing (BOA)',
    description:
        'Aandachtslocaties, overlast, evenementen, bevoegdheden, eigen '
        'veiligheid en gebiedsinzet voor de handhavingsdienst.',
    icon: 'enforcementBriefing',
    buildSlides: _buildEnforcementBriefing,
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
    title: 'Informatieveiligheid: RASCI / TVB',
    description: 'Rollen, RASCI-matrix en taakafspraken vastleggen.',
    icon: 'rasci',
    buildSlides: _buildRasci,
  ),
  DeckTemplate(
    id: 'securityTasks',
    title: 'Takenplan informatieveiligheid',
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
    id: 'postIncidentReview',
    title: 'Post-incident review / lessons learned',
    description:
        'Tijdlijn, impact, oorzaken en verbeteracties na een incident.',
    icon: 'postIncidentReview',
    buildSlides: _buildPostIncidentReview,
  ),
  DeckTemplate(
    id: 'privacyIncident',
    title: 'Datalek / privacy-incident beoordeling',
    description: 'Beoordeel gegevens, risico, meldplicht en communicatie.',
    icon: 'privacyIncident',
    buildSlides: _buildPrivacyIncident,
  ),
  DeckTemplate(
    id: 'dpia',
    title: 'DPIA / privacy impact assessment',
    description: "Verwerking, grondslag, privacyrisico's en maatregelen.",
    icon: 'dpia',
    buildSlides: _buildDpia,
  ),
  DeckTemplate(
    id: 'riskRegister',
    title: 'Risicoanalyse / risk register',
    description: "Leg risico's, kans, impact, maatregelen en eigenaren vast.",
    icon: 'riskRegister',
    buildSlides: _buildRiskRegister,
  ),
  DeckTemplate(
    id: 'continuityTest',
    title: 'Business continuity / DR-test',
    description: 'Scenario, hersteldoelen, testbevindingen en verbeterpunten.',
    icon: 'continuityTest',
    buildSlides: _buildContinuityTest,
  ),
  DeckTemplate(
    id: 'tabletopExercise',
    title: 'Tabletop-oefening / crisisoefening',
    description: 'Scenario, injects, besluiten, waarnemingen en evaluatie.',
    icon: 'tabletopExercise',
    buildSlides: _buildTabletopExercise,
  ),
  DeckTemplate(
    id: 'bobCrisis',
    title: 'BOB-crisisrapportage',
    description:
        'Leid een crisisteam door beeldvorming, oordeelsvorming en '
        'besluitvorming, met live situatiebeeld, informatievragen, '
        "dilemma's, besluitenlog en actielijst.",
    icon: 'bobCrisis',
    buildSlides: _buildBobCrisis,
  ),
  DeckTemplate(
    id: 'releaseReadiness',
    title: 'CAB / release readiness',
    description:
        'Wijziging, impact, tests, rollback, communicatie en go/no-go.',
    icon: 'releaseReadiness',
    buildSlides: _buildReleaseReadiness,
  ),
  DeckTemplate(
    id: 'steeringUpdate',
    title: 'Stuurgroep / project board update',
    description: "Voortgang, planning, budget, risico's en besluiten gevraagd.",
    icon: 'steeringUpdate',
    buildSlides: _buildSteeringUpdate,
  ),
  DeckTemplate(
    id: 'auditFollowup',
    title: 'Auditbevindingen en opvolging',
    description: 'Bevindingen, root cause, maatregelen, bewijs en status.',
    icon: 'auditFollowup',
    buildSlides: _buildAuditFollowup,
  ),
  DeckTemplate(
    id: 'vendorRisk',
    title: 'Leveranciersbeoordeling / vendor risk',
    description: "Dienst, data, afhankelijkheid, eisen, risico's en besluit.",
    icon: 'vendorRisk',
    buildSlides: _buildVendorRisk,
  ),
  DeckTemplate(
    id: 'architectureDecision',
    title: 'Architectuurbesluit / ADR-presentatie',
    description: 'Context, opties, trade-offs, besluit en gevolgen.',
    icon: 'architectureDecision',
    buildSlides: _buildArchitectureDecision,
  ),
  DeckTemplate(
    id: 'policyRollout',
    title: 'Beleid uitrollen / implementatieplan',
    description: 'Doelgroep, planning, communicatie, training en adoptie.',
    icon: 'policyRollout',
    buildSlides: _buildPolicyRollout,
  ),
  DeckTemplate(
    id: 'handover',
    title: 'Overdracht / handover',
    description: "Status, open acties, risico's, contacten en eerste stappen.",
    icon: 'handover',
    buildSlides: _buildHandover,
  ),
  DeckTemplate(
    id: 'retrospective',
    title: 'Retrospective / teamverbetering',
    description: 'Feiten, patronen, start-stop-continue en verbeteracties.',
    icon: 'retrospective',
    buildSlides: _buildRetrospective,
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
  // ── Gesprekssjablonen ──────────────────────────────────────────────────────
  DeckTemplate(
    id: 'jobInterview',
    title: 'Sollicitatiegesprek',
    description:
        'Bereid je voor met STAR-antwoorden, eigen vragen en '
        'arbeidsvoorwaarden.',
    icon: 'jobInterview',
    buildSlides: _buildJobInterview,
  ),
  DeckTemplate(
    id: 'performanceReview',
    title: 'Functioneringsgesprek',
    description:
        'Resultaten, ontwikkelwensen en afspraken volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'performanceReview',
    buildSlides: _buildPerformanceReview,
  ),
  DeckTemplate(
    id: 'salaryNegotiation',
    title: 'Salarisonderhandeling',
    description:
        'Onderbouwing, bandbreedte en tegenargumenten volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'salaryNegotiation',
    buildSlides: _buildSalaryNegotiation,
  ),
  DeckTemplate(
    id: 'moreResponsibility',
    title: 'Meer verantwoordelijkheid vragen',
    description:
        'Vraag je leidinggevende om een grotere rol volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'moreResponsibility',
    buildSlides: _buildMoreResponsibility,
  ),
  DeckTemplate(
    id: 'raiseWorkplaceIssue',
    title: 'Probleem op de werkvloer aankaarten',
    description:
        'Maak een probleem bespreekbaar zonder te beschuldigen, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'raiseWorkplaceIssue',
    buildSlides: _buildRaiseWorkplaceIssue,
  ),
  DeckTemplate(
    id: 'resolveConflict',
    title: 'Conflict uitpraten',
    description:
        'Kom er samen uit met feiten, veiligheid en luisteren, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'resolveConflict',
    buildSlides: _buildResolveConflict,
  ),
  DeckTemplate(
    id: 'giveReceiveFeedback',
    title: 'Kritiek geven of ontvangen',
    description:
        'Geef en ontvang feedback met feit, effect en verzoek, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'giveReceiveFeedback',
    buildSlides: _buildGiveReceiveFeedback,
  ),
  DeckTemplate(
    id: 'deliverBadNews',
    title: 'Slecht nieuws brengen',
    description:
        'Breng slecht nieuws duidelijk en met respect, volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'deliverBadNews',
    buildSlides: _buildDeliverBadNews,
  ),
  DeckTemplate(
    id: 'setBoundaries',
    title: 'Grenzen stellen',
    description:
        'Zet je grens rustig en duidelijk neer, volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'setBoundaries',
    buildSlides: _buildSetBoundaries,
  ),
  DeckTemplate(
    id: 'strainedRelationship',
    title: 'Stroef lopende relatie bespreken',
    description:
        'Bespreek een relatie of vriendschap die stroef loopt, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'strainedRelationship',
    buildSlides: _buildStrainedRelationship,
  ),
  DeckTemplate(
    id: 'clientConversation',
    title: 'Klantgesprek',
    description:
        'Behoefteanalyse, waardevertaling en bezwaren voor een goed '
        'klantgesprek.',
    icon: 'clientConversation',
    buildSlides: _buildClientConversation,
  ),
  DeckTemplate(
    id: 'salesConversation',
    title: 'Verkoopgesprek',
    description:
        'SPIN-vragen, waardevertaling, bezwaren en afsluiten voor een '
        'verkoopgesprek.',
    icon: 'salesConversation',
    buildSlides: _buildSalesConversation,
  ),
  DeckTemplate(
    id: 'supplierNegotiation',
    title: 'Onderhandeling met leveranciers',
    description:
        'Eisen, onderhandelruimte en tactieken met BATNA en ZOPA voor een '
        'leveranciersonderhandeling.',
    icon: 'supplierNegotiation',
    buildSlides: _buildSupplierNegotiation,
  ),
  DeckTemplate(
    id: 'pitch',
    title: 'Pitch geven',
    description:
        'Haak, probleem, oplossing, bewijs en vraag voor een overtuigende '
        'pitch.',
    icon: 'pitch',
    buildSlides: _buildPitch,
  ),
  DeckTemplate(
    id: 'meetingToGetBuyIn',
    title: 'Iets voor elkaar krijgen in een vergadering',
    description:
        'Stakeholders, argumentatie en bezwaren om een besluit of steun te '
        'krijgen in een vergadering.',
    icon: 'meetingToGetBuyIn',
    buildSlides: _buildMeetingToGetBuyIn,
  ),
  DeckTemplate(
    id: 'pplFlightPrep',
    title: 'PPL Vluchtvoorbereiding',
    description:
        'Bereid een VFR-vlucht voor met route, weer, NOTAMs, prestaties, '
        'weight & balance, brandstof, alternates en persoonlijke '
        'go/no-go checks.',
    icon: 'pplFlightPrep',
    buildSlides: _buildPplFlightPrep,
  ),
  DeckTemplate(
    id: 'miauwReport',
    title: 'MIAUW-pentestrapport',
    description:
        'Volledige MIAUW-rapportstructuur: documentbeheer, scope, executie, '
        'managementsamenvatting, bevindingen, checklists en ondertekening.',
    icon: 'miauwReport',
    buildSlides: _buildMiauwReport,
    requiresInfoSafety: true,
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
