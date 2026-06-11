class ThemeProfile {
  final String name;
  final String slideBackgroundColor;
  final String textColor;
  final String accentColor;
  final String checklistCheckedColor;
  final String checklistUncheckedColor;
  final bool checklistStrikeThrough;
  final String tableTextColor;
  final String tableHeaderTextColor;
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
    String? tableTextColor,
    this.tableHeaderTextColor = '#FFFFFF',
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
  }) : tableTextColor = tableTextColor ?? textColor;

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
    String? tableTextColor,
    String? tableHeaderTextColor,
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
      tableTextColor: tableTextColor ?? this.tableTextColor,
      tableHeaderTextColor: tableHeaderTextColor ?? this.tableHeaderTextColor,
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
      'tableTextColor': tableTextColor,
      'tableHeaderTextColor': tableHeaderTextColor,
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

  factory ThemeProfile.fromJson(Map<String, Object?> json) {
    return ThemeProfile(
      slideBackgroundColor:
          json['slideBackgroundColor'] as String? ?? '#FFFFFF',
      name: json['name'] as String? ?? 'Standaard',
      textColor: json['textColor'] as String? ?? '#222222',
      accentColor: json['accentColor'] as String? ?? '#2E7D64',
      checklistCheckedColor:
          json['checklistCheckedColor'] as String? ??
          json['accentColor'] as String? ??
          '#2E7D64',
      checklistUncheckedColor:
          json['checklistUncheckedColor'] as String? ?? '#CBD5E1',
      checklistStrikeThrough: json['checklistStrikeThrough'] as bool? ?? true,
      tableTextColor:
          json['tableTextColor'] as String? ??
          json['textColor'] as String? ??
          '#222222',
      tableHeaderTextColor:
          json['tableHeaderTextColor'] as String? ?? '#FFFFFF',
      titleBackgroundColor:
          json['titleBackgroundColor'] as String? ?? '#1C2B47',
      titleTextColor: json['titleTextColor'] as String? ?? '#FFFFFF',
      sectionBackgroundColor:
          json['sectionBackgroundColor'] as String? ?? '#2E7D64',
      codeBackgroundColor: json['codeBackgroundColor'] as String? ?? '#282C34',
      codeTextColor: json['codeTextColor'] as String? ?? '#ABB2BF',
      codeHighlightSyntax: json['codeHighlightSyntax'] as bool? ?? true,
      codeFontFamily: json['codeFontFamily'] as String? ?? 'monospace',
      logoPath: json['logoPath'] as String?,
      logoPosition: json['logoPosition'] as String? ?? 'bottom-right',
      logoSize: (json['logoSize'] as num?)?.round() ?? 96,
      fontFamily: json['fontFamily'] as String? ?? 'Arial',
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
  });

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
    textColor: '#17233D',
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
  final List<String> recentFiles;

  /// Scale factor for all interface text (1.0–2.0), on top of the system
  /// text scaling. The slide canvas itself is never scaled: slides are a
  /// fixed 16:9 design surface. WCAG 1.4.4 asks for text resizing up to 200%.
  final double uiTextScale;

  const AppSettings({
    this.languageCode = 'nl',
    this.homeDirectory,
    this.exportDirectory,
    this.themeProfiles = const [ThemeProfile()],
    this.selectedThemeProfileName = 'Standaard',
    this.appAppearanceProfiles = AppAppearanceProfile.builtIns,
    this.selectedAppAppearanceProfileName = 'Basic',
    this.recentFiles = const [],
    this.uiTextScale = 1.0,
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
    List<String>? recentFiles,
    double? uiTextScale,
    bool clearHomeDirectory = false,
    bool clearExportDirectory = false,
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
      recentFiles: recentFiles ?? this.recentFiles,
      uiTextScale: uiTextScale ?? this.uiTextScale,
    );
  }
}
