part of 'deck_template.dart';

// ── Template builders ────────────────────────────────────────────────────────

List<Slide> _buildEmpty(String deckTitle) => [
  _title(deckTitle),
  _bullets('Agenda', [
    'Opening en aanleiding',
    'Kern van het verhaal',
    'Vervolg en afspraken',
  ]),
];

List<Slide> _buildBriefing(String deckTitle) => [
  _title(deckTitle),
  _bullets('Situatie in het kort', [
    'Wat is er aan de hand?',
    'Sinds wanneer speelt dit?',
    'Wie zijn erbij betrokken?',
  ]),
  _bullets('Belangrijkste feiten', ['Feit 1: …', 'Feit 2: …', 'Feit 3: …']),
  _bullets('Impact', [
    'Voor de organisatie: …',
    'Voor medewerkers of klanten: …',
    'Financieel: …',
  ]),
  _bullets('Besluit of actie gevraagd', [
    'Gevraagd besluit: …',
    'Alternatief: …',
    'Consequentie van uitstel: …',
  ]),
  _bullets('Vervolgstappen', [
    'Stap 1: … (wie, wanneer)',
    'Stap 2: … (wie, wanneer)',
    'Terugkoppeling: …',
  ]),
];

List<Slide> _buildStatus(String deckTitle) => [
  _title(deckTitle),
  _bullets('Samenvatting status', [
    'Algemene status: op koers / aandacht nodig / kritiek',
    'Belangrijkste ontwikkeling sinds de vorige briefing: …',
    'Verwachting voor de komende periode: …',
  ]),
  _cockpit(
    'Statusdashboard',
    const CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.speedometer,
          label: 'Budgetverbruik',
          unit: '%',
          value: 58,
          greenFrom: 0,
          greenTo: 60,
          redFrom: 85,
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
          value: 4.5,
        ),
        CockpitMeterSpec(
          type: CockpitMeterType.voltmeter,
          label: 'Vertrouwen planning',
          unit: '%',
          greenFrom: 75,
          greenTo: 100,
          redFrom: 50,
          value: 80,
        ),
        CockpitMeterSpec(
          type: CockpitMeterType.climbDescent,
          label: 'Trend openstaande punten',
          unit: '',
          min: -10,
          max: 10,
          neutralFrom: -2,
          neutralTo: 2,
          value: 3,
        ),
      ],
    ),
  ),
  _table('Voortgang per werkstroom', [
    ['Werkstroom', 'Status', 'Toelichting'],
    ['Werkstroom A', '🟢 Op koers', 'Loopt volgens planning'],
    ['Werkstroom B', '🟠 Aandacht', 'Wacht op besluit'],
    ['Werkstroom C', '🔴 Kritiek', 'Capaciteit ontbreekt'],
  ]),
  _bullets("Risico's en blokkades", [
    'Risico 1: … (kans: hoog, impact: groot)',
    'Risico 2: … (kans: laag, impact: groot)',
    'Blokkade: … — hulp nodig van …',
  ]),
  _bullets('Besluiten en acties', [
    'Besluit nodig: …',
    'Actie: … (eigenaar, datum)',
    'Actie: … (eigenaar, datum)',
  ]),
];

List<Slide> _buildKickoff(String deckTitle) => [
  _title(deckTitle),
  _bullets('Waarom dit project', [
    'Aanleiding: …',
    'Probleem of kans: …',
    'Wat gebeurt er als we niets doen?',
  ]),
  _bullets('Doel en beoogd resultaat', [
    'Doel: …',
    'Beoogd resultaat: …',
    'Succescriteria: …',
  ]),
  _twoBullets(
    'Scope',
    columnTitle1: 'Binnen scope',
    bullets: ['Onderdeel 1', 'Onderdeel 2', 'Onderdeel 3'],
    columnTitle2: 'Buiten scope',
    bullets2: ['Onderdeel A', 'Onderdeel B'],
  ),
  _table('Stakeholders', [
    ['Stakeholder', 'Rol', 'Belang'],
    ['Naam of afdeling', 'Opdrachtgever', 'Hoog'],
    ['Naam of afdeling', 'Gebruiker', 'Midden'],
    ['Naam of afdeling', 'Leverancier', 'Midden'],
  ]),
  _timeline('Tijdlijn en mijlpalen', const [
    TimelineEvent(
      marker: 'Q1',
      title: 'Start',
      description: 'Kick-off en plan van aanpak.',
    ),
    TimelineEvent(
      marker: 'Q2',
      title: 'Ontwerp',
      description: 'Ontwerp gereed en akkoord.',
    ),
    TimelineEvent(
      marker: 'Q3',
      title: 'Realisatie',
      description: 'Bouw en tussentijdse demo’s.',
    ),
    TimelineEvent(
      marker: 'Q4',
      title: 'Oplevering',
      description: 'Acceptatie en overdracht.',
    ),
  ]),
  _table('Rollen en verantwoordelijkheden', [
    ['Rol', 'Wie', 'Verantwoordelijk voor'],
    ['Opdrachtgever', 'Naam', 'Budget en besluiten'],
    ['Projectleider', 'Naam', 'Planning en voortgang'],
    ['Teamlid', 'Naam', 'Uitvoering'],
  ]),
  _checklist('Eerste acties', [
    'Projectteam compleet maken',
    'Kick-off plannen met stakeholders',
    'Plan van aanpak uitwerken',
  ]),
];

