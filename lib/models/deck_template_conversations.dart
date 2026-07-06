part of 'deck_template.dart';

// ── Gesprekssjablonen: je voorbereiden op een lastig of belangrijk gesprek ───
// Drie families: werkgesprekken, lastige persoonlijke gesprekken en
// commerciële/overtuigende gesprekken. De echt lastige, emotioneel geladen
// gesprekken (conflict, kritiek, slecht nieuws, grenzen, relatie, plus de
// zwaardere werkgesprekken) weven de methode uit *Crucial Conversations* van
// Patterson, Grenny, McMillan & Switzler erdoorheen; de commerciële en
// sollicitatiesjablonen gebruiken een scenario-eigen kader (STAR, SPIN,
// BATNA/ZOPA). Overal geldt: de voorbereidings- en anticipatietabellen zijn
// live invulbaar en de afsprakenlijst is een checklist met voortgang, zodat je
// het sjabloon vóór én tijdens het gesprek kunt gebruiken.

/// Titelpagina met een contextregel (met wie, wanneer, inzet) als subtitel.
Slide _conversationTitle(String deckTitle, String subtitle) => Slide.create(
  SlideType.title,
).copyWith(title: deckTitle, subtitle: subtitle);

/// De gedeelde ruggengraat van de *Crucial Conversations*-methode. Deze
/// theorieslides staan tussen de scenario-eigen voorbereiding en de afspraken,
/// zodat elk lastig-gesprek-sjabloon dezelfde aanpak deelt en je alleen de
/// invulling per situatie hoeft aan te passen.
List<Slide> _crucialConversationsMethod() => [
  _section('De aanpak: een cruciaal gesprek voeren'),
  _bullets('Begin bij je hart — wat wil ik écht?', [
    'Voor mezelf: welk doel dien ik met dit gesprek?',
    'Voor de ander: wat gun ik hem of haar?',
    'Voor de relatie: hoe wil ik dat we hierna met elkaar omgaan?',
    'Verlies dat doel niet uit het oog zodra het spannend wordt',
  ]),
  _bullets('Scheid de feiten van je verhaal', [
    'Feit: wat is er waarneembaar gebeurd of gezegd?',
    'Verhaal: welke uitleg of aanname heb ik eraan gegeven?',
    'Vraag jezelf af: waarom zou een redelijk mens dit doen?',
    'Vermijd de slachtoffer-, schurk- en machteloosheidsverhalen',
  ]),
  _bullets('Maak het veilig en houd het veilig', [
    'Deel een gemeenschappelijk doel: wat willen we samen bereiken?',
    'Toon oprecht respect, ook als je het oneens bent',
    'Contrasteer bij een misverstand: wat je níét bedoelt, en wat wél',
    'Let op stilte (terugtrekken) of agressie (forceren) als veiligheidssignaal',
  ]),
  _bullets('Deel je pad — STATE', [
    'Deel de feiten: begin neutraal en verifieerbaar',
    'Vertel je verhaal: wat je erover denkt, voorzichtig gebracht',
    'Vraag naar het pad van de ander: nodig hun kijk uit',
    'Praat voorzichtig en moedig tegenspraak aan',
  ]),
  _bullets('Verken het pad van de ander — luister (AMPP)', [
    'Ask: stel een open vraag en meen het',
    'Mirror: benoem wat je ziet ("je lijkt geraakt")',
    'Paraphrase: vat in eigen woorden samen wat je hoort',
    'Prime: opper voorzichtig wat er zou kunnen spelen als het stokt',
  ]),
];

/// Sluit een lastig gesprek af met een invulbare afspraken-checklist. Move to
/// Action: leg vast wie wat doet, wanneer, en hoe je opvolgt.
Slide _crucialConversationsActions(List<String> extra) =>
    _checklist('Naar actie en afspraken', [
      'Beslis samen hoe je beslist (wie beslist, wie adviseert)',
      'Leg vast: wie doet wat, en wanneer',
      'Spreek een moment af om erop terug te komen',
      ...extra,
    ], showProgress: true);

