// Part of the settings library — see ../settings.dart.
//
// AppSettings: de volledige, opgeslagen instellingenstaat van de app. Losgeknipt
// van settings.dart om dat bestand onder het regelplafond te houden (het groeide
// er met de tabelstijl- en paginamaatvelden overheen); het blijft één library met
// ThemeProfile, dus elke aanroeper haalt het nog steeds via
// `models/settings.dart` — geen tweede import.
part of '../settings.dart';

class AppSettings {
  final String languageCode;

  /// Alle bestandsverbindingen, in de volgorde die de gebruiker zelf sleept.
  ///
  /// Dit is de enige bron van waarheid over waar presentaties vandaan komen.
  /// Lokale mappen, WebDAV-servers en git-repositories staan hier door elkaar,
  /// zodat je per opdrachtgever kunt inrichten in plaats van per techniek.
  ///
  /// De volgorde is betekenisvol: de bovenste bruikbare verbinding van een
  /// soort is de standaard voor die soort (zie [primaryOf]). Herordenen is dus
  /// hoe je kiest welke server "de" server is, zonder iets te hoeven wissen.
  final List<StorageConnection> connections;

  /// De bovenste bruikbare verbinding van een soort, of `null` als er geen is.
  /// Half ingevulde verbindingen worden overgeslagen: die staan in de lijst
  /// omdat de gebruiker er nog aan werkt, niet omdat ze dienst kunnen doen.
  StorageConnection? primaryOf(StorageConnectionKind kind) {
    for (final c in connections) {
      if (c.kind == kind && c.isConfigured) return c;
    }
    return null;
  }

  /// Alle bruikbare verbindingen van één soort, in gebruikersvolgorde — de
  /// lijst die een keuzedialoog toont.
  List<T> connectionsOf<T extends StorageConnection>() => [
    for (final c in connections)
      if (c is T && c.isConfigured) c,
  ];

  /// Zoek een verbinding op id; `null` als hij is verwijderd. Herkomstgegevens
  /// van een geopend deck wijzen via id, dus dit is de plek waar "de bron van
  /// dit deck bestaat niet meer" zichtbaar wordt.
  StorageConnection? connectionById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// De lokale mappen als bibliotheken — de vorm die de zoek- en
  /// openen-schermen al verwachten. Afgeleid, niet opgeslagen.
  List<LibraryFolder> get libraries => [
    for (final c in connections)
      if (c is LocalConnection && c.isConfigured)
        LibraryFolder(name: c.name, path: c.path),
  ];

  /// De standaard-startmap: het pad van de eerste bibliotheek, of null wanneer
  /// er geen is. Compat-toegang voor de vele plekken die één "thuismap"
  /// verwachten (native openen/opslaan als startpunt, logo-oplossing,
  /// weergavepad-verkorting).
  String? get homeDirectory => libraries.isEmpty ? null : libraries.first.path;

  /// Alle bibliotheekpaden — de zoekwortels voor multi-map zoekacties (openen,
  /// afbeeldingenbibliotheek, brede scan).
  List<String> get libraryPaths => [for (final l in libraries) l.path];

  /// De eigen checklist-sjablonen van de gebruiker (feedback #9): herbruikbare
  /// testlijsten die per scope-object in een `checklist`-slide geladen kunnen
  /// worden, naast de gebundelde WSTG-lijst. Opgeslagen als JSON onder één
  /// prefs-sleutel (`customChecklists`).
  final List<ChecklistTemplate> customChecklists;

  /// Folder where all exports (PDF/PPTX) are written. When null, exports land
  /// next to the source deck (legacy behaviour).
  final String? exportDirectory;
  final List<ThemeProfile> themeProfiles;
  final String selectedThemeProfileName;
  final List<AppAppearanceProfile> appAppearanceProfiles;
  final String selectedAppAppearanceProfileName;

  /// Documentmodus: de standaard stijl (naam van een [ThemeProfile]) voor
  /// documenten die zelf geen `theme:` in hun frontmatter dragen. `null` = geen
  /// (platte tekst). Puur een weergave- en exportkeuze; het schrijft niets in de
  /// `.md` — alleen een per-document keuze doet dat, byte-chirurgisch.
  final String? documentDefaultStyle;

