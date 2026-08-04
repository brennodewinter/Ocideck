import 'privacy_disposition.dart';
import 'privacy_finding.dart';
import '../services/privacy/privacy_regions.dart';
import 'ai_settings.dart';
import 'libreplan_settings.dart';
import 'chart.dart' show normalizeChartColor;
import 'checklist_template.dart';
import 'library_folder.dart';
import 'recent_file.dart';
import 'storage_connection.dart';
import 'git_settings.dart';
import 's3_settings.dart';
import 'webdav_settings.dart';
import 'matrix_settings.dart';

export 'ai_settings.dart';
export 'libreplan_settings.dart';
export 'checklist_template.dart';
export 'library_folder.dart';
export 'recent_file.dart';
export 'git_settings.dart';
export 's3_settings.dart';
export 'webdav_settings.dart';

part 'parts/app_appearance_profile.dart';

/// Glyph used for unordered (bullet) list markers. [dot] is the classic
/// typographic bullet; [paw] swaps in a small cat-paw drawn in the accent
/// colour (OciDeck's mascot). The theme picks a default; a slide may override
/// it (see `Slide.bulletMarkerOverride`).
enum BulletMarker { dot, paw }

/// Shared activation/animation duration (ms) that animated slide types
/// (timeline, cockpit) inherit from the theme when a slide sets no own value.
/// One knob drives both so a timeline builds up over the same span as a
/// cockpit. The ceiling matches the per-type maxima (30s); a slide that wants
/// different pacing overrides it (see `Slide.timelineAnimationMs` /
/// `CockpitSpec.animationDurationMs`, both nullable = inherit this).
const int kThemeDefaultAnimationDurationMs = 2000;
const int kThemeMinAnimationDurationMs = 400;
const int kThemeMaxAnimationDurationMs = 30000;

/// Clamp a stored/edited theme animation duration into the allowed range.
int clampThemeAnimationDuration(int ms) =>
    ms.clamp(kThemeMinAnimationDurationMs, kThemeMaxAnimationDurationMs);

class ThemeProfile {
  final String name;
  final String slideBackgroundColor;
  final String textColor;
  final String accentColor;
  final String checklistCheckedColor;
  final String checklistUncheckedColor;
  final bool checklistStrikeThrough;

  /// Default marker glyph for bullet lists across the deck. A slide can override
  /// it per-slide. Defaults to [BulletMarker.dot].
  final BulletMarker bulletMarker;
  final String tableTextColor;
  final String tableHeaderTextColor;
  final String tableHeaderBackgroundColor;
  final String titleBackgroundColor;
  final String titleTextColor;
  final String sectionBackgroundColor;

  /// Colours for code (broncode) slides. Defaults mirror the atom-one-dark
  /// editor look. Set e.g. black background + bright green text with
  /// [codeHighlightSyntax] off for a classic CRT terminal feel.
  final String codeBackgroundColor;
  final String codeTextColor;

  /// When false, code is shown monochrome in [codeTextColor] (no per-token
  /// syntax colours) — required for a believable single-colour CRT screen.
  final bool codeHighlightSyntax;

  /// Monospace font family for code slides. `monospace` uses the system default;
  /// e.g. `Courier New` for a typewriter look.
  final String codeFontFamily;

  final String? logoPath;
  final String logoPosition;
  final int logoSize;

  /// Lettertype van de presentatie — hoort bij de stijl, niet bij de app.
  final String fontFamily;

  /// Vrije footertekst onderaan elke slide. Ondersteunt tokens: {page},
  /// {total}, {date}, {title}. Leeg = geen footertekst.
  final String footerText;

  /// Toon "pagina / totaal" rechtsonder op elke slide.
  final bool footerShowPageNumbers;

  /// Horizontale positie van de footer: left, center of right.
  final String footerPosition;

  /// Optional markdown slide that is appended when presenting/exporting with
  /// this theme profile. It stays out of the editable deck slide list.
  final bool closingSlideEnabled;
  final String closingSlideMarkdown;

  /// Default activation/animation duration (ms) for animated slide types
  /// (timeline, cockpit). A slide may override it; null override = inherit this.
  final int animationDurationMs;

