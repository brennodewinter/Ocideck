// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De inhoudsopgave van de instellingen: wat er te vinden is, en waar het staat.
// De teksten hieronder zijn exact dezelfde bronstrings als in de tabbladen —
// ze worden door dezelfde l10n-lookup gehaald, zodat een treffer in élke taal
// dezelfde kop aanwijst als er op het scherm staat. Wijzigt een label of een
// sectiekop in een tabblad, dan moet hij hier mee wijzigen; een test bewaakt
// dat de sectiekoppen hier ook echt in de tabbladen voorkomen.
//
// `keywords` zijn de woorden die iemand intypt als hij de officiële term níét
// kent — "youtube" voor online media, "lettergrootte" voor tekstschaal. Zonder
// die synoniemen vindt een zoekveld alleen wat je al wist te noemen.
part of '../settings_dialog.dart';

const kSettingsSearchIndex = <SettingsSearchEntry>[
  // ── Algemeen ──────────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.general,
    labelKey: 'applicationLanguage',
    sectionKey: 'language',
    keywords: ['taal', 'language', 'nederlands', 'engels', 'vertaling'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Verbinding toevoegen',
    section: 'Bestandsverbindingen',
    keywords: [
      'bibliotheek',
      'mappen',
      'afbeeldingen',
      'media',
      'verbinding',
      'volgorde',
      'bron',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Voorbeeld tonen bij openen',
    section: 'Openen',
    keywords: [
      'voorbeeld',
      'preview',
      'openen',
      'zoeken',
      'weergave',
      'document',
      'presentatie',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    labelKey: 'choose',
    sectionKey: 'exportFolderSetting',
    keywords: ['export', 'exportmap', 'opslaan', 'uitvoer', 'pdf'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.general,
    label: 'Tekstgrootte van de interface',
    section: 'Toegankelijkheid',
    keywords: ['lettergrootte', 'zoom', 'groter', 'schaal', 'leesbaarheid'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.general,
    label: 'Waarschuwing bij export',
    section: 'Exportkwaliteit',
    keywords: ['kwaliteit', 'export', 'waarschuwing'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.general,
    label: 'Blokkeer export bij ernstige kwaliteitsproblemen',
    section: 'Exportkwaliteit',
    keywords: ['kwaliteit', 'export', 'blokkeren', 'fouten'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.general,
    label: 'Minimale contrastverhouding',
    section: 'Toegankelijkheid',
    keywords: ['contrast', 'wcag', 'kleurcontrast', 'leesbaarheid'],
  ),

  // ── Uiterlijk van de app ───────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.appearance,
    label: 'Donkere interface',
    section: 'Look-and-feel',
    keywords: [
      'donker',
      'dark mode',
      'nachtmodus',
      'licht',
      'uiterlijk',
      'app',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.appearance,
    label: 'Lettertype interface',
    section: 'Look-and-feel',
    keywords: ['font', 'lettertype', 'typografie'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.appearance,
    label: 'Hoofdkleur en bovenbalk',
    section: 'Look-and-feel',
    keywords: ['kleur', 'thema', 'balk'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.appearance,
    label: 'Knoppen en accenten',
    section: 'Look-and-feel',
    keywords: ['kleur', 'accent', 'knoppen'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.appearance,
    label: 'Schermachtergrond',
    section: 'Look-and-feel',
    keywords: ['kleur', 'achtergrond'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.appearance,
    label: 'Themanaam',
    section: 'Look-and-feel',
    keywords: ['thema', 'naam', 'profiel'],
  ),

  // ── Uiterlijk van dia's ────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Stijlprofiel',
    sectionKey: 'styleProfile',
    keywords: ['profiel', 'stijl', 'huisstijl', 'thema', 'uiterlijk', 'dia'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Profiel exporteren',
    sectionKey: 'styleProfile',
    keywords: ['exporteren', 'downloaden', 'opslaan', 'delen', 'huisstijl'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Profiel importeren',
    sectionKey: 'styleProfile',
    keywords: ['importeren', 'inladen', 'openen', 'huisstijl'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Achtergrond',
    sectionKey: 'settingsColors',
    keywords: ['kleur', 'achtergrond', 'slide'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Accent / bullets',
    sectionKey: 'settingsColors',
    keywords: ['kleur', 'accent', 'opsomming'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Opsommingsteken',
    sectionKey: 'settingsColors',
    keywords: ['bullet', 'stip', 'pootje', 'opsomming'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Syntaxkleuring',
    section: 'Broncode',
    keywords: ['code', 'syntax', 'highlighting', 'programmeren'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Broncode lettertype',
    section: 'Broncode',
    keywords: ['code', 'font', 'monospace'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Afgevinkte tekst doorhalen',
    section: 'Checklist',
    keywords: ['checklist', 'doorhalen', 'afvinken'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Kritiek',
    section: 'Severity (bevindingen)',
    keywords: ['severity', 'bevinding', 'kleur', 'ernst', 'pentest'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Activatieduur',
    section: 'Animatie',
    keywords: ['animatie', 'snelheid', 'duur'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Logo positie',
    section: 'Logo',
    keywords: ['logo', 'positie', 'merk'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Zebrastrepen (om en om)',
    section: 'Tabel',
    keywords: ['tabel', 'zebra', 'strepen', 'randstijl', 'celopvulling'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Footertekst',
    section: 'Footer',
    keywords: ['footer', 'voettekst', 'paginanummer'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Basislettergrootte',
    section: 'Tekst',
    keywords: [
      'lettergrootte',
      'tekstgrootte',
      'punten',
      'document',
      'typografie',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Koptekst',
    section: 'Koptekst',
    keywords: ['header', 'koptekst', 'document'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Paginanummers tonen (rechtsonder)',
    section: 'Footer',
    keywords: ['paginanummer', 'nummering', 'footer'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Standaard laatste slide gebruiken',
    section: 'Laatste slide',
    keywords: ['slotslide', 'afsluiting', 'laatste'],
  ),

  // ── Cockpit (onder Uiterlijk van dia's, ingeklapt) ─────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Cockpit-kleurschema',
    section: 'Cockpit-kleurschema',
    keywords: ['cockpit', 'meter', 'kleur', 'dashboard'],
  ),

  // ── Privacy en classificatie ───────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.privacy,
    label: 'Toestemming intrekken',
    section: 'Toestemming',
    keywords: ['consent', 'toestemming', 'privacy', 'intrekken', 'licentie'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.privacy,
    label: 'Vrijgaveplafond',
    section: 'Classificatie-handhaving',
    keywords: [
      'tlp',
      'classificatie',
      'vrijgave',
      'plafond',
      'export',
      'niveau',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.privacy,
    label: 'Classificatie verplicht',
    section: 'Classificatie-handhaving',
    keywords: ['tlp', 'classificatie', 'verplicht', 'export'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.privacy,
    label: 'Classificatie-watermerk',
    section: 'Classificatie-handhaving',
    keywords: ['tlp', 'classificatie', 'watermerk', 'merk'],
  ),

  // ── Beveiliging ───────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'Waarschuw bij mogelijke persoonsgegevens',
    section: 'Privacycontrole',
    keywords: ['privacy', 'persoonsgegevens', 'bsn', 'avg', 'scanner'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'Online media toestaan',
    section: 'Online media',
    keywords: [
      'video',
      'youtube',
      'vimeo',
      'mp4',
      'online',
      'url',
      'afbeelding',
      'embed',
      'internet',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'CVE opzoeken (online)',
    section: 'CVE opzoeken',
    infoSafetyOnly: true,
    keywords: ['cve', 'kwetsbaarheid', 'lek', 'nvd', 'mitre', 'enisa'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'CVE-mirror (basis-URL)',
    section: 'CVE opzoeken',
    infoSafetyOnly: true,
    keywords: ['cve', 'mirror', 'url', 'server'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'Database ophalen',
    section: 'Lokale CVE-database',
    infoSafetyOnly: true,
    keywords: [
      'cve',
      'offline',
      'lokaal',
      'database',
      'kwetsbaarheid',
      'lek',
      'nvd',
      'downloaden',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'Herstelbestanden nu wissen',
    section: 'Sporen op dit apparaat',
    keywords: ['herstel', 'recovery', 'wissen', 'autosave', 'sporen'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'Recente lijst wissen',
    section: 'Sporen op dit apparaat',
    keywords: [
      'recent',
      'geschiedenis',
      'wissen',
      'sporen',
      'privacy',
      'lijst',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'Zet alles terug naar de begintoestand',
    section: 'Sporen op dit apparaat',
    keywords: [
      'terugzetten',
      'reset',
      'wissen',
      'fabrieksinstellingen',
      'opnieuw',
      'sporen',
    ],
  ),

  // ── AI-assistentie (geen sectiekoppen op desktop) ─────────────────────────
  //
  // De schakelaar staat sinds #731 op Uitbreidingen, en deze ingang wijst
  // daarheen. Bewust géén `aiOnly`: zoeken naar "ai" moet altijd íéts vinden,
  // namelijk de plek waar je hem aanzet. Zou ook deze verborgen zijn, dan gaf
  // de app "geen instelling gevonden" op een functie die ze wél heeft.
  SettingsSearchEntry(
    tab: SettingsSection.modules,
    label: 'AI-assistentie',
    section: 'Uitbreidingen',
    keywords: ['ai', 'assistent', 'llm', 'model', 'inschakelen', 'module'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.ai,
    label: 'AI-backend',
    keywords: ['ai', 'backend', 'ollama', 'cloud', 'server'],
    aiOnly: true,
  ),
  SettingsSearchEntry(
    tab: SettingsSection.ai,
    label: 'Modelnaam',
    keywords: ['ai', 'model'],
    aiOnly: true,
  ),
  SettingsSearchEntry(
    tab: SettingsSection.ai,
    label: 'API-sleutel (optioneel)',
    keywords: ['ai', 'api', 'sleutel', 'key', 'token'],
    aiOnly: true,
  ),

  // ── Opslag ────────────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Servertype',
    section: 'WebDAV-bron',
    keywords: ['nextcloud', 'owncloud', 'webdav', 'servertype', 'soort'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Server-URL',
    section: 'WebDAV-bron',
    keywords: ['nextcloud', 'owncloud', 'webdav', 'server', 'cloud', 'url'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Gebruikersnaam',
    section: 'WebDAV-bron',
    keywords: ['nextcloud', 'webdav', 'gebruiker', 'account'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'App-wachtwoord',
    section: 'WebDAV-bron',
    keywords: ['nextcloud', 'webdav', 'wachtwoord', 'password'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Verbinding testen',
    section: 'WebDAV-bron',
    keywords: ['nextcloud', 'webdav', 'test', 'verbinding'],
  ),

  // ── Opslag · Git-repository ───────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Soort forge',
    section: 'Git-repository',
    keywords: ['git', 'forge', 'forgejo', 'gitea', 'github', 'gitlab'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Server-URL',
    section: 'Git-repository',
    keywords: ['git', 'server', 'url', 'repository'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Eigenaar',
    section: 'Git-repository',
    keywords: ['git', 'eigenaar', 'owner', 'organisatie', 'gebruiker'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Repository',
    section: 'Git-repository',
    keywords: ['git', 'repository', 'repo'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Personal access token',
    section: 'Git-repository',
    keywords: ['git', 'token', 'pat', 'wachtwoord', 'toegang'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.storage,
    label: 'Vertrouwde interne server',
    section: 'Git-repository',
    keywords: ['git', 'intern', 'vertrouwd', 'http', 'ssrf'],
  ),

  // ── Checklists ────────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.checklists,
    infoSafetyOnly: true,
    label: 'Nieuw sjabloon',
    section: 'Eigen checklists',
    keywords: ['checklist', 'sjabloon', 'template'],
  ),

  // ── Uitbreidingen ─────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.modules,
    label: 'Informatieveiligheid',
    section: 'Uitbreidingen',
    keywords: [
      'security',
      'cwe',
      'wstg',
      'miauw',
      'cvss',
      'pentest',
      'module',
      'referentiegegevens',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.modules,
    label: 'Pakket importeren',
    section: 'Uitbreidingen',
    keywords: ['import', 'pakket', 'offline', 'gegevens'],
  ),
  // Wie "webdav" of "git" zoekt terwijl de module uit staat, moet uitkomen
  // waar hij hem aanzet — niet in een opslagtab die die soorten dan niet
  // aanbiedt (#570).
  SettingsSearchEntry(
    tab: SettingsSection.modules,
    label: 'Online opslag',
    section: 'Uitbreidingen',
    keywords: ['webdav', 's3', 'git', 'server', 'online', 'module', 'opslag'],
  ),
  // Wie "openkat" zoekt terwijl de module uit staat, moet uitkomen waar hij
  // hem aanzet — precies zoals bij Online opslag hierboven. Deze ingang wijst
  // daarom naar Uitbreidingen en niet naar Integraties, want dat tabblad
  // bestaat dan nog niet. Het label is de moduletitel; de namen van de
  // afzonderlijke importeurs staan in de zoektermen, zodat "openkat" hier
  // uitkomt zonder dat de kaart per bron een eigen ingang nodig heeft.
  SettingsSearchEntry(
    tab: SettingsSection.modules,
    label: 'Importeren',
    section: 'Uitbreidingen',
    keywords: [
      'openkat',
      'kat',
      'import',
      'importeren',
      'rapportage',
      'scan',
      'module',
      'integratie',
    ],
  ),
  // Wie "dmaic", "sipoc" of "six sigma" zoekt terwijl de module uit staat,
  // moet uitkomen waar hij hem aanzet (PROCESS_IMPROVEMENT.md Phase 0).
  SettingsSearchEntry(
    tab: SettingsSection.modules,
    label: 'Procesverbetering',
    section: 'Uitbreidingen',
    keywords: [
      'procesverbetering',
      'dmaic',
      'dmadv',
      'kaizen',
      'a3',
      'sipoc',
      'fmea',
      'lean',
      'six sigma',
      'module',
    ],
  ),

  // ── Integraties ───────────────────────────────────────────────────────────
  // `integrationsOnly`: het tabblad Integraties bestaat zodra een koppeling
  // in het register staat (OpenKAT; op web zichtbaar maar uitgeschakeld).
  SettingsSearchEntry(
    tab: SettingsSection.integrations,
    label: 'OpenKAT',
    // Anker naar de sectiekop van het tabblad: OpenKAT is sinds #1158 een
    // integratiekaart ónder de kop 'Integraties', geen eigen sectietitel meer.
    section: 'Integraties',
    integrationsOnly: true,
    keywords: [
      'openkat',
      'integratie',
      'rapportage',
      'map',
      'directory',
      'folder',
      'json',
      'locatie',
      'server',
      'installatie',
      'token',
    ],
  ),

  // ── Documentatie ──────────────────────────────────────────────────────────
  // Dit tabblad heeft een eigen zoekveld over de documentinhoud, dus we
  // spiegelen niet alle documenten: dit zijn ingangen die je naar het tabblad
  // brengen. `section: null` omdat de reader met DocSection werkt in plaats van
  // _sectionTitle — er is geen anker om naartoe te scrollen, en het tabblad
  // openen is genoeg. Bewust géén licentie-ingang: wie "licentie" zoekt wil de
  // echte toestemming onder Privacy en classificatie, niet de reader.
  SettingsSearchEntry(
    tab: SettingsSection.documentation,
    label: 'Documentatie',
    section: null,
    keywords: [
      'handleiding',
      'help',
      'uitleg',
      'manual',
      'hulp',
      'gebruiksaanwijzing',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.documentation,
    label: 'Gebruikershandleiding',
    section: null,
    keywords: ['handleiding', 'manual', 'help', 'uitleg'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.documentation,
    label: 'Sneltoetsen',
    section: null,
    keywords: ['sneltoets', 'shortcut', 'toetsenbord', 'keyboard', 'toetsen'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.documentation,
    label: 'Begrippenlijst',
    section: null,
    keywords: ['begrip', 'term', 'woordenlijst', 'glossary', 'jargon'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.documentation,
    label: 'Bestandsformaat',
    section: null,
    keywords: ['markdown', 'marp', 'formaat', 'bestandsformaat', 'opslag'],
  ),

  // ── Over OciDeck ──────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.about,
    label: 'Contact',
    section: null,
    keywords: ['contact', 'telefoon', 'e-mail', 'adres', 'support', 'bereiken'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.about,
    label: 'Uitgever: Stichting LibreKAT',
    section: null,
    keywords: ['uitgever', 'stichting', 'librekat', 'colofon', 'organisatie'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.about,
    label: 'IBAN',
    section: null,
    keywords: ['iban', 'bank', 'rekening', 'doneren', 'donatie', 'steunen'],
  ),
  // Eén ingang, hoewel het dankwoord op twee plekken staat (hier en in
  // Documentatie): twee treffers met dezelfde naam laten de zoeker kiezen
  // tussen twee routes naar hetzelfde document. Deze wijst naar de tegel die
  // naast het Vigilis-logo staat. Wie "bijdragers" of "credits" typt kent het
  // woord "dank" niet per se — vandaar de synoniemen.
  SettingsSearchEntry(
    tab: SettingsSection.about,
    label: 'Met dank aan',
    section: null,
    keywords: [
      'dank',
      'dankwoord',
      'bijdrage',
      'bijdragers',
      'contributors',
      'credits',
      'mensen',
      'namen',
    ],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.about,
    label: 'Licenties van derden',
    section: null,
    keywords: [
      'licentie',
      'licenties',
      'license',
      'eupl',
      'opensource',
      'derden',
      'attributie',
      'ofl',
      'lettertype',
      'copyright',
    ],
  ),
];
