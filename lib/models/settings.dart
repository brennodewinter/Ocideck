import 'chart.dart' show normalizeChartColor;
import 'webdav_settings.dart';

export 'webdav_settings.dart';

/// Glyph used for unordered (bullet) list markers. [dot] is the classic
/// typographic bullet; [paw] swaps in a small cat-paw drawn in the accent
/// colour (OciDeck's mascot). The theme picks a default; a slide may override
/// it (see `Slide.bulletMarkerOverride`).
enum BulletMarker { dot, paw }

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
  }) : tableTextColor = tableTextColor ?? textColor,
       tableHeaderBackgroundColor = tableHeaderBackgroundColor ?? accentColor;

  static const logoPositions = [
    'top-left',
    'top-right',
    'bottom-left',
    'bottom-right',
  ];

  static const footerPositions = ['left', 'center', 'right'];

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
      fontFamily: _font(json['fontFamily'], AppSettings.availableFonts, 'Arial'),
      footerText: json['footerText'] as String? ?? '',
      footerShowPageNumbers: json['footerShowPageNumbers'] as bool? ?? false,
      footerPosition: json['footerPosition'] as String? ?? 'right',
      closingSlideEnabled: json['closingSlideEnabled'] as bool? ?? false,
      closingSlideMarkdown:
          json['closingSlideMarkdown'] as String? ?? '# Bedankt\n\nVragen?',
    );
  }
}

class AppAppearanceProfile {
  final String name;
  final bool isBuiltIn;
  final bool isDark;
  final String primaryColor;
  final String accentColor;
  final String backgroundColor;
  final String surfaceColor;
  final String textColor;
  final String mutedTextColor;
  final String panelColor;
  final String panelTextColor;

  /// The interface font family — one of [uiFonts], all bundled so the choice
  /// renders on every platform (including the hardened web build). Default
  /// Roboto.
  final String fontFamily;

  const AppAppearanceProfile({
    required this.name,
    this.isBuiltIn = false,
    this.isDark = false,
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.mutedTextColor,
    required this.panelColor,
    required this.panelTextColor,
    this.fontFamily = 'Roboto',
  });

  /// Interface fonts the user can pick for the app UI. All bundled in
  /// pubspec.yaml so they work on desktop, the hardened web build, and export.
  static const uiFonts = ['Roboto', 'Inter', 'Lora', 'EB Garamond'];

  static const basic = AppAppearanceProfile(
    name: 'Basic',
    isBuiltIn: true,
    primaryColor: '#1C2B47',
    accentColor: '#2563EB',
    backgroundColor: '#F8F9FA',
    surfaceColor: '#FFFFFF',
    textColor: '#1E293B',
    mutedTextColor: '#64748B',
    panelColor: '#1E2028',
    panelTextColor: '#E2E8F0',
  );

  static const europa = AppAppearanceProfile(
    name: 'Europa',
    isBuiltIn: true,
    primaryColor: '#003399',
    accentColor: '#FFCC00',
    backgroundColor: '#F4F7FC',
    surfaceColor: '#FFFFFF',
    textColor: '#003399',
    mutedTextColor: '#5D6B85',
    panelColor: '#00266F',
    panelTextColor: '#FFFFFF',
  );

  static const dark = AppAppearanceProfile(
    name: 'Donker',
    isBuiltIn: true,
    isDark: true,
    primaryColor: '#111827',
    accentColor: '#60A5FA',
    backgroundColor: '#0F172A',
    surfaceColor: '#1E293B',
    textColor: '#F1F5F9',
    mutedTextColor: '#94A3B8',
    panelColor: '#090E1A',
    panelTextColor: '#E2E8F0',
  );

  static const builtIns = [basic, europa, dark];

  AppAppearanceProfile copyWith({
    String? name,
    bool? isBuiltIn,
    bool? isDark,
    String? primaryColor,
    String? accentColor,
    String? backgroundColor,
    String? surfaceColor,
    String? textColor,
    String? mutedTextColor,
    String? panelColor,
    String? panelTextColor,
    String? fontFamily,
  }) {
    return AppAppearanceProfile(
      name: name ?? this.name,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      isDark: isDark ?? this.isDark,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      textColor: textColor ?? this.textColor,
      mutedTextColor: mutedTextColor ?? this.mutedTextColor,
      panelColor: panelColor ?? this.panelColor,
      panelTextColor: panelTextColor ?? this.panelTextColor,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'isBuiltIn': isBuiltIn,
      'isDark': isDark,
      'primaryColor': primaryColor,
      'accentColor': accentColor,
      'backgroundColor': backgroundColor,
      'surfaceColor': surfaceColor,
      'textColor': textColor,
      'mutedTextColor': mutedTextColor,
      'panelColor': panelColor,
      'panelTextColor': panelTextColor,
      'fontFamily': fontFamily,
    };
  }

  factory AppAppearanceProfile.fromJson(Map<String, Object?> json) {
    return AppAppearanceProfile(
      name: json['name'] as String? ?? 'Eigen thema',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      isDark: json['isDark'] as bool? ?? false,
      primaryColor: json['primaryColor'] as String? ?? basic.primaryColor,
      accentColor: json['accentColor'] as String? ?? basic.accentColor,
      backgroundColor:
          json['backgroundColor'] as String? ?? basic.backgroundColor,
      surfaceColor: json['surfaceColor'] as String? ?? basic.surfaceColor,
      textColor: json['textColor'] as String? ?? basic.textColor,
      mutedTextColor: json['mutedTextColor'] as String? ?? basic.mutedTextColor,
      panelColor: json['panelColor'] as String? ?? basic.panelColor,
      panelTextColor: json['panelTextColor'] as String? ?? basic.panelTextColor,
      fontFamily: json['fontFamily'] as String? ?? 'Roboto',
    );
  }
}

