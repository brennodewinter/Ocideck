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

/// OciDeck-compatibiliteitslaag boven het gedeelde uiterlijkprofiel.
///
/// Alleen het productbeleid blijft hier: OciDeck bundelt vier lettertypen en
/// gebruikte historisch Roboto wanneer oudere instellingen nog geen
/// `fontFamily` bevatten. Velden en de JSON-basis komen uit AppFoundation.
class AppAppearanceProfile extends foundation.AppAppearanceProfile {
  /// The interface font family — one of [uiFonts], all bundled so the choice
  /// renders on every platform (including the hardened web build). Default
  /// Roboto.
  const AppAppearanceProfile({
    required super.name,
    super.isBuiltIn = false,
    super.isDark = false,
    required super.primaryColor,
    required super.accentColor,
    required super.backgroundColor,
    required super.surfaceColor,
    required super.textColor,
    required super.mutedTextColor,
    required super.panelColor,
    required super.panelTextColor,
    super.fontFamily = 'Roboto',
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

  @override
  String get fontFamily => super.fontFamily!;

  @override
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
    bool useSystemFont = false,
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
      // OciDeck bundelt en vereist een expliciet font; de productneutrale
      // `useSystemFont`-keuze van de basislaag past niet bij dit contract.
      fontFamily: useSystemFont ? 'Roboto' : fontFamily ?? this.fontFamily,
    );
  }

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    // OciDeck schreef dit veld altijd, ook voor het standaardlettertype.
    'fontFamily': fontFamily,
  };

  factory AppAppearanceProfile.fromJson(Map<String, Object?> json) {
    final shared = foundation.AppAppearanceProfile.fromJson(json);
    return AppAppearanceProfile(
      name: shared.name,
      isBuiltIn: shared.isBuiltIn,
      isDark: shared.isDark,
      primaryColor: shared.primaryColor,
      accentColor: shared.accentColor,
      backgroundColor: shared.backgroundColor,
      surfaceColor: shared.surfaceColor,
      textColor: shared.textColor,
      mutedTextColor: shared.mutedTextColor,
      panelColor: shared.panelColor,
      panelTextColor: shared.panelTextColor,
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