List<Slide> _buildCommunication(String deckTitle) => [
  _title(deckTitle),
  _bullets('Aanleiding en communicatiedoel', [
    'Aanleiding: …',
    'Doel van de communicatie: …',
    'Gewenst effect bij de ontvanger: …',
  ]),
  _table('Doelgroepen', [
    ['Doelgroep', 'Informatiebehoefte', 'Kanaal'],
    ['Medewerkers', 'Wat betekent dit voor mij?', 'Intranet'],
    ['Klanten', 'Wat merk ik hiervan?', 'Nieuwsbrief'],
    ['Pers', 'Wat is het verhaal?', 'Persbericht'],
  ]),
  _quote(
    'Formuleer hier de kernboodschap in één krachtige zin.',
    'Naam of afzender',
  ),
  _table('Kanalen en middelen', [
    ['Kanaal', 'Middel', 'Wanneer'],
    ['Intranet', 'Bericht + Q&A', 'Dag 1'],
    ['Nieuwsbrief', 'Artikel', 'Week 1'],
    ['Social media', 'Post', 'Na publicatie'],
  ]),
  _timeline('Timing en publicatiemomenten', const [
    TimelineEvent(
      marker: 'Week 1',
      title: 'Interne voorbereiding',
      description: 'Teksten en Q&A gereed.',
    ),
    TimelineEvent(
      marker: 'Week 2',
      title: 'Afstemming',
      description: 'Partners en woordvoering geïnformeerd.',
    ),
    TimelineEvent(marker: 'Week 3', title: 'Publicatie'),
    TimelineEvent(marker: 'Week 4', title: 'Nazorg en monitoring'),
  ]),
  _bullets('Woordvoering en afstemming', [
    'Woordvoerder: …',
    'Afstemming met: …',
    'Q&A voorbereid: ja / nee',
  ]),
  _bullets("Gevoeligheden en risico's", [
    'Gevoeligheid: …',
    'Mogelijke reactie: …',
    'Handelingsperspectief: …',
  ]),
  _bullets('Besluiten nodig', [
    'Akkoord op de kernboodschap',
    'Akkoord op de timing',
    'Akkoord op de woordvoeringslijn',
  ]),
];

List<Slide> _buildProjectTimeline(String deckTitle) => [
  _title(deckTitle),
  _bullets('Projectdoel', [
    'Doel: …',
    'Opdrachtgever: …',
    'Beoogde einddatum: …',
  ]),
  _bullets('Fases van het project', [
    'Voorbereiding',
    'Ontwerp',
    'Realisatie',
    'Test en acceptatie',
    'Livegang en nazorg',
  ], listStyle: ListStyle.numbered),
  _timeline('Tijdlijn', const [
    TimelineEvent(
      marker: 'Q1',
      title: 'Voorbereiding',
      description: 'Opdracht en team rond.',
    ),
    TimelineEvent(
      marker: 'Q2',
      title: 'Ontwerp',
      description: 'Ontwerp vastgesteld.',
    ),
    TimelineEvent(
      marker: 'Q3',
      title: 'Realisatie',
      description: 'Bouw en tests.',
    ),
    TimelineEvent(
      marker: 'Q4',
      title: 'Livegang',
      description: 'In productie en overdracht.',
    ),
  ]),
  _bullets('Afhankelijkheden', [
    'Afhankelijk van: …',
    'Levering door derden: …',
    'Randvoorwaarde: …',
  ]),
  _table('Mijlpalen', [
    ['Mijlpaal', 'Datum', 'Status'],
    ['Plan van aanpak akkoord', '…', 'Gepland'],
    ['Ontwerp vastgesteld', '…', 'Gepland'],
    ['Livegang', '…', 'Gepland'],
  ]),
  _bullets('Beslismomenten', [
    'Go/no-go realisatie: … (datum)',
    'Budgetbesluit: … (datum)',
    'Go-live-besluit: … (datum)',
  ]),
  _bullets('Eerstvolgende stap', ['Wat: …', 'Wie: …', 'Wanneer: …']),
];

