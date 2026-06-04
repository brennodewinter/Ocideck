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
    state = AppSettings(
      languageCode: prefs.getString('languageCode') ?? 'nl',
      homeDirectory: prefs.getString('homeDirectory'),
      exportDirectory: prefs.getString('exportDirectory'),
      themeProfiles: profiles.isEmpty ? const [ThemeProfile()] : profiles,
      selectedThemeProfileName:
          prefs.getString('selectedThemeProfileName') ?? profiles.first.name,
      recentFiles: prefs.getStringList('recentFiles') ?? [],
    );
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
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (_) => SettingsNotifier(),
);