  /// Documentmodus: dwing [documentDefaultStyle] af als huisstijl — negeer de
  /// per-document `theme:` en render/exporteer elk document met de standaardstijl.
  /// Standaard uit. Wist geen bestaande frontmatter; die blijft in het bestand
  /// staan maar wordt genegeerd zolang dit aanstaat.
  final bool documentStyleEnforced;

  /// Documentmodus: laat elk hoofdstuk (een H1-kop) bij het exporteren/afdrukken
  /// op een nieuwe pagina beginnen. Standaard uit. Puur een export-/afdrukkeuze;
  /// het raakt de `.md` niet.
  final bool documentChapterPageBreak;

  /// Snijtekens rond het snijformaat in de LaTeX/PDF-export.
  ///
  /// Bewust hier en niet in [PageMargins]: die reist sinds de paginaopmaak per
  /// document mee in het `.md`, en voor snijtekens bestaat geen vocabulaire dat
  /// een andere lezer uitvoert. Ze zijn bovendien een keuze per drukgang, niet
  /// een eigenschap van de tekst.
  ///
  /// Werkt alleen samen met een afloop, en alleen in het LaTeX-pad: geen
  /// browser kent `marks` uit CSS Paged Media, dus de HTML-export belooft ze
  /// niet.
  final bool documentCropMarks;

  /// Documentmodus: maximale schrijfbreedte van de visuele editor in px, of
  /// `null` voor volledige breedte. Standaard 1100 — breder dan de vorige
  /// vaste 860, zodat de editor meer van het scherm gebruikt. De gebruiker kan
  /// hem smaller of breder zetten, of op "volledige breedte" (`null`).
  final double? documentEditorMaxWidth;

  /// Documentmodus: op welke breedte de visuele editor schrijft.
  ///
  /// Standaard [DocumentEditorWidth.page] — dezelfde breedte als het vel, want
  /// dat is wat de pagina-einden waar maakt. Zat vroeger vastgeklonken aan de
  /// schakelaar voor die einden, waardoor de instelling hieronder stilzwijgend
  /// werd overruled en "volledige breedte" niets leek te doen.
  final DocumentEditorWidth documentEditorWidth;

  /// Documentmodus: de zoomfactor van de visuele editor en de Pagina's-stand.
  ///
  /// 1,0 is ware grootte. De zoom schaalt de tekst én de kolombreedte én de
  /// paginahoogte waarmee de einden worden uitgerekend, alledrie met dezelfde
  /// factor — anders zou een einde op een andere plek in de tekst vallen zodra
  /// je inzoomt, en dan wijst de lijn nergens naar.
  final double documentEditorZoom;

  /// Documentmodus: paginamaat voor export (ISO-216). Feature 3. Opgeslagen
  /// als id-string (bijv. `"A4"`); `null` = geen `@page`-regel (browser-
  /// default). Standaard A4 portret.
  final PageSizeSpec documentPageSize;

  /// Documentmodus: paginamarges voor export. Feature 3. Opgeslagen als
  /// id-string (bijv. `"25,25,20,20"`); `null` = geen marge. Standaard
  /// 25/25/20/20mm.
  final PageMargins documentPageMargins;

  /// Named cockpit colour schemes and the globally selected one. The active
  /// scheme is applied to every cockpit slide (in preview and export); the
  /// colours are styling and live here, not in the deck `.md`.
  final List<CockpitColorScheme> cockpitColorSchemes;
  final String selectedCockpitColorSchemeName;
  final CockpitVisualStyle cockpitVisualStyle;
  final List<RecentFile> recentFiles;

  /// Herkomst van remote opgehaalde recente bestanden: lokaal pad → bron
  /// (Nextcloud-server + pad, of de import-URL). Alleen paden uit
  /// [recentFiles] staan erin; lokale bestanden ontbreken bewust. De welkom-
  /// lijst markeert deze vermeldingen met een wolk-badge zodat direct
  /// zichtbaar is welke presentaties van buiten komen.
  final Map<String, String> recentFileOrigins;