List<Slide> _buildRasci(String deckTitle) => [
  _title(deckTitle),
  _bullets('Scope van de afspraken', [
    'Geldt voor: … (systemen, processen, afdelingen)',
    'Periode: …',
    'Buiten scope: …',
  ]),
  // Laat de invulcellen leeg: wie welke rol vervult en wie waar
  // verantwoordelijk voor is, hangt van de organisatie af. Alleen de
  // voorbeeldrollen en -taken staan er als steiger; de toewijzing vult de
  // gebruiker zelf in.
  _table('Rollenoverzicht', [
    ['Rol', 'Wie', 'Organisatieonderdeel'],
    ['CISO', '…', '…'],
    ['Proceseigenaar', '…', '…'],
    ['IT-beheer', '…', '…'],
  ], editable: true),
  _table('RASCI-matrix', [
    ['Taak', 'R', 'A', 'S', 'C', 'I'],
    ['Beleid vaststellen', '…', '…', '…', '…', '…'],
    ['Incidentrespons', '…', '…', '…', '…', '…'],
    ['Toegangsbeheer', '…', '…', '…', '…', '…'],
  ], editable: true),
  _table('Taken, verantwoordelijkheden en bevoegdheden', [
    ['Taak', 'Verantwoordelijk', 'Bevoegd tot'],
    ['Risicoanalyse uitvoeren', '…', '…'],
    ['Wijzigingen doorvoeren', '…', '…'],
    ['Uitzonderingen toestaan', '…', '…'],
  ], editable: true),
  _bullets('Escalatie en besluitvorming', [
    'Eerste escalatielijn: …',
    'Tweede escalatielijn: …',
    'Maximale doorlooptijd van een besluit: …',
  ]),
  _bullets('Openstaande afspraken', [
    'Nog te beleggen taak: …',
    'Nog te bevestigen rol: …',
    'Volgend overleg: …',
  ]),
  _table('Actielijst', [
    ['Actie', 'Eigenaar', 'Deadline'],
    ['Matrix bevestigen in het MT', 'Naam', '…'],
    ['Rolbeschrijvingen publiceren', 'Naam', '…'],
  ]),
];

List<Slide> _buildSecurityTasks(String deckTitle) => [
  _title(deckTitle),
  _bullets('Doel van het takenplan', [
    'Aanleiding: … (audit, incident, nieuw beleid)',
    'Doel: …',
    'Periode: …',
  ]),
  _table('Taakoverzicht', [
    ['Taak', 'Omschrijving', 'Norm of eis'],
    ['Toegangsrechten herzien', 'Periodieke schoning van accounts', '…'],
    ['Logging inrichten', 'Centrale logopslag en alerting', '…'],
    ['Awareness-sessie', 'Training voor alle medewerkers', '…'],
  ]),
  _bullets('Prioriteiten', [
    'Kritieke kwetsbaarheden verhelpen',
    'Toegangsrechten herzien',
    'Logging en monitoring inrichten',
  ], listStyle: ListStyle.numbered),
  _table('Eigenaren per taak', [
    ['Taak', 'Eigenaar', 'Plaatsvervanger'],
    ['Toegangsrechten herzien', 'Naam', 'Naam'],
    ['Logging inrichten', 'Naam', 'Naam'],
    ['Awareness-sessie', 'Naam', 'Naam'],
  ]),
  _table('Status per taak', [
    ['Taak', 'Status', 'Gereed op'],
    ['Toegangsrechten herzien', '🟢 Loopt', '…'],
    ['Logging inrichten', '🟠 Nog starten', '…'],
    ['Awareness-sessie', '🟢 Gepland', '…'],
  ]),
  _bullets('Benodigde bewijsstukken', [
    'Beleidsdocument: …',
    'Configuratie-export of screenshot: …',
    'Rapportage of verslag: …',
  ]),
  _checklist('Vervolgacties', [
    'Eigenaren bevestigen de planning',
    'Bewijsstukken verzamelen',
    'Voortgang agenderen in het volgende overleg',
  ]),
];