  /// Severity colour tokens for finding / CVSS rendering (the five FIRST bands,
  /// Critical→Informational). Defaults mirror the built-in
  /// [FindingSeverityPalette] so every existing profile renders identically; the
  /// security profile and the colours editor can retune them (PENTEST_MIAUW §11).
  final String severityCriticalColor;
  final String severityHighColor;
  final String severityMediumColor;
  final String severityLowColor;
  final String severityNoneColor;

  const ThemeProfile({
    this.name = 'Standaard',
    this.slideBackgroundColor = '#FFFFFF',
    this.textColor = '#222222',
    this.accentColor = '#2E7D64',
    this.checklistCheckedColor = '#2E7D64',
    this.checklistUncheckedColor = '#CBD5E1',
    this.checklistStrikeThrough = true,
    this.bulletMarker = BulletMarker.dot,
    String? tableTextColor,
    this.tableHeaderTextColor = '#FFFFFF',
    String? tableHeaderBackgroundColor,
    this.titleBackgroundColor = '#1C2B47',
    this.titleTextColor = '#FFFFFF',
    this.sectionBackgroundColor = '#2E7D64',
    this.codeBackgroundColor = '#282C34',
    this.codeTextColor = '#ABB2BF',
    this.codeHighlightSyntax = true,
    this.codeFontFamily = 'monospace',
    this.logoPath,
    this.logoPosition = 'bottom-right',
    this.logoSize = 96,
    this.fontFamily = 'Arial',
    this.footerText = '',
    this.footerShowPageNumbers = false,
    this.footerPosition = 'right',
    this.closingSlideEnabled = false,
    this.closingSlideMarkdown = '# Bedankt\n\nVragen?',
    this.animationDurationMs = kThemeDefaultAnimationDurationMs,
    this.severityCriticalColor = '#B91C1C',
    this.severityHighColor = '#EA580C',
    this.severityMediumColor = '#D97706',
    this.severityLowColor = '#15803D',
    this.severityNoneColor = '#475569',
  }) : tableTextColor = tableTextColor ?? textColor,
       tableHeaderBackgroundColor = tableHeaderBackgroundColor ?? accentColor;

  static const logoPositions = [
    'top-left',
    'top-right',
    'bottom-left',
    'bottom-right',
  ];

  static const footerPositions = ['left', 'center', 'right'];

  /// Ingebouwd LibreKAT-profiel: de huisstijl (EU-blauw op wit, EB Garamond,
  /// gebundeld logo) die als standaard wordt uitgerold. Het logo is een
  /// `asset:`-pad zodat het op elk platform — ook web — rendert en mee kan in
  /// pakket-exports.
  static const libreKat = ThemeProfile(
    name: 'LibreKAT',
    slideBackgroundColor: '#FFFFFF',
    textColor: '#003399',
    accentColor: '#003399',
    checklistCheckedColor: '#003399',
    checklistUncheckedColor: '#DC2626',
    checklistStrikeThrough: true,
    bulletMarker: BulletMarker.dot,
    tableTextColor: '#003399',
    tableHeaderTextColor: '#FFCC00',
    tableHeaderBackgroundColor: '#003399',
    titleBackgroundColor: '#FFFFFF',
    titleTextColor: '#003399',
    sectionBackgroundColor: '#FFFFFF',
    codeBackgroundColor: '#111827',
    codeTextColor: '#2E7D64',
    codeHighlightSyntax: true,
    codeFontFamily: 'monospace',
    logoPath: 'asset:assets/images/librekat-logo.png',
    logoPosition: 'bottom-left',
    logoSize: 96,
    fontFamily: 'EB Garamond',
  );

