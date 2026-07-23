

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
    this.requiresInfoSafety = false,
  });
}

/// All templates offered by the new-presentation wizard, in picker order. The
/// first entry (the empty deck) is the default choice.
final List<DeckTemplate> deckTemplates = [
  DeckTemplate(
    id: 'empty',
    title: 'Leeg deck',
    description: 'Alleen een titelpagina.',
    icon: 'empty',
  ),
  DeckTemplate(
    id: 'briefing',
    title: 'Korte briefing',
    description: 'Situatie, feiten en gevraagd besluit in zes slides.',
    icon: 'briefing',
  ),
  DeckTemplate(
    id: 'securityGuardBriefing',
    title: 'Beveiligingsbriefing / dienststart',
    description:
        'Actualiteiten, aandachtsvestigingen, bijzonderheden, onderhoud en '
        'bezetting voor de beveiligingsdienst.',
    icon: 'securityGuardBriefing',
  ),
  DeckTemplate(
    id: 'policeBriefing',
    title: 'Operationele politiebriefing',
    description:
        'Actualiteiten, hotspots, signaleringen, opdrachten, eigen veiligheid '
        'en gebiedsinzet voor de dienst.',
    icon: 'policeBriefing',
  ),
  DeckTemplate(
    id: 'enforcementBriefing',
    title: 'Handhavingsbriefing (BOA)',
    description:
        'Aandachtslocaties, overlast, evenementen, bevoegdheden, eigen '
        'veiligheid en gebiedsinzet voor de handhavingsdienst.',
    icon: 'enforcementBriefing',
  ),
  DeckTemplate(
    id: 'status',
    title: 'Status-briefing',
    description: 'Statusdashboard, voortgang per werkstroom en besluiten.',
    icon: 'status',
  ),
  DeckTemplate(
    id: 'kickoff',
    title: 'Projectstart / kick-off',
    description: 'Waarom, doel, scope, stakeholders en tijdlijn.',
    icon: 'kickoff',
  ),
  DeckTemplate(
    id: 'communication',
    title: 'Voorbespreking communicatie',
    description: 'Doelgroepen, kernboodschap, kanalen en woordvoering.',
    icon: 'communication',
  ),
  DeckTemplate(
    id: 'projectTimeline',
    title: 'Projecttijdlijn',
    description: 'Fases, mijlpalen, afhankelijkheden en beslismomenten.',
    icon: 'projectTimeline',
  ),
  DeckTemplate(
    id: 'rasci',
    title: 'Informatieveiligheid: RASCI / TVB',
    description: 'Rollen, RASCI-matrix en taakafspraken vastleggen.',
    icon: 'rasci',
  ),
  DeckTemplate(
    id: 'securityTasks',
    title: 'Takenplan informatieveiligheid',
    description: 'Taken, prioriteiten, eigenaren en bewijsstukken.',
    icon: 'securityTasks',
  ),
  DeckTemplate(
    id: 'certification',
    title: 'Certificering voortgang',
    description: 'Voortgang per domein, controls en auditplanning.',
    icon: 'certification',
  ),
  DeckTemplate(
    id: 'training',
    title: 'Training / workshop',
    description: 'Leerdoelen, kernconcepten, oefening en quizvraag.',
    icon: 'training',
  ),
  DeckTemplate(
    id: 'report',
    title: 'Rapportage',
    description: 'Samenvatting, KPI-dashboard, trend en acties.',
    icon: 'report',
  ),
  DeckTemplate(
    id: 'postIncidentReview',
    title: 'Post-incident review / lessons learned',
    description:
        'Tijdlijn, impact, oorzaken en verbeteracties na een incident.',
    icon: 'postIncidentReview',
  ),
  DeckTemplate(
    id: 'privacyIncident',
    title: 'Datalek / privacy-incident beoordeling',
    description: 'Beoordeel gegevens, risico, meldplicht en communicatie.',
    icon: 'privacyIncident',
  ),
  DeckTemplate(
    id: 'dpia',
    title: 'DPIA / privacy impact assessment',
    description: "Verwerking, grondslag, privacyrisico's en maatregelen.",
    icon: 'dpia',
  ),
  DeckTemplate(
    id: 'riskRegister',
    title: 'Risicoanalyse / risk register',
    description: "Leg risico's, kans, impact, maatregelen en eigenaren vast.",
    icon: 'riskRegister',
  ),
  DeckTemplate(
    id: 'continuityTest',
    title: 'Business continuity / DR-test',
    description: 'Scenario, hersteldoelen, testbevindingen en verbeterpunten.',
    icon: 'continuityTest',
  ),
  DeckTemplate(
    id: 'tabletopExercise',
    title: 'Tabletop-oefening / crisisoefening',
    description: 'Scenario, injects, besluiten, waarnemingen en evaluatie.',
    icon: 'tabletopExercise',
  ),
  DeckTemplate(
    id: 'bobCrisis',
    title: 'BOB-crisisrapportage',
    description:
        'Leid een crisisteam door beeldvorming, oordeelsvorming en '
        'besluitvorming, met live situatiebeeld, informatievragen, '
        "dilemma's, besluitenlog en actielijst.",
    icon: 'bobCrisis',
  ),
  DeckTemplate(
    id: 'releaseReadiness',
    title: 'CAB / release readiness',
    description:
        'Wijziging, impact, tests, rollback, communicatie en go/no-go.',
    icon: 'releaseReadiness',
  ),
  DeckTemplate(
    id: 'steeringUpdate',
    title: 'Stuurgroep / project board update',
    description: "Voortgang, planning, budget, risico's en besluiten gevraagd.",
    icon: 'steeringUpdate',
  ),
  DeckTemplate(
    id: 'auditFollowup',
    title: 'Auditbevindingen en opvolging',
    description: 'Bevindingen, root cause, maatregelen, bewijs en status.',
    icon: 'auditFollowup',
  ),
  DeckTemplate(
    id: 'vendorRisk',
    title: 'Leveranciersbeoordeling / vendor risk',
    description: "Dienst, data, afhankelijkheid, eisen, risico's en besluit.",
    icon: 'vendorRisk',
  ),
  DeckTemplate(
    id: 'architectureDecision',
    title: 'Architectuurbesluit / ADR-presentatie',
    description: 'Context, opties, trade-offs, besluit en gevolgen.',
    icon: 'architectureDecision',
  ),
  DeckTemplate(
    id: 'policyRollout',
    title: 'Beleid uitrollen / implementatieplan',
    description: 'Doelgroep, planning, communicatie, training en adoptie.',
    icon: 'policyRollout',
  ),
  DeckTemplate(
    id: 'handover',
    title: 'Overdracht / handover',
    description: "Status, open acties, risico's, contacten en eerste stappen.",
    icon: 'handover',
  ),
  DeckTemplate(
    id: 'retrospective',
    title: 'Retrospective / teamverbetering',
    description: 'Feiten, patronen, start-stop-continue en verbeteracties.',
    icon: 'retrospective',
  ),
  DeckTemplate(
    id: 'research',
    title: 'Onderzoeksverhaal',
    description: 'Vraag, methode, tijdlijn van bevindingen en conclusies.',
    icon: 'research',
  ),
  DeckTemplate(
    id: 'technical',
    title: 'Technische uitleg',
    description: 'Architectuur, componenten, codevoorbeeld en checklist.',
    icon: 'technical',
  ),
  DeckTemplate(
    id: 'quiz',
    title: 'Interactieve quiz',
    description: 'Drie vraagvormen met uitleg en nabespreking.',
    icon: 'quiz',
  ),
  // ── Gesprekssjablonen ──────────────────────────────────────────────────────
  DeckTemplate(
    id: 'jobInterview',
    title: 'Sollicitatiegesprek',
    description:
        'Bereid je voor met STAR-antwoorden, eigen vragen en '
        'arbeidsvoorwaarden.',
    icon: 'jobInterview',
  ),
  DeckTemplate(
    id: 'performanceReview',
    title: 'Functioneringsgesprek',
    description:
        'Resultaten, ontwikkelwensen en afspraken volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'performanceReview',
  ),
  DeckTemplate(
    id: 'salaryNegotiation',
    title: 'Salarisonderhandeling',
    description:
        'Onderbouwing, bandbreedte en tegenargumenten volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'salaryNegotiation',
  ),
  DeckTemplate(
    id: 'moreResponsibility',
    title: 'Meer verantwoordelijkheid vragen',
    description:
        'Vraag je leidinggevende om een grotere rol volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'moreResponsibility',
  ),
  DeckTemplate(
    id: 'raiseWorkplaceIssue',
    title: 'Probleem op de werkvloer aankaarten',
    description:
        'Maak een probleem bespreekbaar zonder te beschuldigen, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'raiseWorkplaceIssue',
  ),
  DeckTemplate(
    id: 'resolveConflict',
    title: 'Conflict uitpraten',
    description:
        'Kom er samen uit met feiten, veiligheid en luisteren, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'resolveConflict',
  ),
  DeckTemplate(
    id: 'giveReceiveFeedback',
    title: 'Kritiek geven of ontvangen',
    description:
        'Geef en ontvang feedback met feit, effect en verzoek, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'giveReceiveFeedback',
  ),
  DeckTemplate(
    id: 'deliverBadNews',
    title: 'Slecht nieuws brengen',
    description:
        'Breng slecht nieuws duidelijk en met respect, volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'deliverBadNews',
  ),
  DeckTemplate(
    id: 'setBoundaries',
    title: 'Grenzen stellen',
    description:
        'Zet je grens rustig en duidelijk neer, volgens de aanpak voor '
        'cruciale gesprekken.',
    icon: 'setBoundaries',
  ),
  DeckTemplate(
    id: 'strainedRelationship',
    title: 'Stroef lopende relatie bespreken',
    description:
        'Bespreek een relatie of vriendschap die stroef loopt, volgens de '
        'aanpak voor cruciale gesprekken.',
    icon: 'strainedRelationship',
  ),
  DeckTemplate(
    id: 'clientConversation',
    title: 'Klantgesprek',
    description:
        'Behoefteanalyse, waardevertaling en bezwaren voor een goed '
        'klantgesprek.',
    icon: 'clientConversation',
  ),
  DeckTemplate(
    id: 'salesConversation',
    title: 'Verkoopgesprek',
    description:
        'SPIN-vragen, waardevertaling, bezwaren en afsluiten voor een '
        'verkoopgesprek.',
    icon: 'salesConversation',
  ),
  DeckTemplate(
    id: 'supplierNegotiation',
    title: 'Onderhandeling met leveranciers',
    description:
        'Eisen, onderhandelruimte en tactieken met BATNA en ZOPA voor een '
        'leveranciersonderhandeling.',
    icon: 'supplierNegotiation',
  ),
  DeckTemplate(
    id: 'pitch',
    title: 'Pitch geven',
    description:
        'Haak, probleem, oplossing, bewijs en vraag voor een overtuigende '
        'pitch.',
    icon: 'pitch',
  ),
  DeckTemplate(
    id: 'meetingToGetBuyIn',
    title: 'Iets voor elkaar krijgen in een vergadering',
    description:
        'Stakeholders, argumentatie en bezwaren om een besluit of steun te '
        'krijgen in een vergadering.',
    icon: 'meetingToGetBuyIn',
  ),
  DeckTemplate(
    id: 'pplFlightPrep',
    title: 'PPL Vluchtvoorbereiding',
    description:
        'Bereid een VFR-vlucht voor met route, weer, NOTAMs, prestaties, '
        'weight & balance, brandstof, alternates en persoonlijke '
        'go/no-go checks.',
    icon: 'pplFlightPrep',
  ),
  DeckTemplate(
    id: 'miauwReport',
    title: 'MIAUW-pentestrapport',
    description:
        'Volledige MIAUW-rapportstructuur: documentbeheer, scope, executie, '
        'managementsamenvatting, bevindingen, checklists en ondertekening.',
    icon: 'miauwReport',
    requiresInfoSafety: true,
  ),
];

DeckTemplate? deckTemplateById(String id) {
  for (final template in deckTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