  /// Optioneel vrijgaveplafond voor de classificatie-gate, opgeslagen als
  /// TLP-sleutel (zie `TlpLevelX.key`). `null` = geen plafond, alles mag worden
  /// geëxporteerd (standaard). Classificeren blijft optioneel; dit plafond
  /// blokkeert alleen decks die er bovenuit zijn geclassificeerd.
  final String? maxReleaseExportTlpKey;

  /// Optioneel minimumniveau voor export-handhaving (TLP-sleutel). Decks
  /// onder dit niveau (inclusief ongeclassificeerd) worden geweigerd zodra dit
  /// is ingesteld. Standaard uit — backward compatible.
  final String? minRequiredExportTlpKey;

  /// Weiger export wanneer het deck geen TLP-niveau heeft ([TlpLevel.none]).
  /// Standaard uit. Kan samen met [minRequiredExportTlpKey] worden gebruikt.
  final bool requireClassificationOnExport;

  /// Diagonaal classificatie-watermerk op slides (fase 2). Standaard uit.
  final bool classificationWatermarkEnabled;

  /// Of de privacycontrole draait: leest OciDeck de slides na op gegevens die
  /// privacygevoelig kunnen zijn (identificatienummers, contactgegevens)?
  ///
  /// Staat standaard **aan**. De controle draait volledig op dit apparaat en
  /// stuurt niets naar buiten. Uitzetten laat de scan echt niet draaien — het
  /// verbergt de meldingen niet alleen.
  final bool privacyChecksEnabled;

  /// Of afbeeldingen worden nagekeken op herkenbare gezichten.
  ///
  /// Eigen schakelaar naast de hoofdschakelaar, want dit is verreweg de duurste
  /// controle: elke afbeelding wordt gedecodeerd en door een neuraal netwerk
  /// gehaald. Wie op een oude machine werkt of decks met tientallen foto's
  /// heeft, mag dat kunnen uitzetten zonder de tekstcontrole te verliezen.
  ///
  /// Standaard aan: een afbeelding waarop iemand herkenbaar staat is een
  /// persoonsgegeven, en dat is precies wat deze controle hoort te vinden.
  final bool privacyImageFaceDetection;

  /// Behandel een `zeker`-bevinding als fout in plaats van waarschuwing.
  ///
  /// Standaard **uit**, en dat is geen slapheid maar een keuze over wie de
  /// rekening krijgt. Een fout activeert `qualityBlockExportOnErrors`, en wie
  /// die instelling ooit aanzette voor contrastfouten zou ineens geen deck met
  /// een e-mailadres meer kunnen exporteren — een instelling die iets anders
  /// gaat betekenen zonder dat iemand eraan draaide.
  ///
  /// Aan is bedoeld voor gereguleerde omgevingen waar een `zeker`-bevinding
  /// werkelijk een blokkade hoort te zijn. Alleen `zeker` schuift mee:
  /// `waarschijnlijk` blijft een waarschuwing en `mogelijk` blijft informatief.
  /// Dat is met opzet — juist de contextloze treffers landen op `mogelijk`, en
  /// die mogen ook in de strenge stand niemand tegenhouden.
  final bool privacyStrictSeverity;

  /// Detectieregels die de gebruiker heeft uitgezet.
  ///
  /// De ontsnappingsklep: wie één regel te luid vindt, kan chirurgisch ingrijpen
  /// in plaats van de hele controle uit te zetten. Zonder die klep is "alles uit"
  /// de enige uitweg, en dan detecteert er niets meer.
  ///
  /// Standaard staan hier de drie zwaarste art. 9-categorieën in
  /// ([defaultDisabledPrivacyRules]) — niet omdat ze onbelangrijk zijn, maar omdat
  /// hun trefwoorden op gewone zakelijke slides te vaak voorkomen. Wie in die hoek
  /// werkt, zet ze met één vinkje aan.
  final Set<String> privacyDisabledRules;

  /// De landpakketten die de privacycontrole meeneemt (OCIWACHT §5.7, §7).
  ///
  /// Standaard heel Europa — EU-27 plus EER, Zwitserland en het VK. Dat is
  /// verdedigbaar juist omdát de vals-positieven-strategie op checksums leunt:
  /// ruim twintig van de dertig Europese persoonsnummers zijn zelfvaliderend, en
  /// die kosten dus vrijwel geen precisie als je ze allemaal aanzet. De
  /// universele regels (IBAN, e-mail, geheimen, MRZ) staan hier los van en
  /// draaien altijd.
  final Set<String> privacyRegions;

