part of 'deck_template.dart';

// ── Sessiedecks: BOB-crisisoverleg en PPL-vluchtvoorbereiding ────────────────
// Beide zijn bedoeld om live in te vullen: werktafels zijn editable,
// beslislijsten zijn checklists met voortgang.

List<Slide> _buildBobCrisis(String deckTitle) => [
  _title(deckTitle),
  _bullets('Doel en werkwijze van dit overleg', [
    'Doel: gedeeld beeld, gewogen oordeel, expliciete besluiten',
    'Werkwijze: BOB — eerst beeld, dan oordeel, dan besluit',
    'Tijdvak van dit overleg: … tot …',
  ]),
  _table('Rollen en mandaat', [
    ['Rol', 'Wie', 'Mandaat'],
    ['Voorzitter', '…', 'Leidt overleg, bewaakt BOB'],
    ['Logger', '…', 'Vult besluitenlog en actielijst'],
    ['Adviseur(s)', '…', 'Adviseert, besluit niet'],
  ], editable: true),
  _section('Beeldvorming'),
  _table('Actueel situatiebeeld', [
    ['Aspect', 'Wat weten we', 'Bron', 'Tijdstip'],
    ['Wat is er aan de hand', '…', '…', '…'],
    ['Omvang en betrokkenen', '…', '…', '…'],
    ['Verwachte ontwikkeling', '…', '…', '…'],
  ], editable: true),
  _table('Wat weten we nog niet?', [
    ['Informatievraag', 'Wie zoekt uit', 'Wanneer terug'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Impactanalyse', [
    ['Gebied', 'Impact nu', 'Verwachte ontwikkeling'],
    ['Mensen', '…', '…'],
    ['Dienstverlening', '…', '…'],
    ['Reputatie', '…', '…'],
  ], editable: true),
  _table('Stakeholders en communicatiebeeld', [
    ['Stakeholder', 'Huidig beeld of zorg', 'Actie nodig?'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _section('Oordeelsvorming'),
  _bullets("Dilemma's en zorgen", [
    'Dilemma: … versus …',
    'Grootste zorg: …',
    'Waar zijn we het (nog) niet over eens: …',
  ]),
  _table("Opties / scenario's", [
    ['Optie', 'Voordelen', 'Nadelen', "Risico's"],
    ['1. …', '…', '…', '…'],
    ['2. …', '…', '…', '…'],
    ['3. Niets doen', '…', '…', '…'],
  ], editable: true),
  _checklist('Besliscriteria', [
    'Veiligheid van mensen geborgd',
    'Proportioneel ten opzichte van de dreiging',
    'Uitvoerbaar met beschikbare mensen en middelen',
    'Uitlegbaar aan betrokkenen en buitenwereld',
  ]),
  _section('Besluitvorming'),
  _table('Besluitenlog', [
    ['Besluit', 'Door', 'Tijdstip', 'Communiceren?'],
    ['…', '…', '…', 'Ja / nee'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _checklist('Actielijst', [
    'Actie: … (eigenaar, deadline)',
    'Actie: … (eigenaar, deadline)',
    'Actie: … (eigenaar, deadline)',
  ], showProgress: true),
  _table('Communicatiebesluiten', [
    ['Doelgroep', 'Kernboodschap', 'Kanaal', 'Wanneer', 'Woordvoerder'],
    ['…', '…', '…', '…', '…'],
    ['…', '…', '…', '…', '…'],
  ], editable: true),
  _checklist('Herijking / volgende BOB-ronde', [
    'Volgende ronde gepland: … uur',
    'Informatievragen uitgezet',
    'Criteria voor eerder bijeenkomen benoemd',
  ]),
  _bullets('Overdrachtsbeeld', [
    'Situatie in één zin: …',
    'Genomen besluiten: …',
    'Lopende acties: …',
    'Aandachtspunten komende uren: …',
  ]),
];

List<Slide> _buildPplFlightPrep(String deckTitle) => [
  Slide.create(
    SlideType.title,
  ).copyWith(title: deckTitle, subtitle: 'Datum · Callsign · Route · PIC'),
  // Bewust vrije markdown zonder `# `-kop (parser-heuristiek); de
  // waarschuwing moet zichtbaar in het deck staan, niet in de notities.
  _freeMarkdown('''
### Belangrijke waarschuwing

**Controleer altijd actuele AIP/NOTAM, officiële weerinformatie, POH/AFM, lokale procedures en wettelijke minima. Deze template ondersteunt besluitvorming, maar vervangt geen verplichte vluchtvoorbereiding.**
'''),
  _checklist('Go / No-Go Samenvatting', [
    'Pilot fit to fly',
    'Vliegtuig beschikbaar en luchtwaardig',
    'Weer binnen persoonlijke en wettelijke minima',
    'NOTAMs gecontroleerd',
    'Route en luchtruim beoordeeld',
    'Brandstof en reserve akkoord',
    'Alternates gekozen',
    'Externe druk expliciet beoordeeld',
  ], showProgress: true),
  _checklist('Pilot Readiness: IMSAFE', [
    'Illness',
    'Medication',
    'Stress',
    'Alcohol',
    'Fatigue',
    'Emotion / Eating',
  ]),
  _table('PAVE Risicobeeld', [
    ['Onderdeel', 'Risico', 'Mitigatie', 'Besluit'],
    ['Pilot', '…', '…', '…'],
    ['Aircraft', '…', '…', '…'],
    ['enVironment', '…', '…', '…'],
    ['External pressures', '…', '…', '…'],
  ], editable: true),
  _table('Vluchtprofiel', [
    ['Veld', 'Waarde', 'Opmerking'],
    ['Vertrek', '…', '…'],
    ['Bestemming', '…', '…'],
    ['Alternate 1', '…', '…'],
    ['Alternate 2', '…', '…'],
    ['Geplande vertrektijd', '…', '…'],
    ['Endurance', '…', '…'],
    ['Personen aan boord', '…', '…'],
    ['Bijzonderheden', '…', '…'],
  ], editable: true),
  ..._pplPlanningSlides(),
  ..._pplPerformanceSlides(),
  ..._pplBriefingSlides(),
];

/// Route, luchtruim, weer en NOTAMs — het planningsdeel van de
/// PPL-vluchtvoorbereiding.
List<Slide> _pplPlanningSlides() => [
  _table('Route en navigatiepunten', [
    [
      'Leg',
      'Waypoint',
      'Koers',
      'Afstand',
      'Hoogte',
      'Frequentie',
      'ETA',
      'Opmerking',
    ],
    ['1', '…', '…', '…', '…', '…', '…', '…'],
    ['2', '…', '…', '…', '…', '…', '…', '…'],
    ['3', '…', '…', '…', '…', '…', '…', '…'],
  ], editable: true),
  _table('Luchtruim en klaringen', [
    [
      'Segment',
      'Luchtruim/gebied',
      'Ondergrens',
      'Bovengrens',
      'Vereiste actie',
      'Frequentie',
    ],
    ['Departure', '…', '…', '…', '…', '…'],
    ['En-route', '…', '…', '…', '…', '…'],
    ['Destination', '…', '…', '…', '…', '…'],
    ['Alternate', '…', '…', '…', '…', '…'],
  ], editable: true),
  _table('Weerbriefing', [
    [
      'Bron/veld',
      'Wind',
      'Zicht',
      'Wolkenbasis',
      'QNH',
      'Significant weer',
      'Impact',
    ],
    ['Departure METAR/TAF', '…', '…', '…', '…', '…', '…'],
    ['En-route', '…', '…', '…', '…', '…', '…'],
    ['Destination METAR/TAF', '…', '…', '…', '…', '…', '…'],
    ['Alternate', '…', '…', '…', '…', '…', '…'],
    ['Trend / verwachting', '…', '…', '…', '…', '…', '…'],
  ], editable: true),
  _table('NOTAMs en tijdelijke beperkingen', [
    ['Locatie/gebied', 'NOTAM', 'Geldigheid', 'Relevantie', 'Actie'],
    ['…', '…', '…', '…', '…'],
    ['…', '…', '…', '…', '…'],
    ['…', '…', '…', '…', '…'],
  ], editable: true),
];

/// Prestatie, massa & zwaartepunt, brandstof en alternates.
List<Slide> _pplPerformanceSlides() => [
  _table('Start- en landingsprestatie', [
    [
      'Veld/baan',
      'Windcomponent',
      'Temp/QNH',
      'Massa',
      'Benodigd',
      'Beschikbaar',
      'Marge',
    ],
    ['Take-off departure', '…', '…', '…', '…', '…', '…'],
    ['Landing destination', '…', '…', '…', '…', '…', '…'],
    ['Take-off alternate', '…', '…', '…', '…', '…', '…'],
    ['Landing alternate', '…', '…', '…', '…', '…', '…'],
  ], editable: true),
  _table('Weight & Balance', [
    ['Item', 'Gewicht', 'Arm', 'Moment', 'Opmerking'],
    ['Basic empty mass', '…', '…', '…', '…'],
    ['Pilot', '…', '…', '…', '…'],
    ['Passagier(s)', '…', '…', '…', '…'],
    ['Bagage', '…', '…', '…', '…'],
    ['Brandstof', '…', '…', '…', '…'],
    ['Totaal', '…', '…', '…', '…'],
    ['Binnen limieten?', 'Ja / nee', '', '', '…'],
  ], editable: true),
  _table('Brandstofplanning', [
    ['Onderdeel', 'Minuten', 'Liters', 'Opmerking'],
    ['Taxi', '…', '…', '…'],
    ['Trip', '…', '…', '…'],
    ['Alternate', '…', '…', '…'],
    ['Final reserve', '…', '…', '…'],
    ['Contingency', '…', '…', '…'],
    ['Extra', '…', '…', '…'],
    ['Totaal vereist', '…', '…', '…'],
    ['Aan boord', '…', '…', '…'],
    ['Marge', '…', '…', '…'],
  ], editable: true),
  _table('Alternates en uitwijkcriteria', [
    [
      'Alternate',
      'Reden',
      'Weer',
      'Baan',
      'Brandstof',
      'NOTAM/opening',
      'Besluit',
    ],
    ['…', '…', '…', '…', '…', '…', '…'],
    ['…', '…', '…', '…', '…', '…', '…'],
  ], editable: true),
];

/// Threat & error management, briefings en het laatste GO/NO-GO-besluit.
List<Slide> _pplBriefingSlides() => [
  _table('Threat & Error Management', [
    ['Threat', 'Wanneer', 'Mogelijke fout', 'Preventie', 'Herstelactie'],
    ['Lage wolkenbasis', '…', '…', '…', '…'],
    ['Druk luchtruim', '…', '…', '…', '…'],
    ['Passagiersdruk', '…', '…', '…', '…'],
    ['Marginale brandstof', '…', '…', '…', '…'],
    ['Onbekend veld', '…', '…', '…', '…'],
  ], editable: true),
  _checklist('Passagiersbriefing', [
    'Gordels en deuren',
    'Headset en communicatie',
    'Sterile cockpit',
    'Geen bediening aanraken',
    'Misselijkheid of ongemak direct melden',
    'Nooduitgang en evacuatie',
    'Mobiele telefoon / losse spullen',
  ]),
  _checklist('Departure Briefing', [
    'Baan en wind gecontroleerd',
    'Abort point bepaald',
    'Engine failure before take-off besproken',
    'Engine failure after take-off besproken',
    'Eerste koers en hoogte bekend',
    'Noise abatement gecontroleerd',
    'Eerste frequentie ingesteld',
  ]),
  _table('Arrival Briefing', [
    ['Onderdeel', 'Waarde', 'Opmerking'],
    ['ATIS / QNH', '…', '…'],
    ['Baan', '…', '…'],
    ['Circuitrichting', '…', '…'],
    ['Join', '…', '…'],
    ['Obstakels', '…', '…'],
    ['Go-around plan', '…', '…'],
    ['Taxi / parkeren', '…', '…'],
  ], editable: true),
  _checklist('Laatste Besluit', [
    'Plan compleet',
    "Risico's gemitigeerd",
    'Marges voldoende',
    'Alternatief plan bekend',
    'Niet gaan blijft acceptabel',
    'PIC besluit: GO / NO-GO',
  ], showProgress: true),
];