// ── Werkgesprekken ───────────────────────────────────────────────────────────

/// Sollicitatiegesprek — scenario-eigen kader (STAR + voorbereiding).
List<Slide> _buildJobInterview(String deckTitle) => [
  _conversationTitle(
    deckTitle,
    'Functie · Werkgever · Datum · Gesprekspartners',
  ),
  _bullets('Doel en indruk die ik wil achterlaten', [
    'Functie en waarom die bij mij past: …',
    'Drie sterke punten die ik wil laten zien: …',
    'De rode draad in mijn verhaal: …',
  ]),
  _bullets('Wat ik van tevoren uitzoek', [
    'De organisatie: missie, producten, recente ontwikkelingen',
    'De functie: taken, verwachtingen, in wiens team',
    'Mijn gesprekspartners: rol en achtergrond',
    'Praktisch: locatie, tijd, wie ik vraag naar',
  ]),
  _table('Verwachte vragen en mijn STAR-antwoord', [
    ['Vraag', 'Situatie/Taak', 'Actie', 'Resultaat'],
    ['Vertel eens over jezelf', '…', '…', '…'],
    ['Grootste uitdaging tot nu toe', '…', '…', '…'],
    ['Waarom deze functie', '…', '…', '…'],
    ['Een fout en wat je leerde', '…', '…', '…'],
  ], editable: true),
  _table('Vragen die ik zelf stel', [
    ['Vraag', 'Waarom dit voor mij belangrijk is'],
    ['…', '…'],
    ['…', '…'],
    ['…', '…'],
  ], editable: true),
  _twoBullets(
    'Sterke punten en aandachtspunten',
    columnTitle1: 'Waar ik sterk in ben',
    bullets: ['…', '…', '…'],
    columnTitle2: 'Waar ik eerlijk over ben',
    bullets2: ['…', '…', '…'],
  ),
  _bullets('Arbeidsvoorwaarden — als het ter sprake komt', [
    'Salarisindicatie en ruimte: …',
    'Uren, thuiswerken en reistijd: …',
    'Ontwikkeling en doorgroei: …',
  ]),
  _checklist('Voorbereiding en opvolging', [
    'Verhaal en voorbeelden geoefend',
    'Vragen voor de werkgever klaar',
    'Kleding, route en documenten geregeld',
    'Na afloop: bedankje sturen en reflecteren',
  ], showProgress: true),
];

