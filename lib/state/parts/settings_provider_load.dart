// Part of the settings library — see ../settings_provider.dart.
//
// De bewaakte lezers van [_load]: per-voorkeur type-tolerant, per-item
// lijstdecodering, en quarantaine van geweigerde bronnen onder
// `<sleutel>.refused` zodat een niet begrepen waarde haar bytes behoudt
// (#2888). Top-level net als de andere `_read*`/`_load*`-helpers: de klasse
// groeit niet mee en elke helper is zonder notifier te testen.
part of '../settings_provider.dart';

/// Lees één voorkeurswaarde met het opgeslagen type. Een vreemd type — met de
/// hand aangepaste prefs, of een sleutel die in een oudere versie iets anders
/// bevatte — levert `null` op (de aanroeper valt dan op zijn default terug)
/// in plaats van een TypeError die de hele instellingenlading afbreekt (#2888).
T? _pref<T>(SharedPreferences prefs, String key) {
  try {
    return prefs.get(key) as T?;
  } catch (e) {
    logWarning('SettingsNotifier: pref $key heeft onverwacht type', e);
    return null;
  }
}

/// [_pref] voor stringlijsten: `getStringList` doet meer dan casten, dus die
/// blijft de echte lezer.
List<String>? _prefStringList(SharedPreferences prefs, String key) {
  try {
    return prefs.getStringList(key);
  } catch (e) {
    logWarning('SettingsNotifier: pref $key heeft onverwacht type', e);
    return null;
  }
}

/// Parkeer een onleesbare prefs-waarde onder `<sleutel>.refused`: de ruwe
/// bytes blijven bewaard als herstelkopie, terwijl de gewone sleutel bij de
/// eerstvolgende schrijfactie weer schoon wordt (#2888). Kan het wegschrijven
/// zelf niet, dan is de bron daarmee niet slechter af — de weigering is al
/// gelogd.
Future<void> _quarantineRefused(
  SharedPreferences prefs,
  String key,
  String raw,
) async {
  try {
    await prefs.setString('$key.refused', raw);
  } catch (e) {
    logWarning('SettingsNotifier: quarantaine voor $key mislukt', e);
  }
}

/// Decodeer de stijlonderdelen van [_load]: themaprofielen,
/// verschijningsvormen en cockpitschema's. Elk onderdeel degradeert zelf; de
/// merge/uniek-stappen blijven bij de aanroeper (die zijn klasse-methoden).
/// [refusedSources] bevat per prefs-sleutel de ruwe waarde die geheel of
/// deels geweigerd werd — de aanroeper meldt die en parkeert ze met
/// [_quarantineRefused].
({
  List<ThemeProfile> themeProfiles,
  List<AppAppearanceProfile> appearances,
  List<CockpitColorScheme> cockpitSchemes,
  String? selectedThemeProfileName,
  String? selectedAppearanceName,
  String? selectedCockpitSchemeName,
  CockpitVisualStyle cockpitVisualStyle,
  Map<String, String> refusedSources,
})
_decodeStylePrefs(SharedPreferences prefs) {
  final refusedSources = <String, String>{};

  // Verse installatie (geen opgeslagen profielen): de ingebouwde profielen
  // met LibreKAT voorop als standaardselectie. Bestaande prefs — ook het
  // legacy enkelvoudige 'themeProfile' — winnen altijd.
  final themeJson = _pref<String>(prefs, 'themeProfile');
  final profilesJson = _pref<String>(prefs, 'themeProfiles');
  final refusedProfiles = <Object?>[];
  ThemeProfile? legacy;
  if (profilesJson == null && themeJson != null) {
    try {
      legacy = ThemeProfile.fromJson(
        Map<String, Object?>.from(jsonDecode(themeJson) as Map),
      );
    } catch (e) {
      refusedProfiles.add(themeJson);
      logWarning('SettingsNotifier: onleesbare themeProfile', e);
    }
  }
  final themeProfiles = profilesJson == null
      ? [if (themeJson == null) ...ThemeProfile.builtIns, ?legacy]
      : decodeJsonList(
          profilesJson,
          ThemeProfile.fromJson,
          label: 'themeProfiles',
          refused: refusedProfiles,
        );
  if (refusedProfiles.isNotEmpty) {
    refusedSources[profilesJson == null ? 'themeProfile' : 'themeProfiles'] =
        profilesJson ?? themeJson!;
  }

  final appearanceJson = _pref<String>(prefs, 'appAppearanceProfiles');
  final refusedAppearances = <Object?>[];
  final appearances = decodeJsonList(
    appearanceJson,
    AppAppearanceProfile.fromJson,
    label: 'appAppearanceProfiles',
    refused: refusedAppearances,
  );
  if (refusedAppearances.isNotEmpty && appearanceJson != null) {
    refusedSources['appAppearanceProfiles'] = appearanceJson;
  }

  final cockpitJson = _pref<String>(prefs, 'cockpitColorSchemes');
  final refusedCockpit = <Object?>[];
  final cockpitSchemes = decodeJsonList(
    cockpitJson,
    CockpitColorScheme.fromJson,
    label: 'cockpitColorSchemes',
    refused: refusedCockpit,
  );
  if (refusedCockpit.isNotEmpty && cockpitJson != null) {
    refusedSources['cockpitColorSchemes'] = cockpitJson;
  }

  return (
    themeProfiles: themeProfiles,
    appearances: appearances,
    cockpitSchemes: cockpitSchemes,
    selectedThemeProfileName: _pref<String>(prefs, 'selectedThemeProfileName'),
    selectedAppearanceName: _pref<String>(
      prefs,
      'selectedAppAppearanceProfileName',
    ),
    selectedCockpitSchemeName: _pref<String>(
      prefs,
      'selectedCockpitColorSchemeName',
    ),
    cockpitVisualStyle: CockpitVisualStyle.fromName(
      _pref<String>(prefs, 'cockpitVisualStyle'),
    ),
    refusedSources: refusedSources,
  );
}

/// Lees de opgeslagen AI-instellingen; corrupte data degradeert veilig.
AiSettings _readAiSettings(SharedPreferences prefs) {
  final aiJson = _pref<String>(prefs, 'aiSettings');
  if (aiJson == null) return const AiSettings();
  try {
    return AiSettings.fromJson(
      Map<String, Object?>.from(jsonDecode(aiJson) as Map),
    );
  } catch (e) {
    logWarning('SettingsNotifier: ongeldige aiSettings-prefs', e);
    return const AiSettings();
  }
}

/// Lees de opgeslagen LibrePlan-connector-instellingen; corrupte data
/// degradeert veilig. Spiegelt [_readAiSettings].
LibreplanSettings _readLibreplanSettings(SharedPreferences prefs) {
  final json = _pref<String>(prefs, 'libreplanSettings');
  if (json == null) return const LibreplanSettings();
  try {
    return LibreplanSettings.fromJson(
      Map<String, Object?>.from(jsonDecode(json) as Map),
    );
  } catch (e) {
    logWarning('SettingsNotifier: ongeldige libreplanSettings-prefs', e);
    return const LibreplanSettings();
  }
}