List<Slide> _buildCertification(String deckTitle) => [
  _title(deckTitle),
  _bullets('Certificeringsdoel en normenkader', [
    'Norm: ISO 27001 / NIS2 / …',
    'Scope van de certificering: …',
    'Beoogde auditdatum: …',
  ]),
  _chart(
    'Voortgang per domein',
    const ChartSpec(
      type: ChartType.bar,
      x: ['Beleid', 'Techniek', 'Processen', 'Mensen'],
      series: [
        ChartSeries(name: 'Gereed (%)', data: [80, 55, 65, 40]),
      ],
      maxBound: 100,
    ),
  ),
  _table('Openstaande controls', [
    ['Control', 'Domein', 'Status'],
    ['Toegangsbeleid', 'Beleid', 'In review'],
    ['Back-uptest', 'Techniek', 'Nog uitvoeren'],
    ['Leveranciersbeoordeling', 'Processen', 'Nog starten'],
  ]),
  _bullets('Bewijslast en documentatie', [
    'Beschikbaar: …',
    'Nog op te stellen: …',
    'Eigenaar van de bewijslast: …',
  ]),
  _bullets("Risico's voor de audit", [
    'Grootste risico: …',
    'Mitigatie: …',
    'Restrisico geaccepteerd door: …',
  ]),
  _timeline('Auditplanning', const [
    TimelineEvent(
      marker: 'Maand 1',
      title: 'Interne audit',
      description: 'Zelfbeoordeling en bevindingen.',
    ),
    TimelineEvent(
      marker: 'Maand 2',
      title: 'Herstelacties',
      description: 'Openstaande punten wegwerken.',
    ),
    TimelineEvent(marker: 'Maand 3', title: 'Fase 1-audit'),
    TimelineEvent(marker: 'Maand 4', title: 'Fase 2-audit'),
  ]),
  _bullets('Besluiten en hulpvragen', [
    'Besluit nodig over: …',
    'Extra capaciteit nodig voor: …',
    'Hulpvraag aan de organisatie: …',
  ]),
];

List<Slide> _buildTraining(String deckTitle) => [
  _title(deckTitle),
  _bullets('Leerdoelen', [
    'Na deze sessie weet je: …',
    'Na deze sessie kun je: …',
    'Na deze sessie herken je: …',
  ]),
  _bullets('Waarom dit onderwerp belangrijk is', [
    'Wat er misgaat zonder deze kennis: …',
    'Wat het jou oplevert: …',
    'Praktijkvoorbeeld: …',
  ]),
  _bullets('Kernconcepten', [
    'Concept 1: korte uitleg',
    'Concept 2: korte uitleg',
    'Concept 3: korte uitleg',
  ]),
  // Bewust zonder `# `-kop of bullets: die zou de parser als bulletslide
  // classificeren, terwijl dit vrije markdown moet blijven.
  _freeMarkdown('''
### Voorbeeld of casus

Beschrijf hier een herkenbare situatie uit de praktijk.

**Wat gebeurde er?** …

**Wat ging er mis — of juist goed?** …

**Wat leren we hiervan?** …
'''),
  _bullets('Oefening of discussie', [
    'Opdracht: …',
    'Werkvorm: tweetallen / groepjes',
    'Tijd: 10 minuten',
  ]),
  _question(
    'Quizvraag',
    const QuestionSpec(
      prompt: 'Wat is de juiste keuze?',
      answers: [
        QuestionAnswer(text: 'Het juiste antwoord', correct: true),
        QuestionAnswer(text: 'Een fout antwoord'),
        QuestionAnswer(text: 'Nog een fout antwoord'),
        QuestionAnswer(text: 'En nog een fout antwoord'),
      ],
    ),
  ),
  _bullets('Samenvatting', [
    'Belangrijkste inzicht 1: …',
    'Belangrijkste inzicht 2: …',
    'Meer weten? …',
  ]),
];

