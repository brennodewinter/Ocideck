part of 'deck_template.dart';

// ── Werkdeck-builders (deel 2) ───────────────────────────────────────────────

List<Slide> _buildSteeringUpdate(String deckTitle) => [
  _title(deckTitle),
  _bullets('Managementsamenvatting', [
    'Status in één zin: …',
    'Belangrijkste ontwikkeling: …',
    'Belangrijkste vraag aan de stuurgroep: …',
  ]),
  _cockpit(
    'Statusdashboard',
    const CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.speedometer,
          label: 'Budgetverbruik',
          unit: '%',
          value: 55,
          greenFrom: 0,
          greenTo: 60,
          redFrom: 85,
        ),
        CockpitMeterSpec(
          type: CockpitMeterType.voltmeter,
          label: 'Vertrouwen planning',
          unit: '%',
          greenFrom: 75,
          greenTo: 100,
          redFrom: 50,
          value: 78,
        ),
        CockpitMeterSpec(
          type: CockpitMeterType.thermometer,
          label: 'Risiconiveau',
          unit: '/10',
          min: 0,
          max: 10,
          greenFrom: 0,
          greenTo: 3,
          redFrom: 7,
          value: 4,
        ),
      ],
    ),
  ),
  _timeline('Planning en mijlpalen', const [
    TimelineEvent(marker: 'Q1', title: 'Mijlpaal 1', description: 'Behaald.'),
    TimelineEvent(marker: 'Q2', title: 'Mijlpaal 2', description: 'Op koers.'),
    TimelineEvent(
      marker: 'Q3',
      title: 'Mijlpaal 3',
      description: 'Aandachtspunt.',
    ),
  ]),
  _table('Budget en resources', [
    ['Post', 'Begroot', 'Besteed', 'Prognose'],
    ['Budget totaal', '…', '…', '…'],
    ['Inzet team (fte)', '…', '…', '…'],
  ]),
  _table("Risico's en issues", [
    ['Risico of issue', 'Status', 'Actie'],
    ['…', 'Nieuw / lopend / gesloten', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Besluiten gevraagd', [
    ['Besluit', 'Toelichting', 'Uitkomst'],
    ['…', '…', 'Akkoord / afgewezen / aangehouden'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Acties vorige keer', [
    ['Actie', 'Eigenaar', 'Status'],
    ['…', '…', 'Afgerond / loopt / vertraagd'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Nieuwe acties', [
    ['Actie', 'Eigenaar', 'Deadline'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Escalaties', [
    'Escalatie: … — gevraagd van de stuurgroep: …',
    'Geen escalaties: bevestigen en vastleggen',
  ]),
];

List<Slide> _buildAuditFollowup(String deckTitle) => [
  _title(deckTitle),
  _bullets('Auditcontext', [
    'Audit: … (norm, scope, periode)',
    'Auditor: …',
    'Rapportdatum: …',
  ]),
  _table('Bevindingenoverzicht', [
    ['Nr.', 'Bevinding', 'Ernst'],
    ['1', '…', 'Hoog / midden / laag'],
    ['2', '…', '…'],
    ['3', '…', '…'],
  ]),
  _table('Bevinding per norm/control', [
    ['Bevinding', 'Norm of control', 'Afwijking'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Ernst en prioriteit', [
    ['Bevinding', 'Ernst', 'Prioriteit opvolging'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Root cause', [
    ['Bevinding', 'Root cause', 'Structureel of incidenteel'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Maatregelen', [
    ['Bevinding', 'Maatregel', 'Eigenaar', 'Deadline'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Bewijsstukken', [
    ['Maatregel', 'Bewijs', 'Beschikbaar?'],
    ['…', '…', 'Ja / nee'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Status opvolging', [
    ['Bevinding', 'Status', 'Toelichting'],
    ['…', 'Open / loopt / gesloten', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Besluiten en hulpvragen', [
    'Besluit nodig over: …',
    'Capaciteit of budget nodig voor: …',
    'Volgende rapportage: …',
  ]),
];

List<Slide> _buildVendorRisk(String deckTitle) => [
  _title(deckTitle),
  _bullets('Leverancier en dienst', [
    'Leverancier: …',
    'Dienst of product: …',
    'Contractvorm en looptijd: …',
  ]),
  _bullets('Afhankelijkheid en kritikaliteit', [
    'Hoe kritiek voor de bedrijfsvoering: …',
    'Uitwijkmogelijkheden: …',
    'Exit-scenario aanwezig: ja / nee',
  ]),
  _table('Verwerkte data', [
    ['Gegevenscategorie', 'Persoonsgegevens?', 'Locatie opslag'],
    ['…', 'Ja / nee', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _checklist('Security-eisen', [
    'Certificering aanwezig (ISO 27001 / SOC 2)',
    'Verwerkersovereenkomst getekend',
    'Incidentmeldproces afgesproken',
    'Toegangsbeheer en encryptie beoordeeld',
  ]),
  _bullets('Contractuele aandachtspunten', [
    'Aansprakelijkheid en SLA: …',
    'Auditrecht: …',
    'Opzegtermijn en exit-afspraken: …',
  ]),
  _table("Risico's", [
    ['Risico', 'Kans', 'Impact'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Mitigerende maatregelen', [
    ['Risico', 'Maatregel', 'Eigenaar'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Besluit: accepteren / aanpassen / afwijzen', [
    ['Besluit', 'Voorwaarden', 'Besloten door'],
    ['Accepteren / aanpassen / afwijzen', '…', '…'],
  ], editable: true),
  _checklist('Actielijst', [
    'Voorwaarden vastgelegd in contract of dossier',
    'Maatregelen belegd bij eigenaren',
    'Herbeoordeling ingepland',
  ], showProgress: true),
];

List<Slide> _buildArchitectureDecision(String deckTitle) => [
  _title(deckTitle),
  _bullets('Context', [
    'Systeem of domein: …',
    'Aanleiding voor dit besluit: …',
    'Betrokkenen: …',
  ]),
  _bullets('Probleemstelling', [
    'Wat moet er besloten worden: …',
    'Waarom nu: …',
    'Wat gebeurt er zonder besluit: …',
  ]),
  _bullets('Randvoorwaarden', [
    'Moet voldoen aan: …',
    'Budget of tijdslimiet: …',
    'Bestaande afspraken of standaarden: …',
  ]),
  _twoBullets(
    'Optie 1: …',
    columnTitle1: 'Voordelen',
    bullets: ['…', '…'],
    columnTitle2: 'Nadelen',
    bullets2: ['…', '…'],
  ),
  _twoBullets(
    'Optie 2: …',
    columnTitle1: 'Voordelen',
    bullets: ['…', '…'],
    columnTitle2: 'Nadelen',
    bullets2: ['…', '…'],
  ),
  _twoBullets(
    'Optie 3: …',
    columnTitle1: 'Voordelen',
    bullets: ['…', '…'],
    columnTitle2: 'Nadelen',
    bullets2: ['…', '…'],
  ),
  _table('Trade-off-matrix', [
    ['Criterium', 'Optie 1', 'Optie 2', 'Optie 3'],
    ['Kosten', '…', '…', '…'],
    ['Complexiteit', '…', '…', '…'],
    ['Toekomstvastheid', '…', '…', '…'],
    ['Risico', '…', '…', '…'],
  ], editable: true),
  _bullets('Gekozen besluit', [
    'Besluit: optie … — omdat: …',
    'Besloten door: …',
    'Datum: …',
  ]),
  _bullets('Gevolgen en open punten', [
    'Consequentie voor bestaande systemen: …',
    'Migratie of overgangsperiode: …',
    'Open punt: …',
  ]),
];

List<Slide> _buildPolicyRollout(String deckTitle) => [
  _title(deckTitle),
  _bullets('Wat verandert er', [
    'Nieuw of gewijzigd beleid: …',
    'Belangrijkste wijziging voor de praktijk: …',
    'Ingangsdatum: …',
  ]),
  _bullets('Waarom dit beleid', [
    'Aanleiding: … (wetgeving, incident, audit)',
    'Wat het oplost of voorkomt: …',
    'Wat er gebeurt zonder: …',
  ]),
  _table('Doelgroepen', [
    ['Doelgroep', 'Wat verandert er voor hen', 'Impact'],
    ['…', '…', 'Groot / beperkt'],
    ['…', '…', '…'],
  ]),
  _timeline('Implementatieplanning', const [
    TimelineEvent(
      marker: 'Week 1',
      title: 'Aankondiging',
      description: 'Beleid gepubliceerd en toegelicht.',
    ),
    TimelineEvent(
      marker: 'Week 3',
      title: 'Training',
      description: 'Sessies per doelgroep.',
    ),
    TimelineEvent(
      marker: 'Week 6',
      title: 'Ingangsdatum',
      description: 'Beleid van kracht.',
    ),
    TimelineEvent(marker: 'Week 12', title: 'Adoptiemeting'),
  ]),
  _table('Communicatie', [
    ['Kanaal', 'Boodschap', 'Wanneer'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ]),
  _bullets('Training en ondersteuning', [
    'Trainingsvorm: …',
    'Hulpmiddelen (handreiking, FAQ): …',
    'Waar kunnen mensen terecht met vragen: …',
  ]),
  _bullets("Risico's en weerstand", [
    'Verwachte weerstand: … — aanpak: …',
    'Risico op omzeilen: … — aanpak: …',
  ]),
  _checklist('Adoptiecheck', [
    'Doelgroepen geïnformeerd',
    'Training afgerond',
    'Naleving gemeten',
    'Bijsturing besproken',
  ]),
  _table('Acties en eigenaars', [
    ['Actie', 'Eigenaar', 'Deadline'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
];

List<Slide> _buildHandover(String deckTitle) => [
  _title(deckTitle),
  _bullets('Scope van de overdracht', [
    'Wat wordt overgedragen: …',
    'Van wie naar wie: …',
    'Per wanneer: …',
  ]),
  _bullets('Huidige status', [
    'Waar staat het werk nu: …',
    'Wat loopt er op dit moment: …',
    'Wat is recent afgerond: …',
  ]),
  _table('Open acties', [
    ['Actie', 'Status', 'Deadline'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table("Bekende risico's", [
    ['Risico', 'Toelichting', 'Wat te doen'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Belangrijke systemen / dossiers', [
    ['Systeem of dossier', 'Waar te vinden', 'Toegang via'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ]),
  _table('Contactpersonen', [
    ['Wie', 'Waarvoor', 'Bereikbaar via'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ]),
  _table('Besluiten en afspraken', [
    ['Besluit of afspraak', 'Met wie', 'Geldig tot'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Eerste stappen voor de ontvanger', [
    'Lees eerst: …',
    'Maak kennis met: …',
    'Pak als eerste op: …',
  ], listStyle: ListStyle.numbered),
  _checklist('Checklist overdracht compleet', [
    'Toegangen geregeld',
    'Dossiers overgedragen',
    'Contacten geïnformeerd over de wissel',
    'Openstaande acties belegd',
  ], showProgress: true),
];

List<Slide> _buildRetrospective(String deckTitle) => [
  _title(deckTitle),
  _bullets('Doel van de retro', [
    'Periode of onderwerp: …',
    'Wat willen we bereiken: …',
    'Afspraken: veilig, eerlijk, geen schuldvraag',
  ]),
  _bullets('Feiten en context', [
    'Wat is er gebeurd (feitelijk): …',
    'Cijfers of gebeurtenissen: …',
    'Wat was anders dan normaal: …',
  ]),
  _bullets('Wat ging goed', ['…', '…', '…']),
  _bullets('Wat kan beter', ['…', '…', '…']),
  _table('Start / stop / continue', [
    ['Start', 'Stop', 'Continue'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Patronen en oorzaken', [
    'Terugkerend patroon: …',
    'Onderliggende oorzaak: …',
  ]),
  _table('Verbeterexperimenten', [
    ['Experiment', 'Verwachting', 'Meetpunt'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _checklist('Actielijst', [
    'Experiment 1 belegd met eigenaar',
    'Experiment 2 belegd met eigenaar',
    'Evaluatiemoment volgende retro',
  ], showProgress: true),
  _bullets('Check-out', [
    'Eén woord per persoon over deze retro',
    'Grootste inzicht: …',
    'Volgende retro: …',
  ]),
];
