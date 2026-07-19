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
    section: 'Toegankelijkheid',
    keywords: ['kwaliteit', 'export', 'waarschuwing'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.general,
    label: 'Blokkeer export bij ernstige kwaliteitsproblemen',
    section: 'Toegankelijkheid',
    keywords: ['kwaliteit', 'export', 'blokkeren', 'fouten'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.general,
    label: 'Minimale contrastverhouding',
    section: 'Toegankelijkheid',
    keywords: ['contrast', 'wcag', 'kleurcontrast', 'leesbaarheid'],
  ),

  // ── App-thema ─────────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.appearance,
    label: 'Donkere interface',
    section: 'Look-and-feel',
    keywords: ['donker', 'dark mode', 'nachtmodus', 'licht'],
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

  // ── Presentatiestijl ──────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Stijlprofiel',
    sectionKey: 'styleProfile',
    keywords: ['profiel', 'stijl', 'huisstijl', 'thema'],
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
    label: 'Achtergrond slides',
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
    section: 'Logo en footer',
    keywords: ['logo', 'positie', 'merk'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.presentation,
    label: 'Footertekst',
    section: 'Footer',
    keywords: ['footer', 'voettekst', 'paginanummer'],
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

  // ── Cockpit ───────────────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.cockpit,
    label: 'Cockpit-kleurschema',
    section: 'Cockpit-kleurschema',
    keywords: ['cockpit', 'meter', 'kleur', 'dashboard'],
  ),

  // ── Licentie en Privacy ───────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.privacy,
    label: 'Toestemming intrekken',
    section: 'Toestemming',
    keywords: ['consent', 'toestemming', 'privacy', 'intrekken', 'licentie'],
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
    keywords: ['cve', 'kwetsbaarheid', 'lek', 'nvd', 'mitre', 'enisa'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'CVE-mirror (basis-URL)',
    section: 'CVE opzoeken',
    keywords: ['cve', 'mirror', 'url', 'server'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.security,
    label: 'Database ophalen',
    section: 'Lokale CVE-database',
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
    section: 'Herstelbestanden',
    keywords: ['herstel', 'recovery', 'wissen', 'autosave', 'sporen'],
  ),

  // ── AI-assistentie (geen sectiekoppen op desktop) ─────────────────────────
  SettingsSearchEntry(
    tab: SettingsSection.ai,
    label: 'AI-assistentie inschakelen',
    keywords: ['ai', 'assistent', 'llm', 'model'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.ai,
    label: 'AI-backend',
    keywords: ['ai', 'backend', 'ollama', 'cloud', 'server'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.ai,
    label: 'Modelnaam',
    keywords: ['ai', 'model'],
  ),
  SettingsSearchEntry(
    tab: SettingsSection.ai,
    label: 'API-sleutel (optioneel)',
    keywords: ['ai', 'api', 'sleutel', 'key', 'token'],
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

  // ── Documentatie ──────────────────────────────────────────────────────────
  // Dit tabblad heeft een eigen zoekveld over de documentinhoud, dus we
  // spiegelen niet alle documenten: dit zijn ingangen die je naar het tabblad
  // brengen. `section: null` omdat de reader met DocSection werkt in plaats van
  // _sectionTitle — er is geen anker om naartoe te scrollen, en het tabblad
  // openen is genoeg. Bewust géén licentie-ingang: wie "licentie" zoekt wil de
  // echte toestemming onder Licentie en Privacy, niet de reader.
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
];
