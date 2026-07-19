// Part of the settings library — see ../settings.dart.
//
// Het uiterlijk van de applicatie zelf, los van het uiterlijk van een
// presentatie. Die twee worden makkelijk door elkaar gehaald: [ThemeProfile]
// stuurt hoe een slide eruitziet en reist mee in het deck, terwijl dit bepaalt
// hoe het programma eromheen oogt en puur van deze installatie is.
//
// Een `part` en geen eigen bestand met imports: de klasse hoort bij
// AppSettings, wordt overal via `models/settings.dart` gehaald, en dat zo
// houden scheelt elke aanroeper een tweede import.
part of '../settings.dart';

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
    // EU-vlagblauw voor de bovenbalk/panelen (huisstijl), i.p.v. near-black.
    panelColor: '#003399',
    panelTextColor: '#FFFFFF',
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
    // Zelfde EU-vlagblauw als de bovenbalk-keuze in het Basic-profiel.
    panelColor: '#003399',
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
