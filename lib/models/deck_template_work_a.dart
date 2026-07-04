part of 'deck_template.dart';

// ── Werkdeck-builders (deel 1) ───────────────────────────────────────────────
// Invulbare presentaties voor terugkerende werkprocessen: tabellen die tijdens
// het overleg gevuld worden zijn editable, centrale actielijsten zijn
// checklists met voortgang.

List<Slide> _buildPostIncidentReview(String deckTitle) => [
  _title(deckTitle),
  _bullets('Incidentoverzicht', [
    'Wat gebeurde er: …',
    'Wanneer ontdekt en door wie: …',
    'Wanneer verholpen: …',
  ]),
  _timeline('Tijdlijn van het incident', const [
    TimelineEvent(
      marker: 'T+0',
      title: 'Eerste signaal',
      description: 'Melding of alarm binnengekomen.',
    ),
    TimelineEvent(
      marker: 'T+30m',
      title: 'Incident bevestigd',
      description: 'Team opgeschaald.',
    ),
    TimelineEvent(
      marker: 'T+2u',
      title: 'Oorzaak gevonden',
      description: 'Mitigatie gestart.',
    ),
    TimelineEvent(marker: 'T+4u', title: 'Hersteld en geverifieerd'),
  ]),
  _table('Impactanalyse', [
    ['Gebied', 'Impact', 'Duur'],
    ['Gebruikers of klanten', '…', '…'],
    ['Dienstverlening', '…', '…'],
    ['Gegevens', '…', '…'],
  ], editable: true),
  _bullets('Wat ging goed', ['…', '…', '…']),
  _bullets('Wat ging niet goed', ['…', '…', '…']),
  _table('Root causes', [
    ['Oorzaak', 'Categorie', 'Onderbouwing'],
    ['…', 'Techniek / proces / mens', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Verbeteracties', [
    ['Actie', 'Voorkomt', 'Prioriteit'],
    ['…', '…', 'Hoog / midden / laag'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Eigenaars en deadlines', [
    ['Actie', 'Eigenaar', 'Deadline'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Afsluiting / lessons learned', [
    'Belangrijkste les: …',
    'Wat we structureel anders doen: …',
    'Volgende review: …',
  ]),
];

List<Slide> _buildPrivacyIncident(String deckTitle) => [
  _title(deckTitle),
  _bullets('Feitenoverzicht', [
    'Wat is er gebeurd: …',
    'Wanneer ontdekt: …',
    'Hoe ontdekt: …',
  ]),
  _table('Betrokken gegevens', [
    ['Gegevenscategorie', 'Gevoeligheid', 'Omvang'],
    ['…', 'Gewoon / bijzonder', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Betrokkenen en omvang', [
    ['Groep betrokkenen', 'Aantal (schatting)', 'Bijzonderheden'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _checklist('Eerste maatregelen', [
    'Lek gedicht of toegang ingetrokken',
    'Bewijs veiliggesteld (logs, tijdstippen)',
    'FG / privacy officer geïnformeerd',
    'Interne melding geregistreerd',
  ]),
  _table('Risicobeoordeling betrokkenen', [
    ['Risico voor betrokkenen', 'Kans', 'Ernst'],
    ['Identiteitsfraude', '…', '…'],
    ['Reputatieschade', '…', '…'],
    ['Ander nadeel: …', '…', '…'],
  ], editable: true),
  _table('Meldplicht AP: ja of nee', [
    ['Criterium', 'Beoordeling', 'Toelichting'],
    ['Risico voor betrokkenen?', 'Ja / nee', '…'],
    ['Binnen 72 uur haalbaar?', 'Ja / nee', '…'],
    ['Besluit: melden bij AP', 'Ja / nee', 'Besloten door: …'],
  ], editable: true),
  _bullets('Communicatie aan betrokkenen', [
    'Informeren: ja / nee — omdat: …',
    'Kernboodschap: …',
    'Kanaal en moment: …',
  ]),
  _table('Besluitenlog', [
    ['Besluit', 'Door', 'Tijdstip'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _checklist('Actielijst', [
    'Melding AP afronden (indien besloten)',
    'Betrokkenen informeren (indien besloten)',
    'Registratie in datalekregister bijwerken',
    'Evaluatie inplannen',
  ], showProgress: true),
];

List<Slide> _buildDpia(String deckTitle) => [
  _title(deckTitle),
  _bullets('Verwerking en doel', [
    'Verwerking: …',
    'Doel: …',
    'Verantwoordelijke en verwerkers: …',
  ]),
  _bullets('Grondslag en noodzaak', [
    'Grondslag: …',
    'Waarom noodzakelijk en proportioneel: …',
    'Minder ingrijpend alternatief overwogen: …',
  ]),
  _table('Gegevenscategorieën', [
    ['Categorie', 'Bijzonder?', 'Bewaartermijn'],
    ['…', 'Ja / nee', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Betrokkenen', [
    'Groepen betrokkenen: …',
    'Kwetsbare groepen: …',
    'Verwachtingen van betrokkenen: …',
  ]),
  _table('Systemen en leveranciers', [
    ['Systeem of leverancier', 'Rol', 'Verwerkersovereenkomst?'],
    ['…', '…', 'Ja / nee'],
    ['…', '…', '…'],
  ], editable: true),
  _table("Privacyrisico's", [
    ['Risico', 'Kans', 'Impact'],
    ['…', 'Hoog / midden / laag', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Maatregelen', [
    ['Risico', 'Maatregel', 'Eigenaar'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Restrisico en acceptatie', [
    'Restrisico: …',
    'Acceptabel: ja / nee — omdat: …',
    'Voorafgaande raadpleging AP nodig: ja / nee',
  ]),
  _checklist('Besluit en vervolgacties', [
    'DPIA vastgesteld door verantwoordelijke',
    'Maatregelen ingepland met eigenaar en datum',
    'Herbeoordelingsmoment vastgelegd',
  ], showProgress: true),
];

List<Slide> _buildRiskRegister(String deckTitle) => [
  _title(deckTitle),
  _bullets('Scope en methode', [
    'Scope: … (proces, systeem, afdeling)',
    'Methode: … (bijv. kans × impact, 3×3)',
    'Deelnemers: …',
  ]),
  _table('Risico-overzicht', [
    ['Risico', 'Kans', 'Impact', 'Score'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Kans / impact-matrix', [
    ['Kans ↓ · Impact →', 'Laag', 'Midden', 'Hoog'],
    ['Hoog', '…', '…', '…'],
    ['Midden', '…', '…', '…'],
    ['Laag', '…', '…', '…'],
  ], editable: true),
  _table('Bestaande maatregelen', [
    ['Risico', 'Maatregel', 'Werkt aantoonbaar?'],
    ['…', '…', 'Ja / nee'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Aanvullende maatregelen', [
    ['Risico', 'Maatregel', 'Kosten of inspanning'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Restrisico', [
    'Restrisico na maatregelen: …',
    'Binnen risicobereidheid: ja / nee',
    'Geaccepteerd door: …',
  ]),
  _table('Eigenaren en deadlines', [
    ['Maatregel', 'Eigenaar', 'Deadline'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Besluiten gevraagd', [
    'Accepteren van restrisico: …',
    'Budget voor maatregel: …',
    'Prioritering: …',
  ]),
  _checklist('Actielijst', [
    'Maatregelen belegd bij eigenaren',
    'Register bijgewerkt',
    'Volgende herbeoordeling ingepland',
  ], showProgress: true),
];

List<Slide> _buildContinuityTest(String deckTitle) => [
  _title(deckTitle),
  _bullets('Testscenario', [
    'Scenario: … (bijv. uitval datacenter, ransomware)',
    'Aanname vooraf: …',
    'Testvorm: tabletop / gedeeltelijk / volledig',
  ]),
  _bullets('Doelen en succescriteria', [
    'Doel van de test: …',
    'Succescriterium 1: …',
    'Succescriterium 2: …',
  ]),
  _table('Kritieke processen', [
    ['Proces', 'Prioriteit', 'Afhankelijk van'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('RTO / RPO-overzicht', [
    ['Proces of systeem', 'RTO', 'RPO', 'Gehaald?'],
    ['…', '…', '…', 'Ja / nee'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _timeline('Testverloop', const [
    TimelineEvent(
      marker: 'T+0',
      title: 'Start test',
      description: 'Scenario afgekondigd.',
    ),
    TimelineEvent(marker: 'T+…', title: 'Failover gestart'),
    TimelineEvent(marker: 'T+…', title: 'Herstel geverifieerd'),
    TimelineEvent(marker: 'T+…', title: 'Einde test'),
  ]),
  _table('Bevindingen', [
    ['Bevinding', 'Ernst', 'Onderdeel'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Afwijkingen en blokkades', [
    'Afwijking van het draaiboek: …',
    'Blokkade tijdens de test: …',
    'Workaround gebruikt: …',
  ]),
  _checklist('Verbeterpunten', [
    'Draaiboek bijwerken op punt: …',
    'Techniek aanpassen: …',
    'Training of oefening plannen: …',
  ]),
  _checklist('Go / no-go herstelvermogen', [
    'Kritieke processen binnen RTO hersteld',
    'Gegevensverlies binnen RPO gebleven',
    'Draaiboek bruikbaar gebleken',
    'Oordeel: herstelvermogen aangetoond',
  ], showProgress: true),
];

List<Slide> _buildTabletopExercise(String deckTitle) => [
  _title(deckTitle),
  _bullets('Oefendoelen', [
    'Wat oefenen we: …',
    'Wat willen we leren: …',
    'Wat valt buiten de oefening: …',
  ]),
  _bullets('Scenario', [
    'Uitgangssituatie: …',
    'Wat is er (fictief) aan de hand: …',
    'Eerste melding komt binnen via: …',
  ]),
  _table('Rollen en spelregels', [
    ['Rol', 'Wie', 'Taak in de oefening'],
    ['Oefenleider', '…', 'Brengt injects in, bewaakt tijd'],
    ['Deelnemers', '…', 'Handelen alsof het echt is'],
    ['Waarnemer', '…', 'Noteert observaties, grijpt niet in'],
  ]),
  // Injects zijn vertelmomenten; bewust vrije markdown zonder `# `-kop of
  // bullets (anders herclassificeert de parser dit als bulletslide).
  _freeMarkdown('''
### Inject ronde 1

Beschrijf hier de eerste ontwikkeling die het team krijgt voorgelegd.

**Vraag aan het team:** wat doe je nu eerst, en wie informeer je?
'''),
  _table('Besluiten ronde 1', [
    ['Besluit', 'Door wie', 'Overwegingen'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _freeMarkdown('''
### Inject ronde 2

Beschrijf hier de escalatie of wending in het scenario.

**Vraag aan het team:** verandert dit je aanpak — en je communicatie?
'''),
  _table('Besluiten ronde 2', [
    ['Besluit', 'Door wie', 'Overwegingen'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Waarnemingen', [
    ['Waarneming', 'Ging goed / kan beter', 'Toelichting'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _checklist('Evaluatie en verbeteracties', [
    'Oefendoelen behaald beoordeeld',
    'Verbeteracties benoemd met eigenaar',
    'Verslag gedeeld met deelnemers',
    'Volgende oefening ingepland',
  ], showProgress: true),
];

List<Slide> _buildReleaseReadiness(String deckTitle) => [
  _title(deckTitle),
  _bullets('Wijziging samengevat', [
    'Wat verandert er: …',
    'Waarom nu: …',
    'Aangevraagd door: …',
  ]),
  _bullets('Scope en impact', [
    'Systemen en diensten geraakt: …',
    'Gebruikers geraakt: …',
    'Verwachte verstoring: … (duur, moment)',
  ]),
  _table('Teststatus', [
    ['Test', 'Resultaat', 'Bewijs'],
    ['Functionele test', 'Geslaagd / open', '…'],
    ['Regressietest', '…', '…'],
    ['Performancetest', '…', '…'],
  ], editable: true),
  _checklist('Security- en privacycheck', [
    'Security-review uitgevoerd',
    'Geen nieuwe persoonsgegevens — of DPIA gecheckt',
    'Secrets en toegangsrechten gecontroleerd',
    'Kwetsbaarhedenscan schoon',
  ]),
  _table('Implementatieplan', [
    ['Stap', 'Tijd', 'Wie'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Rollbackplan', [
    'Terugdraaien kan tot: …',
    'Rollback-stappen: …',
    'Beslismoment go/no-go rollback: …',
  ], listStyle: ListStyle.numbered),
  _bullets('Communicatieplan', [
    'Vooraf informeren: … (wie, wanneer)',
    'Tijdens de wijziging: …',
    'Achteraf bevestigen: …',
  ]),
  _checklist('Go / no-go checklist', [
    'Tests afgerond en akkoord',
    'Rollback beproefd of aannemelijk',
    'Communicatie klaargezet',
    'Beheer geïnformeerd en beschikbaar',
  ], showProgress: true),
  _table('Besluit CAB', [
    ['Besluit', 'Voorwaarden', 'Datum en tijd'],
    ['Go / no-go / uitgesteld', '…', '…'],
  ], editable: true),
];
