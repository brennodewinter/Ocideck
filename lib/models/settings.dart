class ThemeProfile {
  final String name;
  final String slideBackgroundColor;
  final String textColor;
  final String accentColor;
  final String tableTextColor;
  final String tableHeaderTextColor;
  final String titleBackgroundColor;
  final String titleTextColor;
  final String sectionBackgroundColor;
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

  const ThemeProfile({
    this.name = 'Standaard',
    this.slideBackgroundColor = '#FFFFFF',
    this.textColor = '#222222',
    this.accentColor = '#2E7D64',
    String? tableTextColor,
    this.tableHeaderTextColor = '#FFFFFF',
    this.titleBackgroundColor = '#1C2B47',
    this.titleTextColor = '#FFFFFF',
    this.sectionBackgroundColor = '#2E7D64',
    this.logoPath,
    this.logoPosition = 'bottom-right',
    this.logoSize = 96,
    this.fontFamily = 'Arial',
    this.footerText = '',
    this.footerShowPageNumbers = false,
    this.footerPosition = 'right',
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
    String? tableTextColor,
    String? tableHeaderTextColor,
    String? titleBackgroundColor,
    String? titleTextColor,
    String? sectionBackgroundColor,
    String? logoPath,
    String? logoPosition,
    int? logoSize,
    String? fontFamily,
    String? footerText,
    bool? footerShowPageNumbers,
    String? footerPosition,
    bool clearLogo = false,
  }) {
    return ThemeProfile(
      name: name ?? this.name,
      slideBackgroundColor: slideBackgroundColor ?? this.slideBackgroundColor,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      tableTextColor: tableTextColor ?? this.tableTextColor,
      tableHeaderTextColor: tableHeaderTextColor ?? this.tableHeaderTextColor,
      titleBackgroundColor: titleBackgroundColor ?? this.titleBackgroundColor,
      titleTextColor: titleTextColor ?? this.titleTextColor,
      sectionBackgroundColor:
          sectionBackgroundColor ?? this.sectionBackgroundColor,
      logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
      logoPosition: logoPosition ?? this.logoPosition,
      logoSize: logoSize ?? this.logoSize,
      fontFamily: fontFamily ?? this.fontFamily,
      footerText: footerText ?? this.footerText,
      footerShowPageNumbers:
          footerShowPageNumbers ?? this.footerShowPageNumbers,
      footerPosition: footerPosition ?? this.footerPosition,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'slideBackgroundColor': slideBackgroundColor,
      'name': name,
      'textColor': textColor,
      'accentColor': accentColor,
      'tableTextColor': tableTextColor,
      'tableHeaderTextColor': tableHeaderTextColor,
      'titleBackgroundColor': titleBackgroundColor,
      'titleTextColor': titleTextColor,
      'sectionBackgroundColor': sectionBackgroundColor,
      'logoPath': logoPath,
      'logoPosition': logoPosition,
      'logoSize': logoSize,
      'fontFamily': fontFamily,
      'footerText': footerText,
      'footerShowPageNumbers': footerShowPageNumbers,
      'footerPosition': footerPosition,
    };
  }

  factory ThemeProfile.fromJson(Map<String, Object?> json) {
    return ThemeProfile(
      slideBackgroundColor:
          json['slideBackgroundColor'] as String? ?? '#FFFFFF',
      name: json['name'] as String? ?? 'Standaard',
      textColor: json['textColor'] as String? ?? '#222222',
      accentColor: json['accentColor'] as String? ?? '#2E7D64',
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
      logoPath: json['logoPath'] as String?,
      logoPosition: json['logoPosition'] as String? ?? 'bottom-right',
      logoSize: (json['logoSize'] as num?)?.round() ?? 96,
      fontFamily: json['fontFamily'] as String? ?? 'Arial',
      footerText: json['footerText'] as String? ?? '',
      footerShowPageNumbers: json['footerShowPageNumbers'] as bool? ?? false,
      footerPosition: json['footerPosition'] as String? ?? 'right',
    );
  }
}

class AppSettings {
  final String? homeDirectory;

  /// Folder where all exports (PDF/PPTX) are written. When null, exports land
  /// next to the source deck (legacy behaviour).
  final String? exportDirectory;
  final List<ThemeProfile> themeProfiles;
  final String selectedThemeProfileName;
  final List<String> recentFiles;

  const AppSettings({
    this.homeDirectory,
    this.exportDirectory,
    this.themeProfiles = const [ThemeProfile()],
    this.selectedThemeProfileName = 'Standaard',
    this.recentFiles = const [],
  });

  ThemeProfile get themeProfile {
    return themeProfiles.firstWhere(
      (p) => p.name == selectedThemeProfileName,
      orElse: () => themeProfiles.first,
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

  AppSettings copyWith({
    String? homeDirectory,
    String? exportDirectory,
    ThemeProfile? themeProfile,
    List<ThemeProfile>? themeProfiles,
    String? selectedThemeProfileName,
    List<String>? recentFiles,
    bool clearHomeDirectory = false,
    bool clearExportDirectory = false,
  }) {
    final nextProfiles = themeProfiles ?? this.themeProfiles;
    return AppSettings(
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
      recentFiles: recentFiles ?? this.recentFiles,
    );
  }
}
