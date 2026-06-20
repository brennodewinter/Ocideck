import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeJson = prefs.getString('themeProfile');
    final profilesJson = prefs.getString('themeProfiles');
    final loadedProfiles = profilesJson == null
        ? [
            themeJson == null
                ? const ThemeProfile()
                : ThemeProfile.fromJson(
                    Map<String, Object?>.from(jsonDecode(themeJson) as Map),
                  ),
          ]
        : (jsonDecode(profilesJson) as List)
              .map(
                (item) => ThemeProfile.fromJson(
                  Map<String, Object?>.from(item as Map),
                ),
              )
              .toList();
    final profiles = _uniqueProfiles(loadedProfiles);
    final appearanceJson = prefs.getString('appAppearanceProfiles');
    final loadedAppearances = appearanceJson == null
        ? const <AppAppearanceProfile>[]
        : (jsonDecode(appearanceJson) as List)
              .map(
                (item) => AppAppearanceProfile.fromJson(
                  Map<String, Object?>.from(item as Map),
                ),
              )
              .toList();
    final appearances = _mergeAppearanceProfiles(loadedAppearances);
    final selectedAppearance =
        prefs.getString('selectedAppAppearanceProfileName') ?? 'Basic';
    state = AppSettings(
      languageCode: prefs.getString('languageCode') ?? 'nl',
      homeDirectory: prefs.getString('homeDirectory'),
      exportDirectory: prefs.getString('exportDirectory'),
      themeProfiles: profiles.isEmpty ? const [ThemeProfile()] : profiles,
      selectedThemeProfileName:
          prefs.getString('selectedThemeProfileName') ?? profiles.first.name,
      appAppearanceProfiles: appearances,
      selectedAppAppearanceProfileName:
          appearances.any((profile) => profile.name == selectedAppearance)
          ? selectedAppearance
          : 'Basic',
      recentFiles: prefs.getStringList('recentFiles') ?? [],
      maxReleaseExportTlpKey: prefs.getString('maxReleaseExportTlp'),
      minRequiredExportTlpKey: prefs.getString('minRequiredExportTlp'),
      requireClassificationOnExport:
          prefs.getBool('requireClassificationOnExport') ?? false,
      classificationWatermarkEnabled:
          prefs.getBool('classificationWatermarkEnabled') ?? false,
      uiTextScale: (prefs.getDouble('uiTextScale') ?? 1.0).clamp(1.0, 2.0),
      presentationTargetSeconds:
          (prefs.getInt('presentationTargetSeconds') ?? 0).clamp(0, 86400),
      qualityWarningsOnExport: prefs.getBool('qualityWarningsOnExport') ?? true,
      qualityBlockExportOnErrors:
          prefs.getBool('qualityBlockExportOnErrors') ?? false,
    );
  }

  /// Stel het vrijgaveplafond voor de export-gate in (een TLP-sleutel), of
  /// `null` om de gate uit te zetten. Persisteert in hetzelfde prefs-domein.
  Future<void> setMaxReleaseExportTlp(String? key) async {
    state = key == null
        ? state.copyWith(clearMaxReleaseExportTlp: true)
        : state.copyWith(maxReleaseExportTlpKey: key);
    final prefs = await SharedPreferences.getInstance();
    if (key == null) {
      await prefs.remove('maxReleaseExportTlp');
    } else {
      await prefs.setString('maxReleaseExportTlp', key);
    }
  }

  /// Stel het vereiste minimumniveau voor export in, of `null` om uit te zetten.
  Future<void> setMinRequiredExportTlp(String? key) async {
    state = key == null
        ? state.copyWith(clearMinRequiredExportTlp: true)
        : state.copyWith(minRequiredExportTlpKey: key);
    final prefs = await SharedPreferences.getInstance();
    if (key == null) {
      await prefs.remove('minRequiredExportTlp');
    } else {
      await prefs.setString('minRequiredExportTlp', key);
    }
  }

  Future<void> setRequireClassificationOnExport(bool enabled) async {
    state = state.copyWith(requireClassificationOnExport: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('requireClassificationOnExport', enabled);
  }

  Future<void> setClassificationWatermarkEnabled(bool enabled) async {
    state = state.copyWith(classificationWatermarkEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('classificationWatermarkEnabled', enabled);
  }

  Future<void> setUiTextScale(double scale) async {
    final clamped = scale.clamp(1.0, 2.0).toDouble();
    state = state.copyWith(uiTextScale: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('uiTextScale', clamped);
  }

  /// Stel de standaard doeltijd (in seconden) voor de presenter-aftelling in.
  /// 0 = geen aftelling. Begrensd tot een etmaal tegen onzin-invoer.
  Future<void> setPresentationTargetSeconds(int seconds) async {
    final clamped = seconds.clamp(0, 86400);
    state = state.copyWith(presentationTargetSeconds: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('presentationTargetSeconds', clamped);
  }

  Future<void> setQualityWarningsOnExport(bool enabled) async {
    state = state.copyWith(qualityWarningsOnExport: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('qualityWarningsOnExport', enabled);
  }

  Future<void> setQualityBlockExportOnErrors(bool enabled) async {
    state = state.copyWith(qualityBlockExportOnErrors: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('qualityBlockExportOnErrors', enabled);
  }

  Future<void> addRecentFile(String path) async {
    final updated = [
      path,
      ...state.recentFiles.where((f) => f != path),
    ].take(10).toList();
    state = state.copyWith(recentFiles: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recentFiles', updated);
  }

  Future<void> setLanguageCode(String code) async {
    state = state.copyWith(languageCode: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', code);
  }

  Future<void> setHomeDirectory(String? path) async {
    state = path == null
        ? state.copyWith(clearHomeDirectory: true)
        : state.copyWith(homeDirectory: path);
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('homeDirectory');
    } else {
      await prefs.setString('homeDirectory', path);
    }
  }

  Future<void> setExportDirectory(String? path) async {
    state = path == null
        ? state.copyWith(clearExportDirectory: true)
        : state.copyWith(exportDirectory: path);
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('exportDirectory');
    } else {
      await prefs.setString('exportDirectory', path);
    }
  }

  /// Persist edits to the profile currently identified by [previousName],
  /// renaming it in place when the name changed. When no profile matches
  /// [previousName] (e.g. a freshly created one) the profile is added. The
  /// edited profile is selected afterwards.
  Future<void> saveThemeProfile(
    ThemeProfile profile, {
    required String previousName,
  }) async {
    final profileName = _uniqueName(profile.name, exceptName: previousName);
    final renamed = profile.copyWith(name: profileName);
    final exists = state.themeProfiles.any((p) => p.name == previousName);
    final profiles = exists
        ? [
            for (final p in state.themeProfiles)
              if (p.name == previousName) renamed else p,
          ]
        : [...state.themeProfiles, renamed];
    state = state.copyWith(
      themeProfiles: profiles,
      selectedThemeProfileName: profileName,
    );
    await _saveProfiles();
  }

  Future<void> selectThemeProfile(String name) async {
    state = state.copyWith(selectedThemeProfileName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedThemeProfileName', name);
  }

  /// Create a brand-new profile (optionally based on [base]), add it to the
  /// list, select it and persist. Returns the created profile (its name may
  /// have been made unique).
  Future<ThemeProfile> createThemeProfile({ThemeProfile? base}) async {
    final source = base ?? state.themeProfile;
    final name = _uniqueName('Nieuw profiel');
    final created = source.copyWith(name: name);
    state = state.copyWith(
      themeProfiles: [...state.themeProfiles, created],
      selectedThemeProfileName: name,
    );
    await _saveProfiles();
    return created;
  }

  Future<void> deleteThemeProfile(String name) async {
    if (state.themeProfiles.length <= 1) return;
    final profiles = state.themeProfiles.where((p) => p.name != name).toList();
    state = state.copyWith(
      themeProfiles: profiles,
      selectedThemeProfileName: profiles.first.name,
    );
    await _saveProfiles();
  }

  Future<void> selectAppAppearanceProfile(String name) async {
    if (!state.appAppearanceProfiles.any((profile) => profile.name == name)) {
      return;
    }
    state = state.copyWith(selectedAppAppearanceProfileName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedAppAppearanceProfileName', name);
  }

  Future<AppAppearanceProfile> createAppAppearanceProfile({
    AppAppearanceProfile? base,
  }) async {
    final source = base ?? state.appAppearanceProfile;
    final created = source.copyWith(
      name: _uniqueAppearanceName('Eigen thema'),
      isBuiltIn: false,
    );
    state = state.copyWith(
      appAppearanceProfiles: [...state.appAppearanceProfiles, created],
      selectedAppAppearanceProfileName: created.name,
    );
    await _saveAppearanceProfiles();
    return created;
  }

  Future<void> saveAppAppearanceProfile(
    AppAppearanceProfile profile, {
    required String previousName,
  }) async {
    final existing = state.appAppearanceProfiles.firstWhere(
      (item) => item.name == previousName,
      orElse: () => profile,
    );
    if (existing.isBuiltIn) return;
    final name = _uniqueAppearanceName(profile.name, exceptName: previousName);
    final saved = profile.copyWith(name: name, isBuiltIn: false);
    final profiles = [
      for (final item in state.appAppearanceProfiles)
        if (item.name == previousName) saved else item,
    ];
    state = state.copyWith(
      appAppearanceProfiles: profiles,
      selectedAppAppearanceProfileName: name,
    );
    await _saveAppearanceProfiles();
  }

  Future<void> deleteAppAppearanceProfile(String name) async {
    final profile = state.appAppearanceProfiles.firstWhere(
      (item) => item.name == name,
      orElse: () => AppAppearanceProfile.basic,
    );
    if (profile.isBuiltIn) return;
    final profiles = state.appAppearanceProfiles
        .where((item) => item.name != name)
        .toList();
    state = state.copyWith(
      appAppearanceProfiles: profiles,
      selectedAppAppearanceProfileName: 'Basic',
    );
    await _saveAppearanceProfiles();
  }

  Future<void> _saveAppearanceProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final customProfiles = state.appAppearanceProfiles
        .where((profile) => !profile.isBuiltIn)
        .map((profile) => profile.toJson())
        .toList();
    await prefs.setString('appAppearanceProfiles', jsonEncode(customProfiles));
    await prefs.setString(
      'selectedAppAppearanceProfileName',
      state.selectedAppAppearanceProfileName,
    );
  }

  Future<void> _saveProfiles() async {
    state = state.copyWith(themeProfiles: _uniqueProfiles(state.themeProfiles));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'themeProfiles',
      jsonEncode(state.themeProfiles.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(
      'selectedThemeProfileName',
      state.selectedThemeProfileName,
    );
    await prefs.setString(
      'themeProfile',
      jsonEncode(state.themeProfile.toJson()),
    );
  }

  List<ThemeProfile> _uniqueProfiles(List<ThemeProfile> profiles) {
    final result = <ThemeProfile>[];
    for (final profile in profiles) {
      result.add(
        profile.copyWith(name: _uniqueName(profile.name, profiles: result)),
      );
    }
    return result.isEmpty ? const [ThemeProfile()] : result;
  }

  String _uniqueName(
    String rawName, {
    List<ThemeProfile>? profiles,
    String? exceptName,
  }) {
    final existingProfiles = profiles ?? state.themeProfiles;
    final base = rawName.trim().isEmpty ? 'Stijlprofiel' : rawName.trim();
    final used = existingProfiles
        .map((p) => p.name)
        .where((name) => name != exceptName)
        .toSet();
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base $index')) {
      index++;
    }
    return '$base $index';
  }

  List<AppAppearanceProfile> _mergeAppearanceProfiles(
    List<AppAppearanceProfile> loaded,
  ) {
    final result = [...AppAppearanceProfile.builtIns];
    for (final profile in loaded.where((profile) => !profile.isBuiltIn)) {
      result.add(
        profile.copyWith(
          name: _uniqueAppearanceName(profile.name, profiles: result),
          isBuiltIn: false,
        ),
      );
    }
    return result;
  }

  String _uniqueAppearanceName(
    String rawName, {
    List<AppAppearanceProfile>? profiles,
    String? exceptName,
  }) {
    final existingProfiles = profiles ?? state.appAppearanceProfiles;
    final base = rawName.trim().isEmpty ? 'Eigen thema' : rawName.trim();
    final used = existingProfiles
        .map((profile) => profile.name)
        .where((name) => name != exceptName)
        .toSet();
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base $index')) {
      index++;
    }
    return '$base $index';
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (_) => SettingsNotifier(),
);