  /// Ingebouwd beveiligingsprofiel voor pentest-/MIAUW-rapporten (PENTEST_MIAUW
  /// §11): een strakke, zakelijke look — leesbare lichte pagina's met een
  /// donkere slate-titelbalk en een rood accent dat de beveiligingscontext
  /// signaleert. De severity-tokens blijven op de FIRST-standaardpalet, zodat
  /// bevindingskaarten meteen de vertrouwde bandkleuren tonen.
  static const security = ThemeProfile(
    name: 'Security',
    slideBackgroundColor: '#FFFFFF',
    textColor: '#1E293B',
    accentColor: '#B91C1C',
    checklistCheckedColor: '#15803D',
    checklistUncheckedColor: '#CBD5E1',
    checklistStrikeThrough: true,
    bulletMarker: BulletMarker.dot,
    tableTextColor: '#1E293B',
    tableHeaderTextColor: '#FFFFFF',
    tableHeaderBackgroundColor: '#0F172A',
    titleBackgroundColor: '#0F172A',
    titleTextColor: '#FFFFFF',
    sectionBackgroundColor: '#B91C1C',
    codeBackgroundColor: '#0F172A',
    codeTextColor: '#E2E8F0',
    codeHighlightSyntax: true,
    codeFontFamily: 'monospace',
    fontFamily: 'Arial',
  );

  /// Ingebouwde stijlprofielen voor een verse installatie: LibreKAT voorop
  /// (en dus de standaardselectie), met het neutrale 'Standaard' en het
  /// beveiligingsprofiel ernaast. Bestaande installaties behouden hun eigen
  /// opgeslagen profielenlijst.
  static const builtIns = [libreKat, ThemeProfile(), security];

  ThemeProfile copyWith({
    String? name,
    String? slideBackgroundColor,
    String? textColor,
    String? accentColor,
    String? checklistCheckedColor,
    String? checklistUncheckedColor,
    bool? checklistStrikeThrough,
    BulletMarker? bulletMarker,
    String? tableTextColor,
    String? tableHeaderTextColor,
    String? tableHeaderBackgroundColor,
    String? titleBackgroundColor,
    String? titleTextColor,
    String? sectionBackgroundColor,
    String? codeBackgroundColor,
    String? codeTextColor,
    bool? codeHighlightSyntax,
    String? codeFontFamily,
    String? logoPath,
    String? logoPosition,
    int? logoSize,
    String? fontFamily,
    String? footerText,
    bool? footerShowPageNumbers,
    String? footerPosition,
    bool? closingSlideEnabled,
    String? closingSlideMarkdown,
    int? animationDurationMs,
    String? severityCriticalColor,
    String? severityHighColor,
    String? severityMediumColor,
    String? severityLowColor,
    String? severityNoneColor,
    bool clearLogo = false,
  }) {
    return ThemeProfile(
      name: name ?? this.name,
      slideBackgroundColor: slideBackgroundColor ?? this.slideBackgroundColor,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      checklistCheckedColor:
          checklistCheckedColor ?? this.checklistCheckedColor,
      checklistUncheckedColor:
          checklistUncheckedColor ?? this.checklistUncheckedColor,
      checklistStrikeThrough:
          checklistStrikeThrough ?? this.checklistStrikeThrough,
      bulletMarker: bulletMarker ?? this.bulletMarker,
      tableTextColor: tableTextColor ?? this.tableTextColor,
      tableHeaderTextColor: tableHeaderTextColor ?? this.tableHeaderTextColor,
      tableHeaderBackgroundColor:
          tableHeaderBackgroundColor ?? this.tableHeaderBackgroundColor,
      titleBackgroundColor: titleBackgroundColor ?? this.titleBackgroundColor,
      titleTextColor: titleTextColor ?? this.titleTextColor,
      sectionBackgroundColor:
          sectionBackgroundColor ?? this.sectionBackgroundColor,
      codeBackgroundColor: codeBackgroundColor ?? this.codeBackgroundColor,
      codeTextColor: codeTextColor ?? this.codeTextColor,
      codeHighlightSyntax: codeHighlightSyntax ?? this.codeHighlightSyntax,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
      logoPosition: logoPosition ?? this.logoPosition,
      logoSize: logoSize ?? this.logoSize,
      fontFamily: fontFamily ?? this.fontFamily,
      footerText: footerText ?? this.footerText,
      footerShowPageNumbers:
          footerShowPageNumbers ?? this.footerShowPageNumbers,
      footerPosition: footerPosition ?? this.footerPosition,
      closingSlideEnabled: closingSlideEnabled ?? this.closingSlideEnabled,
      closingSlideMarkdown: closingSlideMarkdown ?? this.closingSlideMarkdown,
      animationDurationMs: animationDurationMs ?? this.animationDurationMs,
      severityCriticalColor:
          severityCriticalColor ?? this.severityCriticalColor,
      severityHighColor: severityHighColor ?? this.severityHighColor,
      severityMediumColor: severityMediumColor ?? this.severityMediumColor,
      severityLowColor: severityLowColor ?? this.severityLowColor,
      severityNoneColor: severityNoneColor ?? this.severityNoneColor,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'slideBackgroundColor': slideBackgroundColor,
      'name': name,
      'textColor': textColor,
      'accentColor': accentColor,
      'checklistCheckedColor': checklistCheckedColor,
      'checklistUncheckedColor': checklistUncheckedColor,
      'checklistStrikeThrough': checklistStrikeThrough,
      'bulletMarker': bulletMarker.name,
      'tableTextColor': tableTextColor,
      'tableHeaderTextColor': tableHeaderTextColor,
      'tableHeaderBackgroundColor': tableHeaderBackgroundColor,
      'titleBackgroundColor': titleBackgroundColor,
      'titleTextColor': titleTextColor,
      'sectionBackgroundColor': sectionBackgroundColor,
      'codeBackgroundColor': codeBackgroundColor,
      'codeTextColor': codeTextColor,
      'codeHighlightSyntax': codeHighlightSyntax,
      'codeFontFamily': codeFontFamily,
      'logoPath': logoPath,
      'logoPosition': logoPosition,
      'logoSize': logoSize,
      'fontFamily': fontFamily,
      'footerText': footerText,
      'footerShowPageNumbers': footerShowPageNumbers,
      'footerPosition': footerPosition,
      'closingSlideEnabled': closingSlideEnabled,
      'closingSlideMarkdown': closingSlideMarkdown,
      'animationDurationMs': animationDurationMs,
      'severityCriticalColor': severityCriticalColor,
      'severityHighColor': severityHighColor,
      'severityMediumColor': severityMediumColor,
      'severityLowColor': severityLowColor,
      'severityNoneColor': severityNoneColor,
    };
  }