  /// Hoe streng de export-gate is: niets zeggen, waarschuwen (standaard), of
  /// weigeren zolang er onafgehandelde zekere bevindingen zijn.
  ///
  /// Waarschuwen is de standaard omdat een gate die altijd blokkeert, een gate is
  /// die wordt weggeklikt.
  final PrivacyExportGate privacyExportGate;

  /// Je eigen gegevens: naam, e-mailadres, telefoonnummer, organisatiedomein.
  /// Eén per regel.
  ///
  /// Wat hierin staat, wordt niet als bevinding gemeld. De grootste praktische
  /// vals-positieven-bron is namelijk de auteur zelf — zijn adres in de footer,
  /// zijn naam op de titelslide. Dat is geen bevinding maar de afzender.
  final String privacyOwnIdentity;

  /// Scale factor for all interface text (1.0–2.0), on top of the system
  /// text scaling. The slide canvas itself is never scaled: slides are a
  /// fixed 16:9 design surface. WCAG 1.4.4 asks for text resizing up to 200%.
  final double uiTextScale;

  /// Lettergrootte in de documentatielezer (0.8–1.8), bovenop [uiTextScale] en
  /// de systeemschaal. Los van de interfaceschaal zodat de lezer per keer groter
  /// of kleiner kan zonder de rest van de app te beïnvloeden.
  final double docReaderTextScale;

  /// Toon een waarschuwing vóór export wanneer de slide-kwaliteitscontrole
  /// problemen vindt (alt-tekst, contrast, tekstdichtheid).
  final bool qualityWarningsOnExport;

  /// Blokkeer export volledig wanneer de kwaliteitscontrole fouten vindt.
  final bool qualityBlockExportOnErrors;

  /// Minimale contrastverhouding voor normale tekst waaronder de
  /// kwaliteitscontrole markeert. Standaard WCAG AA (4.5); lager = toleranter
  /// (bijv. 3.5 accepteert een 3.6:1-verhouding). Begrensd tot 1.0–7.0.
  final double contrastMinRatio;

  /// Of het openscherm en de brede zoekactie een gerenderd voorbeeld van het
  /// aangewezen bestand tonen. Standaard uit: het voorbeeld leest en tekent een
  /// bestand dat je nog niet gekozen hebt, en dat hoort een bewuste keuze te
  /// zijn — niet iets wat ongevraagd gebeurt terwijl je door een lijst loopt.
  final bool showOpenPreview;

  /// Of online media (afbeeldingen/video's via URL en YouTube/Vimeo-embeds)
  /// live mag worden geladen. Standaard uit (fail-closed): een geopende deck
  /// van een ander kan dan niet ongevraagd naar buiten "bellen" of pixels van
  /// derden laden. De gebruiker zet dit bewust aan in de instellingen.
  final bool allowRemoteMedia;

  /// De standaard-CVE-mirror (een NVD-spiegel) voor het opzoeken van CVE's.
  static const defaultCveApiBaseUrl = 'https://cveapi.librekat.nl';

  /// Of CVE's online opgezocht mogen worden (in de bevinding-editor). Standaard
  /// uit (fail-closed, offline-first): de gebruiker zet het bewust aan en dan
  /// nog geldt de outbound-consent. Alleen desktop (geen web).
  final bool allowCveLookup;

  /// De basis-URL van de CVE-mirror; instelbaar zodat je een eigen spiegel kunt
  /// gebruiken. Leeg = de standaard ([defaultCveApiBaseUrl]).
  final String cveApiBaseUrl;

  /// De standaard-WebDAV-bron: de bovenste bruikbare WebDAV-verbinding, of
  /// `null` wanneer er geen is. Afgeleid uit [connections] — de plekken die
  /// zonder keuze van de gebruiker één server nodig hebben lezen hier.
  WebdavServer? get webdavServer =>
      (primaryOf(StorageConnectionKind.webdav) as WebdavConnection?)?.server;