List<Slide> _buildReport(String deckTitle) => [
  _title(deckTitle),
  _bullets('Managementsamenvatting', [
    'Belangrijkste conclusie: …',
    'Grootste risico of afwijking: …',
    'Gevraagde actie: …',
  ]),
  // Kerncijfers mét de stand van de vorige rapportage ernaast. Een rapportage
  // die terugkomt leidt met wat er veranderde; het getal zelf is context. De
  // voorbeelden tonen bewust alle drie de uitkomsten — vooruit, achteruit en
  // ongewijzigd — zodat zichtbaar is wat de richtingkeuze doet.
  _scorecard('Kerncijfers', const [
    ScorecardEntry(
      label: 'Doelrealisatie',
      value: 72,
      previous: 65,
      unit: '%',
      polarity: ScorecardPolarity.higherBetter,
    ),
    ScorecardEntry(
      label: 'Openstaande punten',
      value: 18,
      previous: 12,
      polarity: ScorecardPolarity.lowerBetter,
    ),
    ScorecardEntry(
      label: 'Risiconiveau',
      value: 3.5,
      previous: 4.2,
      unit: '/10',
      polarity: ScorecardPolarity.lowerBetter,
    ),
    ScorecardEntry(
      label: 'Doorlooptijd',
      value: 21,
      previous: 21,
      unit: 'dagen',
      polarity: ScorecardPolarity.lowerBetter,
    ),
  ]),
  _chart(
    'Trendgrafiek',
    const ChartSpec(
      type: ChartType.line,
      x: ['Jan', 'Feb', 'Mrt', 'Apr', 'Mei', 'Jun'],
      series: [
        ChartSeries(name: 'Dit jaar', data: [12, 14, 13, 17, 19, 22]),
        ChartSeries(name: 'Vorig jaar', data: [10, 11, 13, 14, 15, 16]),
      ],
    ),
  ),
  _bullets('Analyse en duiding', [
    'Wat valt op in de cijfers: …',
    'Verklaring: …',
    'Wat betekent dit voor het doel: …',
  ]),
  _bullets("Risico's en afwijkingen", [
    'Afwijking: … (oorzaak, omvang)',
    'Risico voor de komende periode: …',
    'Beheersmaatregel: …',
  ]),
  // Eigenaar en deadline staan in eigen kolommen in plaats van tussen haakjes
  // in de tekst. Dezelfde kolommen als de actielijst-preset van de tabeleditor,
  // zodat sjabloon en preset dezelfde taal spreken. De deadlines blijven leeg:
  // een sjabloon met ingebakken datums veroudert, en een lege deadline is
  // meestal precies wat er in de vergadering moet worden afgesproken.
  _table('Acties en besluiten', const [
    ['Actie', 'Eigenaar', 'Deadline', 'Status'],
    ['Waarover we een besluit vragen: …', '…', '', 'Open'],
    ['Wat loopt en bij wie: …', '…', '', 'Loopt'],
    ['Wat vastloopt en aandacht nodig heeft: …', '…', '', 'Open'],
  ]),
];

List<Slide> _buildResearch(String deckTitle) => [
  _title(deckTitle),
  _bullets('Onderzoeksvraag', [
    'Hoofdvraag: …',
    'Deelvraag 1: …',
    'Deelvraag 2: …',
  ]),
  _bullets('Methode en bronnen', [
    'Methode: documentanalyse / interviews / data-analyse',
    'Bronnen: …',
    'Onderzoeksperiode: …',
  ]),
  _timeline('Tijdlijn van bevindingen', const [
    TimelineEvent(
      marker: 'Jan',
      title: 'Eerste signaal',
      description: 'Aanleiding voor het onderzoek.',
    ),
    TimelineEvent(
      marker: 'Mrt',
      title: 'Patroon zichtbaar',
      description: 'Meerdere bronnen wijzen dezelfde kant op.',
    ),
    TimelineEvent(
      marker: 'Mei',
      title: 'Bevestiging',
      description: 'Kernbevinding gestaafd met documenten.',
    ),
    TimelineEvent(marker: 'Jun', title: 'Conclusie'),
  ]),
  _bullets('Belangrijkste observaties', [
    'Observatie 1: …',
    'Observatie 2: …',
    'Observatie 3: …',
  ]),
  // Bewust zonder `# `-kop, bullets of blockquote: die zouden de parser dit
  // als bullet- of quoteslide laten classificeren.
  _freeMarkdown('''
### Bewijs en voorbeeldmateriaal

*„Citaat of passage uit het bronmateriaal.”*

**Bron:** … (document, datum)

**Context:** …

**Wat dit aantoont:** …
'''),
  _bullets('Conclusies', [
    'Antwoord op de hoofdvraag: …',
    'Belangrijkste onderbouwing: …',
    'Wat we niet konden vaststellen: …',
  ]),
  _bullets('Aanbevelingen', [
    'Aanbeveling 1: …',
    'Aanbeveling 2: …',
    'Aanbeveling 3: …',
  ], listStyle: ListStyle.numbered),
];