  /// Validates a deck-supplied colour to a strict `#RRGGBB` literal, falling
  /// back to [fallback] for anything else. Theme profiles travel inside the
  /// deck front matter (base64url JSON) and are interpolated raw into the
  /// `<style>` block of the HTML export and the audience-window inline styles,
  /// so an unvalidated value like `red}</style>…<style>` is a CSS/HTML
  /// injection. The import-safety scanner never sees the base64 payload, so
  /// this is the choke point.
  static String _color(Object? value, String fallback) =>
      normalizeChartColor(value is String ? value : null) ?? fallback;

  /// Whitelists a font family against the offered set; an unknown value can
  /// break out of the `font-family:'…'` declaration, so reject it.
  static String _font(Object? value, List<String> allowed, String fallback) =>
      value is String && allowed.contains(value) ? value : fallback;

  factory ThemeProfile.fromJson(Map<String, Object?> json) {
    return ThemeProfile(
      slideBackgroundColor: _color(json['slideBackgroundColor'], '#FFFFFF'),
      name: json['name'] as String? ?? 'Standaard',
      textColor: _color(json['textColor'], '#222222'),
      accentColor: _color(json['accentColor'], '#2E7D64'),
      checklistCheckedColor: _color(
        json['checklistCheckedColor'] ?? json['accentColor'],
        '#2E7D64',
      ),
      checklistUncheckedColor: _color(
        json['checklistUncheckedColor'],
        '#CBD5E1',
      ),
      checklistStrikeThrough: json['checklistStrikeThrough'] as bool? ?? true,
      bulletMarker: BulletMarker.values.firstWhere(
        (m) => m.name == json['bulletMarker'],
        orElse: () => BulletMarker.dot,
      ),
      tableTextColor: _color(
        json['tableTextColor'] ?? json['textColor'],
        '#222222',
      ),
      tableHeaderTextColor: _color(json['tableHeaderTextColor'], '#FFFFFF'),
      tableHeaderBackgroundColor: _color(
        json['tableHeaderBackgroundColor'] ?? json['accentColor'],
        '#2E7D64',
      ),
      titleBackgroundColor: _color(json['titleBackgroundColor'], '#1C2B47'),
      titleTextColor: _color(json['titleTextColor'], '#FFFFFF'),
      sectionBackgroundColor: _color(json['sectionBackgroundColor'], '#2E7D64'),
      codeBackgroundColor: _color(json['codeBackgroundColor'], '#282C34'),
      codeTextColor: _color(json['codeTextColor'], '#ABB2BF'),
      codeHighlightSyntax: json['codeHighlightSyntax'] as bool? ?? true,
      codeFontFamily: _font(
        json['codeFontFamily'],
        AppSettings.codeFonts,
        'monospace',
      ),
      logoPath: json['logoPath'] as String?,
      logoPosition: json['logoPosition'] as String? ?? 'bottom-right',
      logoSize: (json['logoSize'] as num?)?.round() ?? 96,
      fontFamily: _font(
        json['fontFamily'],
        AppSettings.availableFonts,
        'Arial',
      ),
      footerText: json['footerText'] as String? ?? '',
      footerShowPageNumbers: json['footerShowPageNumbers'] as bool? ?? false,
      footerPosition: json['footerPosition'] as String? ?? 'right',
      closingSlideEnabled: json['closingSlideEnabled'] as bool? ?? false,
      closingSlideMarkdown:
          json['closingSlideMarkdown'] as String? ?? '# Bedankt\n\nVragen?',
      animationDurationMs: clampThemeAnimationDuration(
        (json['animationDurationMs'] as num?)?.round() ??
            kThemeDefaultAnimationDurationMs,
      ),
      severityCriticalColor: _color(json['severityCriticalColor'], '#B91C1C'),
      severityHighColor: _color(json['severityHighColor'], '#EA580C'),
      severityMediumColor: _color(json['severityMediumColor'], '#D97706'),
      severityLowColor: _color(json['severityLowColor'], '#15803D'),
      severityNoneColor: _color(json['severityNoneColor'], '#475569'),
    );
  }
}