  /// De standaard-S3-bucket, langs dezelfde regel als [webdavServer].
  S3Bucket? get s3Bucket =>
      (primaryOf(StorageConnectionKind.s3) as S3Connection?)?.bucket;

  /// De standaard-git-repository, langs dezelfde regel als [webdavServer].
  GitRepoConfig? get gitRepo =>
      (primaryOf(StorageConnectionKind.git) as GitConnection?)?.repo;

  /// De git-verbinding waar een geopend deck bij hoort.
  ///
  /// Eerst op id, want dat overleeft hernoemen en het herstellen van een
  /// typefout in de URL. Lukt dat niet — een herkomst uit een versie van vóór
  /// de verbindingenlijst draagt nog geen id — dan alsnog op de configuratie,
  /// zodat zo'n deck niet losgeslagen raakt van zijn repo. `null` wanneer de
  /// verbinding is verwijderd; de aanroeper moet dan om een keuze vragen in
  /// plaats van te gokken.
  GitConnection? gitConnectionFor(String? connectionId, GitRepoConfig config) {
    final byId = connectionById(connectionId);
    if (byId is GitConnection) return byId;
    for (final c in connections) {
      if (c is GitConnection && c.repo == config) return c;
    }
    return null;
  }

  /// Instellingen voor de optionele AI-assistentie. Standaard uit; bevat nooit
  /// een API-sleutel (die staat in de keychain).
  final AiSettings aiSettings;

  /// Het app-globale Matrix-account voor realtime samenwerken, of `null` als er
  /// geen is ingesteld. Bevat nooit het access-token (dat staat in de keychain,
  /// zie `SecretStore`) — alleen de niet-geheime homeserver/user/device-gegevens.
  final MatrixServer? matrixAccount;

  /// Instellingen voor de optionele LibrePlan-connector. Standaard uit; bevat
  /// nooit het wachtwoord (dat staat in de keychain).
  final LibreplanSettings libreplanSettings;

  const AppSettings({
    this.languageCode = 'nl',
    this.connections = const [],
    this.customChecklists = const [],
    this.exportDirectory,
    this.themeProfiles = ThemeProfile.builtIns,
    this.selectedThemeProfileName = 'LibreKAT',
    this.appAppearanceProfiles = AppAppearanceProfile.builtIns,
    this.selectedAppAppearanceProfileName = 'Europa',
    this.documentDefaultStyle,
    this.documentStyleEnforced = false,
    this.documentChapterPageBreak = false,
    this.documentCropMarks = false,
    this.documentEditorMaxWidth = 1100,
    this.documentEditorWidth = DocumentEditorWidth.page,
    this.documentEditorZoom = 1,
    this.documentPageSize = PageSizeSpec.a4,
    this.documentPageMargins = const PageMargins(),
    this.cockpitColorSchemes = CockpitColorScheme.builtIns,
    this.selectedCockpitColorSchemeName = 'Standaard',
    this.cockpitVisualStyle = CockpitVisualStyle.authentic,
    this.recentFiles = const [],
    this.recentFileOrigins = const {},
    this.maxReleaseExportTlpKey,
    this.minRequiredExportTlpKey,
    this.requireClassificationOnExport = false,
    this.classificationWatermarkEnabled = false,
    this.privacyChecksEnabled = true,
    this.privacyImageFaceDetection = true,
    this.privacyStrictSeverity = false,
    this.privacyDisabledRules = defaultDisabledPrivacyRules,
    this.privacyRegions = defaultPrivacyRegions,
    this.privacyExportGate = PrivacyExportGate.warn,
    this.privacyOwnIdentity = '',
    this.uiTextScale = 1.0,
    this.docReaderTextScale = 1.0,
    this.qualityWarningsOnExport = true,
    this.qualityBlockExportOnErrors = false,
    this.contrastMinRatio = 4.5,
    this.showOpenPreview = false,
    this.allowRemoteMedia = false,
    this.allowCveLookup = false,
    this.cveApiBaseUrl = defaultCveApiBaseUrl,
    this.aiSettings = const AiSettings(),
    this.matrixAccount,
    this.libreplanSettings = const LibreplanSettings(),
  });