List<Slide> _buildTechnical(String deckTitle) => [
  _title(deckTitle),
  _bullets('Context en doel', [
    'Waar dit onderdeel voor dient: …',
    'Voor wie deze uitleg is: …',
    'Wat je na afloop begrijpt: …',
  ]),
  // Bewust een `###`-kop: een `# `-kop zou de parser als bulletslide-titel
  // lezen in plaats van als vrije markdown.
  _freeMarkdown('''
### Architectuuroverzicht

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```
'''),
  _table('Componenten en verantwoordelijkheden', [
    ['Component', 'Verantwoordelijkheid', 'Eigenaar'],
    ['Client', 'Presentatie en invoer', 'Team A'],
    ['API', 'Validatie en routering', 'Team B'],
    ['Service', 'Bedrijfslogica', 'Team B'],
    ['Database', 'Opslag', 'Team C'],
  ]),
  _bullets('Datastroom of procesflow', [
    'De gebruiker doet een aanvraag',
    'De API valideert en routeert',
    'De service verwerkt en slaat op',
    'Het resultaat gaat terug naar de gebruiker',
  ], listStyle: ListStyle.numbered),
  _code('Codevoorbeeld', 'dart', '''
/// Vervang dit voorbeeld door de code die je wilt toelichten.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
'''),
  _bullets("Risico's en trade-offs", [
    'Gekozen oplossing: … — omdat: …',
    'Afgevallen alternatief: … — omdat: …',
    'Bekend risico: …',
  ]),
  _checklist('Implementatiechecklist', [
    'Ontwerp besproken met het team',
    'Tests geschreven',
    'Documentatie bijgewerkt',
    'Monitoring ingericht',
  ]),
];

List<Slide> _buildQuiz(String deckTitle) => [
  _title(deckTitle),
  _bullets('Uitleg van de quiz', [
    'Drie vragen, drie vraagvormen',
    'Antwoord eerst zelf, dan bespreken we het samen',
    'Fout antwoord? Daar leren we juist van',
  ]),
  _question(
    'Vraag 1: meerkeuze',
    const QuestionSpec(
      prompt: 'Vervang dit door je eigen meerkeuzevraag.',
      answers: [
        QuestionAnswer(text: 'Het juiste antwoord', correct: true),
        QuestionAnswer(text: 'Een fout antwoord'),
        QuestionAnswer(text: 'Nog een fout antwoord'),
        QuestionAnswer(text: 'En nog een fout antwoord'),
      ],
    ),
  ),
  _bullets('Uitleg bij het antwoord', [
    'Waarom dit het juiste antwoord is: …',
    'Veelgemaakte denkfout: …',
  ]),
  _question(
    'Vraag 2: waar of onwaar',
    const QuestionSpec(
      kind: QuestionKind.trueFalse,
      prompt: 'Vervang dit door een stelling die waar of onwaar is.',
      statementIsTrue: true,
    ),
  ),
  _question(
    'Vraag 3: meerdere juiste antwoorden',
    const QuestionSpec(
      kind: QuestionKind.multipleCorrect,
      prompt: 'Vervang dit door een vraag met meerdere juiste antwoorden.',
      answers: [
        QuestionAnswer(text: 'Juist antwoord 1', correct: true),
        QuestionAnswer(text: 'Juist antwoord 2', correct: true),
        QuestionAnswer(text: 'Fout antwoord 1'),
        QuestionAnswer(text: 'Fout antwoord 2'),
      ],
    ),
  ),
  _bullets('Reflectie en nabespreking', [
    'Welke vraag was het lastigst — en waarom?',
    'Wat neem je hiervan mee?',
  ]),
  _section('Afsluiting'),
];