enum CockpitVisualStyle {
  authentic,
  classic;

  static CockpitVisualStyle fromName(String? name) =>
      CockpitVisualStyle.values.firstWhere(
        (style) => style.name == name,
        orElse: () => CockpitVisualStyle.authentic,
      );
}

class CockpitColorScheme {
  final String name;
  final bool isBuiltIn;
  final CockpitVisualStyle visualStyle;
  final String good;
  final String warning;
  final String critical;
  final String cold;
  final String sky;
  final String ground;

  const CockpitColorScheme({
    required this.name,
    this.isBuiltIn = false,
    this.visualStyle = CockpitVisualStyle.authentic,
    this.good = '#22C55E',
    this.warning = '#F59E0B',
    this.critical = '#EF4444',
    this.cold = '#3B82F6',
    this.sky = '#2563EB',
    this.ground = '#9A5A22',
  });

  static const standard = CockpitColorScheme(
    name: 'Standaard',
    isBuiltIn: true,
  );

  static const builtIns = [standard];

  CockpitColorScheme copyWith({
    String? name,
    bool? isBuiltIn,
    CockpitVisualStyle? visualStyle,
    String? good,
    String? warning,
    String? critical,
    String? cold,
    String? sky,
    String? ground,
  }) {
    return CockpitColorScheme(
      name: name ?? this.name,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      visualStyle: visualStyle ?? this.visualStyle,
      good: good ?? this.good,
      warning: warning ?? this.warning,
      critical: critical ?? this.critical,
      cold: cold ?? this.cold,
      sky: sky ?? this.sky,
      ground: ground ?? this.ground,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'isBuiltIn': isBuiltIn,
      'visualStyle': visualStyle.name,
      'good': good,
      'warning': warning,
      'critical': critical,
      'cold': cold,
      'sky': sky,
      'ground': ground,
    };
  }

  factory CockpitColorScheme.fromJson(Map<String, Object?> json) {
    return CockpitColorScheme(
      name: json['name'] as String? ?? 'Eigen schema',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      visualStyle: CockpitVisualStyle.fromName(json['visualStyle'] as String?),
      good: json['good'] as String? ?? standard.good,
      warning: json['warning'] as String? ?? standard.warning,
      critical: json['critical'] as String? ?? standard.critical,
      cold: json['cold'] as String? ?? standard.cold,
      sky: json['sky'] as String? ?? standard.sky,
      ground: json['ground'] as String? ?? standard.ground,
    );
  }
}

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
