part of 'deck_template.dart';

// ── Dienstbriefings: beveiliging, politie en handhaving (BOA) ────────────────
// Bedoeld om vóór of tijdens de dienst live in te vullen: de kerntabellen zijn
// editable, de controle- en besluitlijsten zijn checklists met voortgang.
// Alle drie volgen dezelfde ruggengraat — doel/tijdvak, kernonderwerpen, eigen
// veiligheid, controle vóór de dienst en overdracht/debriefing — met per soort
// dienst eigen accenten.

/// Beveiligingsbriefing: de vijf vaste onderwerpen van de dienstoverdracht,
/// aangevuld met doel/tijdvak, alarmering, een controle-checklist en overdracht.
List<Slide> _buildSecurityGuardBriefing(String deckTitle) => [
  Slide.create(SlideType.title).copyWith(
    title: deckTitle,
    subtitle: 'Datum · Dienst · Object/locatie · Dienstleider',
  ),
  _bullets('Doel en tijdvak van deze briefing', [
    'Doel: iedereen begint de dienst met hetzelfde beeld',
    'Tijdvak van de dienst: … tot …',
    'Object/locatie: …',
    'Dienstleider en bereikbaarheid: …',
  ]),
  _table('Belangrijkste punten actualiteiten en vorige dienst', [
    ['Onderwerp', 'Wat speelt er', 'Opvolging deze dienst'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Aandachtsvestigingen voor de dienst', [
    ['Locatie/onderdeel', 'Aandachtspunt', 'Wat te doen'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Bijzonderheden voor de dag', [
    ['Tijd', 'Bijzonderheid (bezoek, levering, evenement)', 'Actie'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Onderhoudswerkzaamheden pand of locatie', [
    [
      'Locatie',
      'Werkzaamheid',
      'Firma/contact',
      'Tijdvak',
      'Impact op beveiliging',
    ],
    ['…', '…', '…', '…', '…'],
    ['…', '…', '…', '…', '…'],
  ], editable: true),
  _table('Personele bezetting', [
    ['Post/rol', 'Naam', 'Tijdvak', 'Portofoon/bereikbaar'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _bullets('Alarmering en calamiteiten', [
    'Meldkamer en alarmnummer: …',
    'Ontruiming en BHV: verzamelplaats en taken',
    'EHBO en AED: locatie en aangewezen personen',
    'Escalatie- en waarschuwingslijn: wie bel je wanneer',
    'Bommelding of verdacht pakket: handelwijze',
  ]),
  _checklist('Controle vóór aanvang dienst', [
    'Portofoon getest en verbinding in orde',
    'Sleutels en toegangspassen compleet',
    'Camerasysteem en beeldopslag werken',
    'Toegangscontrole en slagbomen gecontroleerd',
    'Rondes en surveillance ingepland',
    'Overdracht van vorige dienst ontvangen en getekend',
  ], showProgress: true),
  _bullets('Overdracht einde dienst', [
    'Bijzonderheden vastgelegd in het dagrapport',
    'Openstaande acties overgedragen aan volgende dienst',
    'Incidenten gemeld en gerapporteerd',
    'Sleutels, portofoon en materiaal overgedragen',
  ]),
];

/// Operationele politiebriefing: informatiegestuurd de straat op, met
/// hotspots/hot times/hot crimes, signaleringen (met gevaarzetting),
/// opdrachten, eigen veiligheid en gebiedsinzet.
List<Slide> _buildPoliceBriefing(String deckTitle) => [
  Slide.create(SlideType.title).copyWith(
    title: deckTitle,
    subtitle: 'Datum · Dienst · Werkgebied · Briefer',
  ),
  _bullets('Doel en kaders van deze briefing', [
    'Doel: informatiegestuurd en veilig de straat op',
    'Tijdvak van de dienst: … tot …',
    'Werkgebied/basisteam: …',
    'Operationeel leider/OvD en bereikbaarheid: …',
  ]),
  _section('Terugblik en actualiteiten'),
  _table('Belangrijkste punten vorige dienst en actualiteiten', [
    ['Onderwerp', 'Wat speelt er', 'Opvolging'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _section('Informatiegestuurd beeld'),
  _table('Hotspots, hot times en hot crimes', [
    [
      'Locatie/gebied',
      'Wanneer (hot times)',
      'Fenomeen (hot crimes)',
      'Opdracht',
    ],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Signaleringen: personen', [
    [
      'Naam/omschrijving',
      'Reden signalering',
      'Gevaarzetting',
      'Actie bij aantreffen',
    ],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Signaleringen: voertuigen en goederen', [
    ['Kenteken/omschrijving', 'Reden', 'Actie bij aantreffen'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _section('Opdrachten en inzet'),
  _table('Prioriteiten en surveillance-opdrachten', [
    ['Opdracht/prioriteit', 'Gebied', 'Wie', 'Beoogd resultaat'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Bijzonderheden: evenementen, acties en bevoegdheden', [
    ['Tijd/locatie', 'Bijzonderheid', 'Kader/bevoegdheid', 'Actie'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Personele bezetting en gebiedsindeling', [
    ['Eenheid/koppel', 'Wie', 'Gebied/wijk', 'Roepnummer'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _bullets('Eigen veiligheid en geweldsdreiging', [
    'Bekende gevaarzetting van personen of locaties: …',
    'Bewapening, uitrusting en beschermingsmiddelen: …',
    'Assistentie en aanrijtijd: hoe en wanneer opschalen',
    'Verbindingen en noodknop gecontroleerd',
    'Samenwerking met partners en meldkamer: …',
  ]),
  _checklist('Controle vóór aanvang dienst', [
    'Verbindingen en portofoon getest',
    'Noodknop en assistentieprocedure helder',
    'Bodycam (BWV) gecontroleerd',
    'Voertuig gecontroleerd en bijgetankt',
    'Uitrusting en beschermingsmiddelen compleet',
    'Ambtsinstructie en bevoegdheden helder',
  ], showProgress: true),
  _bullets('Debriefing einde dienst', [
    'Mutaties en registraties bijgewerkt',
    'Aanhoudingen en bekeuringen verwerkt',
    'Signaleringen bijgewerkt of afgemeld',
    'Bijzonderheden voor de volgende ploeg genoteerd',
    'Geweldsaanwending gemeld en geregistreerd',
  ]),
];

/// Handhavingsbriefing (BOA): incidentgestuurd toezicht rond aandachtslocaties,
/// overlast, evenementen, APV/aanwijzingsgebieden, samenwerking met en
/// opschaling naar politie, en eigen veiligheid bij agressie.
List<Slide> _buildEnforcementBriefing(String deckTitle) => [
  Slide.create(SlideType.title).copyWith(
    title: deckTitle,
    subtitle: 'Datum · Dienst · Werkgebied/wijk · Coördinator',
  ),
  _bullets('Doel en kaders van deze briefing', [
    'Doel: gericht en zichtbaar toezicht in de openbare ruimte',
    'Tijdvak van de dienst: … tot …',
    'Werkgebied: …',
    'Coördinator/OvD en bereikbaarheid: …',
  ]),
  _section('Terugblik en meldingen'),
  _table('Belangrijkste punten vorige dienst en meldingen', [
    ['Onderwerp', 'Wat speelt er (melding/overlast)', 'Opvolging'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _section('Aandachtsgebieden'),
  _table('Aandachtslocaties en overlast', [
    [
      'Locatie',
      'Wanneer',
      'Soort overlast (jeugd, afval, parkeren, horeca)',
      'Opdracht',
    ],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Lopende acties en projecten', [
    ['Actie/project', 'Doel', 'Gebied', 'Wie'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _section('Opdrachten en inzet'),
  _table('Bijzonderheden: evenementen, markten en werkzaamheden', [
    ['Tijd/locatie', 'Bijzonderheid', 'Impact', 'Actie'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Bevoegdheden en juridisch kader', [
    [
      'Onderwerp (APV, aanwijzingsgebied, dwangsom)',
      'Locatie/kader',
      'Wat mag/moet ik',
      'Bijzonderheid',
    ],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Bezetting en gebiedsindeling', [
    ['Koppel/BOA', 'Wie', 'Gebied/wijk', 'Portofoon/bereikbaar'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _bullets('Samenwerking en opschaling', [
    'Afstemming met politie en wijkagent: …',
    'Meldkamer en aanrijtijd assistentie: …',
    'Wanneer politie inschakelen: geweld, aanhouding of buiten bevoegdheid',
    'Wijkpartners en toezichtpartners: …',
  ]),
  _bullets('Eigen veiligheid en agressie', [
    'Bekende risicolocaties en -personen: …',
    'De-escalatie en terugtrekken bij dreiging',
    'Geen optreden buiten bevoegdheid of uitrusting',
    'Verbindingen en noodknop gecontroleerd',
    'Assistentie inroepen en niet alleen doorpakken',
  ]),
  _checklist('Controle vóór aanvang dienst', [
    'Verbindingen en portofoon getest',
    'Bodycam gecontroleerd (indien toegewezen)',
    'Legitimatie en BOA-pas bij je',
    'Uitrusting en beschermingsmiddelen compleet',
    'Bonnenapparaat/handheld werkt',
    'Bevoegdheden en aanwijzingsgebieden helder',
  ], showProgress: true),
  _bullets('Debriefing einde dienst', [
    'Mutaties en bekeuringen verwerkt',
    'Meldingen teruggekoppeld aan melders of partners',
    'Aandachtslocaties bijgewerkt voor de volgende ploeg',
    'Bijzonderheden genoteerd',
    'Agressie- en geweldsincidenten gemeld',
  ]),
];