/// Functioneringsgesprek — cruciaal gesprek.
List<Slide> _buildPerformanceReview(String deckTitle) => [
  _conversationTitle(deckTitle, 'Met wie · Periode · Datum'),
  _bullets('Wat ik uit dit gesprek wil halen', [
    'Voor mezelf: erkenning, duidelijkheid, ontwikkeling — …',
    'Voor de ander: begrijpen wat mijn leidinggevende verwacht',
    'Voor de samenwerking: hoe we het komende jaar samen optrekken',
  ]),
  _table('Mijn resultaten en voorbeelden', [
    ['Doel of taak', 'Wat ik heb bereikt', 'Bewijs of voorbeeld'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  ..._crucialConversationsMethod(),
  _table('Feiten versus mijn interpretatie', [
    ['Wat er feitelijk gebeurde', 'Mijn verhaal erover', 'Wat ik wil checken'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Mijn ontwikkelwensen', [
    'Wat ik wil leren of meer wil doen: …',
    'Welke steun of middelen ik daarvoor nodig heb: …',
    'Wat ik zelf ga oppakken: …',
  ]),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Hoe ik veilig en kalm blijf'],
    ['Kritiek die me raakt', '…'],
    ['Een ander beeld dan het mijne', '…'],
    ['Geen ruimte voor mijn wens', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Afspraken over doelen en ontwikkeling vastgelegd',
    'Datum voor tussentijdse terugkoppeling geprikt',
  ]),
];

/// Salarisonderhandeling — cruciaal gesprek.
List<Slide> _buildSalaryNegotiation(String deckTitle) => [
  _conversationTitle(deckTitle, 'Met wie · Functie · Datum'),
  _bullets('Wat ik echt wil bereiken', [
    'Voor mezelf: een eerlijke beloning voor mijn waarde — …',
    'Voor de ander: laten zien wat ik het team oplever',
    'Voor de relatie: een goede verstandhouding houden, ook bij een nee',
  ]),
  _table('Mijn onderbouwing', [
    ['Argument', 'Bewijs of voorbeeld', 'Waarde voor de organisatie'],
    ['Resultaten dit jaar', '…', '…'],
    ['Extra taken of rollen', '…', '…'],
    ['Markt en benchmark', '…', '…'],
  ], editable: true),
  _bullets('Mijn bandbreedte', [
    'Streefbedrag (ambitieus, realistisch): …',
    'Streefdoel waar ik tevreden mee ben: …',
    'Ondergrens en mijn alternatief als het niet lukt: …',
    'Naast salaris bespreekbaar: opleiding, uren, bonus, titel',
  ]),
  ..._crucialConversationsMethod(),
  _table('Anticiperen op reacties', [
    ['Mogelijk bezwaar', 'Mijn kalme reactie'],
    ['"Daar is nu geen budget voor"', '…'],
    ['"Je zit al goed voor je functie"', '…'],
    ['"We kijken volgend jaar opnieuw"', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Concreet voorstel en tegenvoorstel benoemd',
    'Afgesproken wanneer en hoe het besluit valt',
  ]),
];

/// Meer verantwoordelijkheid vragen — cruciaal gesprek.
List<Slide> _buildMoreResponsibility(String deckTitle) => [
  _conversationTitle(deckTitle, 'Met wie · Huidige rol · Datum'),
  _bullets('Wat ik wil bereiken', [
    'Voor mezelf: de verantwoordelijkheid of rol die ik ambieer — …',
    'Voor de ander: laten zien dat het de afdeling helpt',
    'Voor de relatie: mijn leidinggevende meenemen, niet overvallen',
  ]),
  _table('Wat ik nu al waarmaak', [
    [
      'Taak of resultaat',
      'Bewijs',
      'Waarom dit past bij meer verantwoordelijkheid',
    ],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('Wat ik concreet vraag', [
    'De verantwoordelijkheid of rol: …',
    'Wat er dan verandert aan mijn takenpakket: …',
    'Wat ik daarvoor nodig heb (tijd, mandaat, begeleiding): …',
  ]),
  ..._crucialConversationsMethod(),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Mijn kalme reactie'],
    ['"Je bent er nog niet klaar voor"', '…'],
    ['"Daar is nu geen ruimte voor"', '…'],
    ['"Dat ligt gevoelig in het team"', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Afgesproken welke stap ik als eerste mag zetten',
    'Moment geprikt om de voortgang te bespreken',
  ]),
];

/// Een probleem op de werkvloer aankaarten — cruciaal gesprek.
List<Slide> _buildRaiseWorkplaceIssue(String deckTitle) => [
  _conversationTitle(deckTitle, 'Met wie · Onderwerp · Datum'),
  _bullets('Wat ik wil bereiken', [
    'Voor mezelf: het probleem bespreekbaar maken zonder te beschuldigen',
    'Voor de ander: samen naar een oplossing zoeken',
    'Voor de relatie: de werksfeer verbeteren, niet beschadigen',
  ]),
  _bullets('Waar het over gaat', [
    'Het probleem in één zin: …',
    'Wanneer en hoe vaak het speelt: …',
    'Het effect op het werk of het team: …',
  ]),
  ..._crucialConversationsMethod(),
  _table('Feiten versus mijn interpretatie', [
    ['Wat er feitelijk gebeurde', 'Mijn verhaal erover', 'Wat ik wil checken'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Hoe ik het veilig houd'],
    ['Ontkenning of afweer', '…'],
    ['Boosheid of verwijt', '…'],
    ['"Zo is het nu eenmaal"', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Samen een eerste stap of proef afgesproken',
    'Bepaald wie eventueel nog betrokken moet worden',
  ]),
];

// ── Lastige persoonlijke gesprekken ──────────────────────────────────────────

/// Een conflict uitpraten — cruciaal gesprek.
List<Slide> _buildResolveConflict(String deckTitle) => [
  _conversationTitle(deckTitle, 'Met wie · Waarover · Datum'),
  _bullets('Wat ik echt wil bereiken', [
    'Voor mezelf: gehoord worden en mijn kant vertellen',
    'Voor de ander: hun kant echt begrijpen',
    'Voor de relatie: er samen sterker uitkomen, niet winnen',
  ]),
  _bullets('Waar het conflict over gaat', [
    'De kwestie in één zin: …',
    'Wat het bij mij losmaakt: …',
    'Wat ik vermoed dat het bij de ander losmaakt: …',
  ]),
  ..._crucialConversationsMethod(),
  _table('Feiten versus mijn verhaal', [
    ['Wat er feitelijk gebeurde', 'Mijn verhaal erover', 'Een mildere uitleg'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Hoe ik het veilig houd'],
    ['Verwijten of oude koeien', '…'],
    ['Terugtrekken of dichtklappen', '…'],
    ['Emoties lopen hoog op', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Erkend wat we allebei bijdroegen',
    'Een concrete afspraak voor de volgende keer gemaakt',
  ]),
];

/// Kritiek geven of ontvangen — cruciaal gesprek.
List<Slide> _buildGiveReceiveFeedback(String deckTitle) => [
  _conversationTitle(deckTitle, 'Met wie · Onderwerp · Datum'),
  _bullets('Wat ik wil bereiken', [
    'Voor mezelf: eerlijk zijn zonder de ander te beschadigen',
    'Voor de ander: iets waar hij of zij echt mee verder kan',
    'Voor de relatie: vertrouwen houden of opbouwen',
  ]),
  _twoBullets(
    'Kritiek geven en ontvangen',
    columnTitle1: 'Als ik geef',
    bullets: [
      'Beschrijf gedrag, geen persoon',
      'Feit → effect → verzoek',
      'Op tijd, niet opgespaard',
      'Check hoe het binnenkomt',
    ],
    columnTitle2: 'Als ik ontvang',
    bullets2: [
      'Luister zonder meteen te verdedigen',
      'Vraag door naar een voorbeeld',
      'Bedank voor de openheid',
      'Neem tijd voordat ik reageer',
    ],
  ),
  ..._crucialConversationsMethod(),
  _table('Mijn boodschap voorbereiden', [
    ['Feit (wat ik zag)', 'Effect (wat het deed)', 'Verzoek (wat ik vraag)'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Hoe ik het veilig houd'],
    ['Verdediging of "ja maar"', '…'],
    ['Ontkenning', '…'],
    ['Geraaktheid of tranen', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Gecheckt of de boodschap goed is aangekomen',
    'Afgesproken wat er nu anders gaat',
  ]),
];

/// Slecht nieuws brengen — cruciaal gesprek.
List<Slide> _buildDeliverBadNews(String deckTitle) => [
  _conversationTitle(deckTitle, 'Aan wie · Het nieuws · Datum'),
  _bullets('Wat ik wil bereiken', [
    'Voor mezelf: het duidelijk en met respect brengen',
    'Voor de ander: hem of haar niet in het ongewisse laten',
    'Voor de relatie: menselijk blijven, ook nu',
  ]),
  _bullets('De boodschap helder krijgen', [
    'Het nieuws in één heldere zin: …',
    'De reden, zakelijk en eerlijk: …',
    'Wat wél kan of wat de volgende stap is: …',
    'Wat vaststaat en waar nog ruimte is: …',
  ]),
  ..._crucialConversationsMethod(),
  _bullets('Zo breng ik het', [
    'Kondig kort aan dat het geen makkelijk bericht is',
    'Geef het nieuws direct, draai er niet omheen',
    'Zwijg en geef ruimte voor de reactie',
    'Erken de emotie voordat je naar oplossingen gaat',
  ]),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Hoe ik reageer'],
    ['Boosheid of verwijt', '…'],
    ['Verdriet of stilte', '…'],
    ['Onderhandelen of ontkennen', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Duidelijk gemaakt wat de vervolgstappen zijn',
    'Nazorg of een vervolggesprek aangeboden',
  ]),
];

/// Grenzen stellen — cruciaal gesprek.
List<Slide> _buildSetBoundaries(String deckTitle) => [
  _conversationTitle(deckTitle, 'Tegen wie · Waarover · Datum'),
  _bullets('Wat ik wil bereiken', [
    'Voor mezelf: mijn grens duidelijk en rustig neerzetten',
    'Voor de ander: begrijpelijk maken, niet afwijzen',
    'Voor de relatie: respect houden, ook als ik nee zeg',
  ]),
  _bullets('Mijn grens scherp krijgen', [
    'Wat er precies over gaat: …',
    'Wat voor mij niet (meer) oké is: …',
    'Wat ik wél wil of aanbied: …',
    'Waarom deze grens voor mij belangrijk is: …',
  ]),
  ..._crucialConversationsMethod(),
  _bullets('Zo zeg ik het', [
    'Benoem het gedrag en het effect, kort en concreet',
    'Zeg wat je nodig hebt in de ik-vorm',
    'Blijf vriendelijk maar herhaal je grens als het moet',
    'Bied waar mogelijk een alternatief',
  ]),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Hoe ik bij mijn grens blijf'],
    ['Druk of "doe niet zo moeilijk"', '…'],
    ['Schuldgevoel opwekken', '…'],
    ['Boosheid of afstand', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Mijn grens helder herhaald en bevestigd',
    'Afgesproken wat er verandert en wat ik doe als de grens wéér wordt overschreden',
  ]),
];

/// Een stroef lopende relatie of vriendschap bespreken — cruciaal gesprek.
List<Slide> _buildStrainedRelationship(String deckTitle) => [
  _conversationTitle(deckTitle, 'Met wie · Waarover · Wanneer'),
  _bullets('Wat ik echt wil bereiken', [
    'Voor mezelf: uitspreken wat me dwarszit',
    'Voor de ander: begrijpen hoe hij of zij het beleeft',
    'Voor de relatie: weer dichter bij elkaar komen',
  ]),
  _bullets('Wat er speelt', [
    'Wat er de laatste tijd anders voelt: …',
    'Een concreet moment dat het duidelijk maakte: …',
    'Wat ik mis of nodig heb: …',
  ]),
  ..._crucialConversationsMethod(),
  _table('Feiten versus mijn verhaal', [
    ['Wat er feitelijk gebeurde', 'Mijn verhaal erover', 'Een mildere uitleg'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Anticiperen op reacties', [
    ['Mogelijke reactie', 'Hoe ik het gesprek open houd'],
    ['"Er is toch niks?"', '…'],
    ['Terugtrekken of stilvallen', '…'],
    ['Verwijt of oude pijn', '…'],
  ], editable: true),
  _crucialConversationsActions([
    'Uitgesproken wat we allebei waardevol vinden aan de band',
    'Een concrete manier afgesproken om het weer op te bouwen',
  ]),
];

// ── Commerciële en overtuigende gesprekken ───────────────────────────────────

/// Klantgesprek — scenario-eigen kader (behoefte en waarde).
List<Slide> _buildClientConversation(String deckTitle) => [
  _conversationTitle(deckTitle, 'Klant · Contactpersoon · Doel · Datum'),
  _bullets('Doel van dit gesprek', [
    'Wat ik met dit gesprek wil bereiken: …',
    'Wat de klant eruit moet halen: …',
    'De ideale volgende stap na afloop: …',
  ]),
  _bullets('Wat ik van tevoren uitzoek', [
    'De klant: organisatie, rol, eerdere contacten',
    'Wat er bij hen speelt: uitdagingen, doelen',
    'Onze historie en lopende afspraken',
  ]),
  _table('Behoefteanalyse', [
    ['Vraag die ik stel', 'Wat ik wil weten'],
    ['Waar loopt u tegenaan?', '…'],
    ['Wat zou het oplossen u opleveren?', '…'],
    ['Wie beslist hierover?', '…'],
  ], editable: true),
  _table('Van behoefte naar waarde', [
    ['Behoefte van de klant', 'Wat wij bieden', 'Concrete waarde'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Anticiperen op bezwaren', [
    ['Mogelijk bezwaar', 'Mijn reactie'],
    ['"Te duur"', '…'],
    ['"Geen tijd nu"', '…'],
    ['"We doen het al zelf"', '…'],
  ], editable: true),
  _checklist('Afspraken en opvolging', [
    'Behoefte samengevat en bevestigd',
    'Concrete vervolgstap afgesproken',
    'Wie doet wat en wanneer vastgelegd',
    'Terugkoppeling of offerte toegezegd',
  ], showProgress: true),
];

/// Verkoopgesprek — scenario-eigen kader (SPIN).
List<Slide> _buildSalesConversation(String deckTitle) => [
  _conversationTitle(deckTitle, 'Prospect · Contactpersoon · Aanbod · Datum'),
  _bullets('Doel en aanbod', [
    'Wat ik verkoop en aan wie: …',
    'Het doel van dit gesprek: …',
    'De gewenste uitkomst: order, vervolgafspraak, offerte',
  ]),
  _table('Vragen volgens SPIN', [
    ['Type vraag', 'Mijn vraag', 'Wat ik eruit wil halen'],
    ['Situatie', '…', 'Feiten en context'],
    ['Probleem', '…', 'Waar het pijn doet'],
    ['Implicatie', '…', 'Wat het probleem kost'],
    ['Nut/behoefte', '…', 'Waarde van een oplossing'],
  ], editable: true),
  _table('Van behoefte naar waarde', [
    ['Behoefte', 'Kenmerk van ons aanbod', 'Voordeel voor de klant'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _table('Bezwaren en mijn reactie', [
    ['Bezwaar', 'Erken', 'Weerleg of alternatief'],
    ['Prijs', '…', '…'],
    ['Timing', '…', '…'],
    ['Twijfel over waarde', '…', '…'],
  ], editable: true),
  _bullets('Afsluiten', [
    'Vat de afgesproken waarde samen',
    'Stel een concrete afsluitvraag',
    'Maak de vervolgstap klein en duidelijk',
    'Bevestig de afspraak meteen',
  ]),
  _checklist('Opvolging', [
    'Behoefte en waarde bevestigd',
    'Vervolgstap of order afgesproken',
    'Offerte of bevestiging toegezegd',
    'Datum voor opvolging geprikt',
  ], showProgress: true),
];

/// Onderhandeling met leveranciers — scenario-eigen kader (BATNA/ZOPA).
List<Slide> _buildSupplierNegotiation(String deckTitle) => [
  _conversationTitle(deckTitle, 'Leverancier · Contract · Doel · Datum'),
  _bullets('Doel van de onderhandeling', [
    'Wat ik wil binnenhalen (prijs, voorwaarden, service): …',
    'Waarom dit voor ons belangrijk is: …',
    'De relatie die we willen houden: …',
  ]),
  _bullets('Mijn onderhandelruimte', [
    'Streefresultaat (ambitieus): …',
    'Acceptabel resultaat: …',
    'Ondergrens en mijn alternatief (BATNA): …',
    'Waar de gezamenlijke ruimte waarschijnlijk ligt (ZOPA): …',
  ]),
  _table('Eisen en wensen', [
    ['Punt', 'Must-have of nice-to-have', 'Wat het mij waard is'],
    ['Prijs', '…', '…'],
    ['Levertijd', '…', '…'],
    ['Service en garantie', '…', '…'],
    ['Betalingsvoorwaarden', '…', '…'],
  ], editable: true),
  _table('Onderhandelpunten', [
    ['Punt', 'Openingsbod', 'Streef', 'Ondergrens'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _table('Anticiperen op tactieken', [
    ['Wat de ander kan doen', 'Mijn reactie'],
    ['"Dit is onze laatste prijs"', '…'],
    ['Druk op tijd', '…'],
    ['Koppelen van eisen', '…'],
  ], editable: true),
  _checklist('Afspraken en vastlegging', [
    'Afspraken samengevat en bevestigd',
    'Prijs en voorwaarden vastgelegd',
    'Wie tekent en wanneer bepaald',
    'Vervolg en evaluatiemoment afgesproken',
  ], showProgress: true),
];

/// Een pitch — scenario-eigen kader (probleem-oplossing-bewijs-vraag).
List<Slide> _buildPitch(String deckTitle) => [
  _conversationTitle(deckTitle, 'Voor wie · Wat je vraagt · Tijd · Datum'),
  _bullets('Doel en kernboodschap', [
    'Aan wie pitch ik en waarom zij: …',
    'De kernboodschap in één zin: …',
    'Wat ik concreet van hen vraag: …',
  ]),
  _quote(
    'Als je het niet in één zin kunt uitleggen, snap je het zelf nog niet goed genoeg.',
    'Vuistregel voor een sterke pitch',
  ),
  _bullets('De opbouw', [
    'Haak: een prikkelende opening of voorbeeld',
    'Probleem: welke pijn los je op, voor wie',
    'Oplossing: wat je biedt, in gewone taal',
    'Bewijs: cijfers, voorbeeld of demo',
    'Vraag: de concrete volgende stap',
  ], listStyle: ListStyle.numbered),
  _table('Mijn pitch uitgewerkt', [
    ['Onderdeel', 'Wat ik zeg'],
    ['Haak', '…'],
    ['Probleem', '…'],
    ['Oplossing', '…'],
    ['Bewijs', '…'],
    ['Vraag', '…'],
  ], editable: true),
  _table('Anticiperen op vragen', [
    ['Verwachte vraag', 'Mijn antwoord'],
    ['Wat kost het?', '…'],
    ['Waarom jullie?', '…'],
    ['Wat als het niet werkt?', '…'],
  ], editable: true),
  _checklist('Klaar om te pitchen', [
    'Kernboodschap en vraag scherp',
    'Verhaal binnen de tijd geoefend',
    'Cijfers en voorbeeld paraat',
    'Duidelijke call to action',
  ], showProgress: true),
];

/// Een vergadering waarin je iets voor elkaar wilt krijgen — scenario-eigen
/// kader (doel, stakeholders, besluit).
List<Slide> _buildMeetingToGetBuyIn(String deckTitle) => [
  _conversationTitle(deckTitle, 'Vergadering · Besluit gevraagd · Datum'),
  _bullets('Wat ik voor elkaar wil krijgen', [
    'Het besluit of de steun die ik wil: …',
    'Waarom dit nu nodig is: …',
    'Hoe succes er na afloop uitziet: …',
  ]),
  _table('Stakeholders en belangen', [
    [
      'Wie',
      'Belang of zorg',
      'Waarschijnlijke houding',
      'Wat ik hen wil bieden',
    ],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
    ['…', '…', '…', '…'],
  ], editable: true),
  _bullets('Mijn argumentatie', [
    'Het sterkste argument voorop: …',
    'Onderbouwing met feit of voorbeeld: …',
    'Wat het kost om níéts te doen: …',
  ]),
  _table('Anticiperen op bezwaren', [
    ['Verwacht bezwaar', 'Van wie', 'Mijn reactie'],
    ['…', '…', '…'],
    ['…', '…', '…'],
    ['…', '…', '…'],
  ], editable: true),
  _bullets('De vergadering sturen', [
    'Open met het doel en de gevraagde beslissing',
    'Geef ruimte voor zorgen, maar bewaak de tijd',
    'Vat aan het eind de afspraak hardop samen',
    'Leg vast wie wat doet en wanneer',
  ]),
  _checklist('Besluit en opvolging', [
    'Doel en gevraagd besluit vooraf gedeeld',
    'Belangrijkste stakeholders vooraf gepolst',
    'Besluit genomen en genotuleerd',
    'Acties en eigenaren vastgelegd',
  ], showProgress: true),
];
