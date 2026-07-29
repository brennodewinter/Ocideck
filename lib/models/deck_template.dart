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

  /// True for templates that only make sense with the "Procesverbetering"
  /// module on (PROCESS_IMPROVEMENT.md Phase 0). Hidden until that module is
  /// revealed. Temporary sibling of [requiresInfoSafety] — not a unified
  /// `requiresModule` yet, on purpose (light Phase 0).
  final bool requiresProcesverbetering;

  const DeckTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.requiresInfoSafety = false,
    this.requiresProcesverbetering = false,
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
    id: 'businessCase',
    title: 'Businesscase / investeringsvoorstel',
    description:
        "Aanleiding, opties met kosten en baten, risico's en het gevraagde "
        'besluit.',
    icon: 'businessCase',
  ),
  DeckTemplate(
    id: 'budgetPresentation',
    title: 'Begroting / budgetpresentatie',
    description:
        "Uitgangspunten, posten met vergelijking, keuzeruimte, risico's en "
        'beslispunten.',
    icon: 'budgetPresentation',
  ),
  DeckTemplate(
    id: 'decisionMeeting',
    title: 'Besluitvormend overleg',
    description:
        'Agenda, toelichting per punt, besluitenlijst en acties met eigenaar.',
    icon: 'decisionMeeting',
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
    id: 'threatModeling',
    title: 'Threat modeling-sessie',
    description:
        'Scope, datastromen, vertrouwensgrenzen, dreigingen per '
        'STRIDE-categorie en maatregelen.',
    icon: 'threatModeling',
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
    id: 'sprintReview',
    title: 'Sprint review / demo',
    description: 'Sprintdoel, opgeleverd werk, demo, metrieken en vooruitblik.',
    icon: 'sprintReview',
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
    id: 'conversationPrep',
    title: 'Gesprek voorbereiden',
    description:
        'Doel, de ander, opbouw, vragen en afspraken voor elk gesprek dat je '
        'goed wilt voorbereiden.',
    icon: 'conversationPrep',
  ),
  DeckTemplate(
    id: 'crucialConversation',
    title: 'Cruciaal gesprek voorbereiden',
    description:
        'Hoge belangen en sterke emoties, volgens de aanpak voor cruciale '
        'gesprekken.',
    icon: 'crucialConversation',
  ),
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
  // ── Zorg en medische overdracht ─────────────────────────────────────────────
  DeckTemplate(
    id: 'sbarHandover',
    title: 'SBAR-overdracht',
    description:
        'Draag een patiënt of situatie gestructureerd over: Situatie, '
        'Achtergrond, Beoordeling en Aanbeveling.',
    icon: 'sbarHandover',
  ),
  DeckTemplate(
    id: 'mistHandover',
    title: '(A)MIST traumaoverdracht',
    description:
        'Prehospitale overdracht naar de SEH met leeftijd, mechanisme, '
        'letsels, symptomen en behandeling.',
    icon: 'mistHandover',
  ),
  DeckTemplate(
    id: 'mdtMeeting',
    title: 'Multidisciplinair overleg (MDO)',
    description:
        'Bespreek een casus met alle disciplines: beeld, behandeldoel, '
        'besluiten en afspraken.',
    icon: 'mdtMeeting',
  ),
  DeckTemplate(
    id: 'surgicalChecklist',
    title: 'Chirurgische veiligheidscheck (WHO)',
    description:
        'Sign in, time-out en sign out rond een ingreep volgens de '
        'WHO-checklist.',
    icon: 'surgicalChecklist',
  ),
  DeckTemplate(
    id: 'nursingHandover',
    title: 'Verpleegkundige dienstoverdracht',
    description:
        'Draag de zorg per patiënt over: toestand, aandachtspunten en '
        'openstaande taken.',
    icon: 'nursingHandover',
  ),
  DeckTemplate(
    id: 'familyCareConversation',
    title: 'Familiegesprek zorg en mantelzorg',
    description:
        "Scenario's, wensen, taakverdeling en afspraken voor een zwaar "
        'familiegesprek.',
    icon: 'familyCareConversation',
  ),
  DeckTemplate(
    id: 'socialCaseReview',
    title: 'Casuïstiekbespreking sociaal domein',
    description:
        'Geanonimiseerde casus: leefdomeinen, veiligheid, wettelijk kader en '
        'regie.',
    icon: 'socialCaseReview',
  ),
  // ── Inwerken en HR-levenscyclus ─────────────────────────────────────────────
  DeckTemplate(
    id: 'onboardingPlan',
    title: 'Inwerkplan (30-60-90 dagen)',
    description:
        'Zet verwachtingen, mijlpalen en begeleiding uit over de eerste 30, '
        '60 en 90 dagen.',
    icon: 'onboardingPlan',
  ),
  DeckTemplate(
    id: 'firstDayInduction',
    title: 'Eerste dag / introductie',
    description:
        'Mensen, systemen, huisregels en de veiligheids- en privacybasis voor '
        'een nieuwe medewerker.',
    icon: 'firstDayInduction',
  ),
  DeckTemplate(
    id: 'buddyMentor',
    title: 'Buddy- / mentorafspraak',
    description:
        'Doelen, ritme en checkpoints tussen nieuwkomer en buddy of mentor.',
    icon: 'buddyMentor',
  ),
  DeckTemplate(
    id: 'offboarding',
    title: 'Uitdiensttreding / offboarding',
    description:
        'Kennisoverdracht, intrekken van toegang en een net exitgesprek bij '
        'vertrek.',
    icon: 'offboarding',
  ),
  DeckTemplate(
    id: 'worksCouncilRequest',
    title: 'Adviesaanvraag OR / medezeggenschap',
    description:
        'Voorgenomen besluit, beweegredenen, personele gevolgen en het '
        'adviestraject.',
    icon: 'worksCouncilRequest',
  ),
  // ── Luchtvaart ──────────────────────────────────────────────────────────────
  DeckTemplate(
    id: 'imsafeCheck',
    title: 'IMSAFE fit-to-fly-check',
    description:
        'Persoonlijke go/no-go: ziekte, medicatie, stress, alcohol, '
        'vermoeidheid en gemoed.',
    icon: 'imsafeCheck',
  ),
  DeckTemplate(
    id: 'crewBriefing',
    title: 'Crew- / departurebriefing',
    description:
        'Taakverdeling, bedreigingen en fouten (TEM) en afwijkingen vóór '
        'vertrek met de bemanning.',
    icon: 'crewBriefing',
  ),
  DeckTemplate(
    id: 'occurrenceReport',
    title: 'Voorvalmelding (just culture)',
    description:
        'Meld een voorval feitelijk en zonder schuldvraag: wat, factoren, '
        'risico en verbetering.',
    icon: 'occurrenceReport',
  ),
  // ── Fysieke beveiliging en veiligheid ───────────────────────────────────────
  DeckTemplate(
    id: 'toolboxTalk',
    title: 'Toolbox / LMRA veiligheidscheck',
    description:
        'Taak, gevaren, maatregelen en akkoord vlak voordat het werk begint.',
    icon: 'toolboxTalk',
  ),
  DeckTemplate(
    id: 'eventSafety',
    title: 'Evenement- en crowd-safetybriefing',
    description:
        "Capaciteit, risico's, in- en uitstroom en incidentrollen voor een "
        'evenement.',
    icon: 'eventSafety',
  ),
  DeckTemplate(
    id: 'evacuationDrill',
    title: 'Ontruimings- en BHV-oefening',
    description:
        'Scenario, taken, verzamelplaats, waarnemingen en evaluatie van een '
        'ontruiming.',
    icon: 'evacuationDrill',
  ),
  DeckTemplate(
    id: 'permitToWork',
    title: 'Werkvergunning (permit to work)',
    description:
        'Werk, isolaties, controles en vrijgave voor risicovol werk '
        'vastleggen.',
    icon: 'permitToWork',
  ),
  // ── Hulpdiensten en crisis ──────────────────────────────────────────────────
  DeckTemplate(
    id: 'methaneReport',
    title: 'METHANE grootschalig-incidentmelding',
    description:
        'Eerste melding bij een groot incident: melding, locatie, type, '
        'gevaren, toegang, aantal en diensten.',
    icon: 'methaneReport',
  ),
  DeckTemplate(
    id: 'gripEscalation',
    title: 'GRIP-opschaling',
    description:
        'Bepaal het GRIP-niveau, de crisisstructuur, rollen en op- en '
        'afschalingsbesluiten.',
    icon: 'gripEscalation',
  ),
  DeckTemplate(
    id: 'fireServiceBriefing',
    title: 'Brandweerbriefing (inzet en oefening)',
    description:
        'Object, bereikbaarheid, gevaren, kwadranten, waterwinning en '
        'taakverdeling.',
    icon: 'fireServiceBriefing',
  ),
  DeckTemplate(
    id: 'afterActionReview',
    title: 'Debriefing / after-action review',
    description:
        'Wat was gepland, wat gebeurde er, waarom — en welke afspraken maken '
        'we.',
    icon: 'afterActionReview',
  ),
  // ── Maritiem ────────────────────────────────────────────────────────────────
  DeckTemplate(
    id: 'bridgePassageBriefing',
    title: 'Maritieme passage-/brugbriefing',
    description:
        'Reisplan en brugafspraken (appraisal, planning, execution, '
        'monitoring) met kritieke routepunten.',
    icon: 'bridgePassageBriefing',
  ),
  // ── Publieke sector ─────────────────────────────────────────────────────────
  DeckTemplate(
    id: 'councilProposal',
    title: 'Raads- / collegevoorstel',
    description:
        'Aanleiding, beslispunten, argumenten én kanttekeningen, dekking en '
        'vervolg.',
    icon: 'councilProposal',
  ),
  DeckTemplate(
    id: 'residentsMeeting',
    title: 'Bewonersavond / participatiebijeenkomst',
    description:
        'Wat vaststaat en wat openligt, cijfers, reactiemogelijkheden en '
        'vervolg.',
    icon: 'residentsMeeting',
  ),
  // ── Onderwijs en stage ──────────────────────────────────────────────────────
  DeckTemplate(
    id: 'parentsEvening',
    title: 'Ouderavond / informatieavond',
    description:
        'Jaarprogramma, aanpak, praktische afspraken en hoe ouders kunnen '
        'helpen.',
    icon: 'parentsEvening',
  ),
  DeckTemplate(
    id: 'internshipPresentation',
    title: 'Stagepresentatie',
    description:
        'Bedrijf, opdracht, aanpak, resultaat, leerdoelen en reflectie.',
    icon: 'internshipPresentation',
  ),
  // ── Vereniging ──────────────────────────────────────────────────────────────
  DeckTemplate(
    id: 'membersAssembly',
    title: 'Ledenvergadering (ALV)',
    description:
        'Agenda, jaarverslag, kascommissie, begroting en stemmingen voor '
        'vereniging of VvE.',
    icon: 'membersAssembly',
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
  DeckTemplate(
    id: 'procesverbetering-dmaic',
    title: 'Procesverbetering: DMAIC-project',
    description:
        'DMAIC-skelet met charter, CTQ-boom (Y-01), SIPOC en fase-secties.',
    icon: 'procesverbeteringDmaic',
    requiresProcesverbetering: true,
  ),
];

DeckTemplate? deckTemplateById(String id) {
  for (final template in deckTemplates) {
    if (template.id == id) return template;
  }
  return null;
}