  ThemeProfile get themeProfile {
    return themeProfiles.firstWhere(
      (p) => p.name == selectedThemeProfileName,
      orElse: () => themeProfiles.first,
    );
  }

  AppAppearanceProfile get appAppearanceProfile {
    return appAppearanceProfiles.firstWhere(
      (p) => p.name == selectedAppAppearanceProfileName,
      orElse: () => appAppearanceProfiles.first,
    );
  }

  CockpitColorScheme get cockpitColorScheme {
    final selected = cockpitColorSchemes.isEmpty
        ? CockpitColorScheme.standard
        : cockpitColorSchemes.firstWhere(
            (s) => s.name == selectedCockpitColorSchemeName,
            orElse: () => cockpitColorSchemes.first,
          );
    return selected.copyWith(visualStyle: cockpitVisualStyle);
  }

  static const availableFonts = [
    'Arial',
    'EB Garamond',
    'Helvetica Neue',
    'Verdana',
    'Trebuchet MS',
    'Georgia',
    'Times New Roman',
    'Gill Sans MT',
    'Calibri',
    'Segoe UI',
    'Courier New',
  ];

  /// Monospace families offered for code slides. `monospace` is the system
  /// default; the rest are common typewriter/coding faces.
  static const codeFonts = [
    'monospace',
    'Courier New',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'Cascadia Code',
  ];