/// A named set of cockpit instrument colours. The status colours map to the
/// gauge zones: [good] (default green), [warning] (amber), [critical] (red) and
/// [cold] (blue, used below a meter's lower bound). [sky] and [ground] colour
/// the artificial horizon. Users can create and name several schemes
/// ("variants"); the active one is selected globally in [AppSettings], just like
/// [ThemeProfile]/[AppAppearanceProfile]. The defaults match the values the
/// instruments used when colours were hardcoded.
class CockpitColorScheme {
  final String name;
  final bool isBuiltIn;
  final String good;
  final String warning;
  final String critical;
  final String cold;
  final String sky;
  final String ground;

  const CockpitColorScheme({
    required this.name,
    this.isBuiltIn = false,
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
  final String? homeDirectory;

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
  final List<String> recentFiles;

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

  /// Scale factor for all interface text (1.0–2.0), on top of the system
  /// text scaling. The slide canvas itself is never scaled: slides are a
  /// fixed 16:9 design surface. WCAG 1.4.4 asks for text resizing up to 200%.
  final double uiTextScale;

  /// Toon een waarschuwing vóór export wanneer de slide-kwaliteitscontrole
  /// problemen vindt (alt-tekst, contrast, tekstdichtheid).
  final bool qualityWarningsOnExport;

  /// Blokkeer export volledig wanneer de kwaliteitscontrole fouten vindt.
  final bool qualityBlockExportOnErrors;

  /// Of online media (afbeeldingen/video's via URL en YouTube/Vimeo-embeds)
  /// live mag worden geladen. Standaard uit (fail-closed): een geopende deck
  /// van een ander kan dan niet ongevraagd naar buiten "bellen" of pixels van
  /// derden laden. De gebruiker zet dit bewust aan in de instellingen.
  final bool allowRemoteMedia;

  /// Toon na afloop van een presentatie het oefenoverzicht (bestede tijd per
  /// slide). De tijd wordt altijd gemeten; dit bepaalt enkel of het scherm
  /// verschijnt. Standaard aan — backward compatible met het oude gedrag.
  final bool showRehearsalSummary;

  /// Geconfigureerde WebDAV/Nextcloud-bron, of `null` wanneer geen server is
  /// ingesteld. Bevat nooit het wachtwoord (dat staat in de keychain).
  final WebdavServer? webdavServer;

  const AppSettings({
    this.languageCode = 'nl',
    this.homeDirectory,
    this.exportDirectory,
    this.themeProfiles = const [ThemeProfile()],
    this.selectedThemeProfileName = 'Standaard',
    this.appAppearanceProfiles = AppAppearanceProfile.builtIns,
    this.selectedAppAppearanceProfileName = 'Basic',
    this.cockpitColorSchemes = CockpitColorScheme.builtIns,
    this.selectedCockpitColorSchemeName = 'Standaard',
    this.recentFiles = const [],
    this.maxReleaseExportTlpKey,
    this.minRequiredExportTlpKey,
    this.requireClassificationOnExport = false,
    this.classificationWatermarkEnabled = false,
    this.uiTextScale = 1.0,
    this.qualityWarningsOnExport = true,
    this.qualityBlockExportOnErrors = false,
    this.allowRemoteMedia = false,
    this.showRehearsalSummary = true,
    this.webdavServer,
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
    if (cockpitColorSchemes.isEmpty) return CockpitColorScheme.standard;
    return cockpitColorSchemes.firstWhere(
      (s) => s.name == selectedCockpitColorSchemeName,
      orElse: () => cockpitColorSchemes.first,
    );
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
    String? homeDirectory,
    String? exportDirectory,
    ThemeProfile? themeProfile,
    List<ThemeProfile>? themeProfiles,
    String? selectedThemeProfileName,
    List<AppAppearanceProfile>? appAppearanceProfiles,
    String? selectedAppAppearanceProfileName,
    List<CockpitColorScheme>? cockpitColorSchemes,
    String? selectedCockpitColorSchemeName,
    List<String>? recentFiles,
    String? maxReleaseExportTlpKey,
    String? minRequiredExportTlpKey,
    bool? requireClassificationOnExport,
    bool? classificationWatermarkEnabled,
    double? uiTextScale,
    bool? qualityWarningsOnExport,
    bool? qualityBlockExportOnErrors,
    bool? allowRemoteMedia,
    bool? showRehearsalSummary,
    WebdavServer? webdavServer,
    bool clearHomeDirectory = false,
    bool clearExportDirectory = false,
    bool clearMaxReleaseExportTlp = false,
    bool clearMinRequiredExportTlp = false,
    bool clearWebdavServer = false,
  }) {
    final nextProfiles = themeProfiles ?? this.themeProfiles;
    return AppSettings(
      languageCode: languageCode ?? this.languageCode,
      homeDirectory: clearHomeDirectory
          ? null
          : (homeDirectory ?? this.homeDirectory),
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
      recentFiles: recentFiles ?? this.recentFiles,
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
      uiTextScale: uiTextScale ?? this.uiTextScale,
      qualityWarningsOnExport:
          qualityWarningsOnExport ?? this.qualityWarningsOnExport,
      qualityBlockExportOnErrors:
          qualityBlockExportOnErrors ?? this.qualityBlockExportOnErrors,
      allowRemoteMedia: allowRemoteMedia ?? this.allowRemoteMedia,
      showRehearsalSummary: showRehearsalSummary ?? this.showRehearsalSummary,
      webdavServer: clearWebdavServer
          ? null
          : (webdavServer ?? this.webdavServer),
    );
  }
}
