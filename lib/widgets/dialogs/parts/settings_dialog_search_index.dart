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
  // ── Tab 0 — Algemeen ──────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 0,
    labelKey: 'applicationLanguage',
    sectionKey: 'language',
    keywords: ['taal', 'language', 'nederlands', 'engels', 'vertaling'],
  ),
  SettingsSearchEntry(
    tab: 0,
    label: 'Map toevoegen',
    section: 'Bibliotheken',
    keywords: ['bibliotheek', 'mappen', 'afbeeldingen', 'media'],
  ),
  SettingsSearchEntry(
    tab: 0,
    labelKey: 'choose',
    sectionKey: 'exportFolderSetting',
    keywords: ['export', 'exportmap', 'opslaan', 'uitvoer', 'pdf'],
  ),
  SettingsSearchEntry(
    tab: 0,
    label: 'Tekstgrootte van de interface',
    section: 'Toegankelijkheid',
    keywords: ['lettergrootte', 'zoom', 'groter', 'schaal', 'leesbaarheid'],
  ),
  SettingsSearchEntry(
    tab: 0,
    label: 'Waarschuwing bij export',
    section: 'Toegankelijkheid',
    keywords: ['kwaliteit', 'export', 'waarschuwing'],
  ),
  SettingsSearchEntry(
    tab: 0,
    label: 'Blokkeer export bij ernstige kwaliteitsproblemen',
    section: 'Toegankelijkheid',
    keywords: ['kwaliteit', 'export', 'blokkeren', 'fouten'],
  ),
  SettingsSearchEntry(
    tab: 0,
    label: 'Minimale contrastverhouding',
    section: 'Toegankelijkheid',
    keywords: ['contrast', 'wcag', 'kleurcontrast', 'leesbaarheid'],
  ),

  // ── Tab 1 — App-thema ─────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 1,
    label: 'Donkere interface',
    section: 'Look-and-feel',
    keywords: ['donker', 'dark mode', 'nachtmodus', 'licht'],
  ),
  SettingsSearchEntry(
    tab: 1,
    label: 'Lettertype interface',
    section: 'Look-and-feel',
    keywords: ['font', 'lettertype', 'typografie'],
  ),
  SettingsSearchEntry(
    tab: 1,
    label: 'Hoofdkleur en bovenbalk',
    section: 'Look-and-feel',
    keywords: ['kleur', 'thema', 'balk'],
  ),
  SettingsSearchEntry(
    tab: 1,
    label: 'Knoppen en accenten',
    section: 'Look-and-feel',
    keywords: ['kleur', 'accent', 'knoppen'],
  ),
  SettingsSearchEntry(
    tab: 1,
    label: 'Schermachtergrond',
    section: 'Look-and-feel',
    keywords: ['kleur', 'achtergrond'],
  ),
  SettingsSearchEntry(
    tab: 1,
    label: 'Themanaam',
    section: 'Look-and-feel',
    keywords: ['thema', 'naam', 'profiel'],
  ),

  // ── Tab 2 — Presentatiestijl ──────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 2,
    label: 'Stijlprofiel',
    sectionKey: 'styleProfile',
    keywords: ['profiel', 'stijl', 'huisstijl', 'thema'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Profiel exporteren',
    sectionKey: 'styleProfile',
    keywords: ['exporteren', 'downloaden', 'opslaan', 'delen', 'huisstijl'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Profiel importeren',
    sectionKey: 'styleProfile',
    keywords: ['importeren', 'inladen', 'openen', 'huisstijl'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Achtergrond slides',
    sectionKey: 'settingsColors',
    keywords: ['kleur', 'achtergrond', 'slide'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Accent / bullets',
    sectionKey: 'settingsColors',
    keywords: ['kleur', 'accent', 'opsomming'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Opsommingsteken',
    sectionKey: 'settingsColors',
    keywords: ['bullet', 'stip', 'pootje', 'opsomming'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Syntaxkleuring',
    section: 'Broncode',
    keywords: ['code', 'syntax', 'highlighting', 'programmeren'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Broncode lettertype',
    section: 'Broncode',
    keywords: ['code', 'font', 'monospace'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Afgevinkte tekst doorhalen',
    section: 'Checklist',
    keywords: ['checklist', 'doorhalen', 'afvinken'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Kritiek',
    section: 'Severity (bevindingen)',
    keywords: ['severity', 'bevinding', 'kleur', 'ernst', 'pentest'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Activatieduur',
    section: 'Animatie',
    keywords: ['animatie', 'snelheid', 'duur'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Logo positie',
    section: 'Logo en footer',
    keywords: ['logo', 'positie', 'merk'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Footertekst',
    section: 'Footer',
    keywords: ['footer', 'voettekst', 'paginanummer'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Paginanummers tonen (rechtsonder)',
    section: 'Footer',
    keywords: ['paginanummer', 'nummering', 'footer'],
  ),
  SettingsSearchEntry(
    tab: 2,
    label: 'Standaard laatste slide gebruiken',
    section: 'Laatste slide',
    keywords: ['slotslide', 'afsluiting', 'laatste'],
  ),

  // ── Tab 3 — Cockpit ───────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 3,
    label: 'Cockpit-kleurschema',
    section: 'Cockpit-kleurschema',
    keywords: ['cockpit', 'meter', 'kleur', 'dashboard'],
  ),

  // ── Tab 4 — Licentie en Privacy ───────────────────────────────────────────
  SettingsSearchEntry(
    tab: 4,
    label: 'Toestemming intrekken',
    section: 'Toestemming',
    keywords: ['consent', 'toestemming', 'privacy', 'intrekken', 'licentie'],
  ),

  // ── Tab 5 — Beveiliging ───────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 5,
    label: 'Waarschuw bij mogelijke persoonsgegevens',
    section: 'Privacycontrole',
    keywords: ['privacy', 'persoonsgegevens', 'bsn', 'avg', 'scanner'],
  ),
  SettingsSearchEntry(
    tab: 5,
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
    tab: 5,
    label: 'CVE opzoeken (online)',
    section: 'CVE opzoeken',
    keywords: ['cve', 'kwetsbaarheid', 'lek', 'nvd', 'mitre', 'enisa'],
  ),
  SettingsSearchEntry(
    tab: 5,
    label: 'CVE-mirror (basis-URL)',
    section: 'CVE opzoeken',
    keywords: ['cve', 'mirror', 'url', 'server'],
  ),
  SettingsSearchEntry(
    tab: 5,
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
    tab: 5,
    label: 'Herstelbestanden nu wissen',
    section: 'Herstelbestanden',
    keywords: ['herstel', 'recovery', 'wissen', 'autosave', 'sporen'],
  ),

  // ── Tab 6 — AI-assistentie (geen sectiekoppen op desktop) ─────────────────
  SettingsSearchEntry(
    tab: 6,
    label: 'AI-assistentie inschakelen',
    keywords: ['ai', 'assistent', 'llm', 'model'],
  ),
  SettingsSearchEntry(
    tab: 6,
    label: 'AI-backend',
    keywords: ['ai', 'backend', 'ollama', 'cloud', 'server'],
  ),
  SettingsSearchEntry(tab: 6, label: 'Modelnaam', keywords: ['ai', 'model']),
  SettingsSearchEntry(
    tab: 6,
    label: 'API-sleutel (optioneel)',
    keywords: ['ai', 'api', 'sleutel', 'key', 'token'],
  ),

  // ── Tab 7 — Nextcloud ─────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 7,
    label: 'Server-URL',
    section: 'Nextcloud-bron (WebDAV)',
    keywords: ['nextcloud', 'webdav', 'server', 'cloud', 'url'],
  ),
  SettingsSearchEntry(
    tab: 7,
    label: 'Gebruikersnaam',
    section: 'Nextcloud-bron (WebDAV)',
    keywords: ['nextcloud', 'webdav', 'gebruiker', 'account'],
  ),
  SettingsSearchEntry(
    tab: 7,
    label: 'App-wachtwoord',
    section: 'Nextcloud-bron (WebDAV)',
    keywords: ['nextcloud', 'webdav', 'wachtwoord', 'password'],
  ),
  SettingsSearchEntry(
    tab: 7,
    label: 'Verbinding testen',
    section: 'Nextcloud-bron (WebDAV)',
    keywords: ['nextcloud', 'webdav', 'test', 'verbinding'],
  ),

  // ── Tab 8 — Git-repository ────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 8,
    label: 'Soort forge',
    section: 'Git-repository',
    keywords: ['git', 'forge', 'forgejo', 'gitea', 'github', 'gitlab'],
  ),
  SettingsSearchEntry(
    tab: 8,
    label: 'Server-URL',
    section: 'Git-repository',
    keywords: ['git', 'server', 'url', 'repository'],
  ),
  SettingsSearchEntry(
    tab: 8,
    label: 'Eigenaar',
    section: 'Git-repository',
    keywords: ['git', 'eigenaar', 'owner', 'organisatie', 'gebruiker'],
  ),
  SettingsSearchEntry(
    tab: 8,
    label: 'Repository',
    section: 'Git-repository',
    keywords: ['git', 'repository', 'repo'],
  ),
  SettingsSearchEntry(
    tab: 8,
    label: 'Personal access token',
    section: 'Git-repository',
    keywords: ['git', 'token', 'pat', 'wachtwoord', 'toegang'],
  ),
  SettingsSearchEntry(
    tab: 8,
    label: 'Vertrouwde interne server',
    section: 'Git-repository',
    keywords: ['git', 'intern', 'vertrouwd', 'http', 'ssrf'],
  ),

  // ── Tab 9 — Checklists ────────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 9,
    label: 'Nieuw sjabloon',
    section: 'Eigen checklists',
    keywords: ['checklist', 'sjabloon', 'template'],
  ),

  // ── Tab 10 — Uitbreidingen ────────────────────────────────────────────────
  SettingsSearchEntry(
    tab: 10,
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
    tab: 10,
    label: 'Pakket importeren',
    section: 'Uitbreidingen',
    keywords: ['import', 'pakket', 'offline', 'gegevens'],
  ),
];