  AppSettings copyWith({
    String? languageCode,
    List<StorageConnection>? connections,
    List<ChecklistTemplate>? customChecklists,
    String? exportDirectory,
    ThemeProfile? themeProfile,
    List<ThemeProfile>? themeProfiles,
    String? selectedThemeProfileName,
    List<AppAppearanceProfile>? appAppearanceProfiles,
    String? selectedAppAppearanceProfileName,
    String? documentDefaultStyle,
    bool? documentStyleEnforced,
    bool? documentChapterPageBreak,
    bool? documentCropMarks,
    double? documentEditorMaxWidth,
    DocumentEditorWidth? documentEditorWidth,
    double? documentEditorZoom,
    PageSizeSpec? documentPageSize,
    PageMargins? documentPageMargins,
    List<CockpitColorScheme>? cockpitColorSchemes,
    String? selectedCockpitColorSchemeName,
    CockpitVisualStyle? cockpitVisualStyle,
    List<RecentFile>? recentFiles,
    Map<String, String>? recentFileOrigins,
    String? maxReleaseExportTlpKey,
    String? minRequiredExportTlpKey,
    bool? requireClassificationOnExport,
    bool? classificationWatermarkEnabled,
    bool? privacyChecksEnabled,
    bool? privacyImageFaceDetection,
    bool? privacyStrictSeverity,
    Set<String>? privacyDisabledRules,
    Set<String>? privacyRegions,
    PrivacyExportGate? privacyExportGate,
    String? privacyOwnIdentity,
    double? uiTextScale,
    double? docReaderTextScale,
    bool? qualityWarningsOnExport,
    bool? qualityBlockExportOnErrors,
    double? contrastMinRatio,
    bool? showOpenPreview,
    bool? allowRemoteMedia,
    bool? allowCveLookup,
    String? cveApiBaseUrl,
    AiSettings? aiSettings,
    MatrixServer? matrixAccount,
    bool clearMatrixAccount = false,
    LibreplanSettings? libreplanSettings,
    bool clearExportDirectory = false,
    bool clearMaxReleaseExportTlp = false,
    bool clearMinRequiredExportTlp = false,
    bool clearDocumentDefaultStyle = false,
    bool clearDocumentEditorMaxWidth = false,
  }) {
    final nextProfiles = themeProfiles ?? this.themeProfiles;
    return AppSettings(
      languageCode: languageCode ?? this.languageCode,
      connections: connections ?? this.connections,
      customChecklists: customChecklists ?? this.customChecklists,
      exportDirectory: clearExportDirectory
          ? null
          : (exportDirectory ?? this.exportDirectory),
      themeProfiles: themeProfile == null
          ? nextProfiles
          : [
              for (final profile in nextProfiles)
                if (profile.name == themeProfile.name)
                  themeProfile
                else
                  profile,
              if (!nextProfiles.any((p) => p.name == themeProfile.name))
                themeProfile,
            ],
      selectedThemeProfileName:
          selectedThemeProfileName ??
          themeProfile?.name ??
          this.selectedThemeProfileName,
      appAppearanceProfiles:
          appAppearanceProfiles ?? this.appAppearanceProfiles,
      selectedAppAppearanceProfileName:
          selectedAppAppearanceProfileName ??
          this.selectedAppAppearanceProfileName,
      documentDefaultStyle: clearDocumentDefaultStyle
          ? null
          : (documentDefaultStyle ?? this.documentDefaultStyle),
      documentStyleEnforced:
          documentStyleEnforced ?? this.documentStyleEnforced,
      documentChapterPageBreak:
          documentChapterPageBreak ?? this.documentChapterPageBreak,
      documentCropMarks: documentCropMarks ?? this.documentCropMarks,
      documentEditorMaxWidth: clearDocumentEditorMaxWidth
          ? null
          : (documentEditorMaxWidth ?? this.documentEditorMaxWidth),
      documentEditorWidth: documentEditorWidth ?? this.documentEditorWidth,
      documentEditorZoom: documentEditorZoom ?? this.documentEditorZoom,
      documentPageSize: documentPageSize ?? this.documentPageSize,
      documentPageMargins: documentPageMargins ?? this.documentPageMargins,
      cockpitColorSchemes: cockpitColorSchemes ?? this.cockpitColorSchemes,
      selectedCockpitColorSchemeName:
          selectedCockpitColorSchemeName ?? this.selectedCockpitColorSchemeName,
      cockpitVisualStyle: cockpitVisualStyle ?? this.cockpitVisualStyle,
      recentFiles: recentFiles ?? this.recentFiles,
      recentFileOrigins: recentFileOrigins ?? this.recentFileOrigins,
      maxReleaseExportTlpKey: clearMaxReleaseExportTlp
          ? null
          : (maxReleaseExportTlpKey ?? this.maxReleaseExportTlpKey),
      minRequiredExportTlpKey: clearMinRequiredExportTlp
          ? null
          : (minRequiredExportTlpKey ?? this.minRequiredExportTlpKey),
      requireClassificationOnExport:
          requireClassificationOnExport ?? this.requireClassificationOnExport,
      classificationWatermarkEnabled:
          classificationWatermarkEnabled ?? this.classificationWatermarkEnabled,
      privacyChecksEnabled: privacyChecksEnabled ?? this.privacyChecksEnabled,
      privacyImageFaceDetection:
          privacyImageFaceDetection ?? this.privacyImageFaceDetection,
      privacyStrictSeverity:
          privacyStrictSeverity ?? this.privacyStrictSeverity,
      privacyDisabledRules: privacyDisabledRules ?? this.privacyDisabledRules,
      privacyRegions: privacyRegions ?? this.privacyRegions,
      privacyExportGate: privacyExportGate ?? this.privacyExportGate,
      privacyOwnIdentity: privacyOwnIdentity ?? this.privacyOwnIdentity,
      uiTextScale: uiTextScale ?? this.uiTextScale,
      docReaderTextScale: docReaderTextScale ?? this.docReaderTextScale,
      qualityWarningsOnExport:
          qualityWarningsOnExport ?? this.qualityWarningsOnExport,
      qualityBlockExportOnErrors:
          qualityBlockExportOnErrors ?? this.qualityBlockExportOnErrors,
      contrastMinRatio: contrastMinRatio ?? this.contrastMinRatio,
      showOpenPreview: showOpenPreview ?? this.showOpenPreview,
      allowRemoteMedia: allowRemoteMedia ?? this.allowRemoteMedia,
      allowCveLookup: allowCveLookup ?? this.allowCveLookup,
      cveApiBaseUrl: cveApiBaseUrl ?? this.cveApiBaseUrl,
      aiSettings: aiSettings ?? this.aiSettings,
      matrixAccount: clearMatrixAccount
          ? null
          : (matrixAccount ?? this.matrixAccount),
      libreplanSettings: libreplanSettings ?? this.libreplanSettings,
    );
  }
}
