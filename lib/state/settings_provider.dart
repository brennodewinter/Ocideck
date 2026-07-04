import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/deck.dart' show TlpLevel;
import '../models/settings.dart';
import '../services/secret_store.dart';
import '../utils/log.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier({SecretStore? secretStore})
    : _secrets = secretStore ?? SecretStore(),
      super(const AppSettings()) {
    _load();
  }

  final SecretStore _secrets;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeJson = prefs.getString('themeProfile');
    final profilesJson = prefs.getString('themeProfiles');
    // Verse installatie (geen opgeslagen profielen): de ingebouwde profielen
    // met LibreKAT voorop als standaardselectie. Bestaande prefs — ook het
    // legacy enkelvoudige 'themeProfile' — winnen altijd.
    final loadedProfiles = profilesJson == null
        ? [
            if (themeJson == null)
              ...ThemeProfile.builtIns
            else
              ThemeProfile.fromJson(
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
        prefs.getString('selectedAppAppearanceProfileName') ?? 'Europa';
    final cockpitJson = prefs.getString('cockpitColorSchemes');
    final loadedCockpitSchemes = cockpitJson == null
        ? const <CockpitColorScheme>[]
        : (jsonDecode(cockpitJson) as List)
              .map(
                (item) => CockpitColorScheme.fromJson(
                  Map<String, Object?>.from(item as Map),
                ),
              )
              .toList();
    final cockpitSchemes = _mergeCockpitSchemes(loadedCockpitSchemes);
    final selectedCockpit =
        prefs.getString('selectedCockpitColorSchemeName') ?? 'Standaard';
    final webdavJson = prefs.getString('webdavServer');
    WebdavServer? webdav;
    if (webdavJson != null) {
      try {
        webdav = WebdavServer.fromJson(
          Map<String, Object?>.from(jsonDecode(webdavJson) as Map),
        );
      } catch (e) {
        logWarning('SettingsNotifier: ongeldige webdavServer-prefs', e);
      }
    }
    state = AppSettings(
      languageCode: prefs.getString('languageCode') ?? 'nl',
      homeDirectory: prefs.getString('homeDirectory'),
      exportDirectory: prefs.getString('exportDirectory'),
      themeProfiles: profiles.isEmpty ? ThemeProfile.builtIns : profiles,
      selectedThemeProfileName:
          prefs.getString('selectedThemeProfileName') ?? profiles.first.name,
      appAppearanceProfiles: appearances,
      selectedAppAppearanceProfileName:
          appearances.any((profile) => profile.name == selectedAppearance)
          ? selectedAppearance
          : 'Europa',
      cockpitColorSchemes: cockpitSchemes,
      selectedCockpitColorSchemeName:
          cockpitSchemes.any((scheme) => scheme.name == selectedCockpit)
          ? selectedCockpit
          : 'Standaard',
      recentFiles: _loadRecentFiles(prefs),
      recentFileOrigins: _decodeRecentFileOrigins(
        prefs.getString('recentFileOrigins'),
      ),
      maxReleaseExportTlpKey: prefs.getString('maxReleaseExportTlp'),
      minRequiredExportTlpKey: prefs.getString('minRequiredExportTlp'),
      requireClassificationOnExport:
          prefs.getBool('requireClassificationOnExport') ?? false,
      classificationWatermarkEnabled:
          prefs.getBool('classificationWatermarkEnabled') ?? false,
      uiTextScale: (prefs.getDouble('uiTextScale') ?? 1.0).clamp(1.0, 2.0),
      qualityWarningsOnExport: prefs.getBool('qualityWarningsOnExport') ?? true,
      qualityBlockExportOnErrors:
          prefs.getBool('qualityBlockExportOnErrors') ?? false,
      contrastMinRatio: (prefs.getDouble('contrastMinRatio') ?? 4.5).clamp(
        1.0,
        7.0,
      ),
      allowRemoteMedia: prefs.getBool('allowRemoteMedia') ?? false,
      webdavServer: webdav,
    );
  }

  /// Persisteer een prefs-mutatie. Vangt schrijffouten af en logt ze, zodat een
  /// niet-afgewachte setter-aanroep (zoals een dropdown-`onChanged` in de
  /// settings-dialoog) nooit een onafgevangen async-exceptie oplevert. De state
  /// is op dat punt al bijgewerkt — de UI klopt voor deze sessie; bij een
  /// schrijffout gaat enkel de persistentie verloren (gelogd). Zelfde rationale
  /// als [setWebdavPassword] voor de keychain.
  Future<void> _persist(
    String label,
    Future<void> Function(SharedPreferences prefs) write,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await write(prefs);
    } catch (e, s) {
      logError('SettingsNotifier.$label: prefs-schrijf mislukt', e, s);
    }
  }

  /// Bewaar de WebDAV/Nextcloud-serverconfiguratie (zonder wachtwoord) in
  /// hetzelfde prefs-domein, of `null` om de bron te verwijderen. Wist enkel
  /// deze key — nooit het hele domein (zie geheugen `ocideck-prefs-storage`).
  Future<void> setWebdavServer(WebdavServer? server) async {
    state = server == null
        ? state.copyWith(clearWebdavServer: true)
        : state.copyWith(webdavServer: server);
    await _persist('setWebdavServer', (prefs) async {
      if (server == null) {
        await prefs.remove('webdavServer');
      } else {
        await prefs.setString('webdavServer', jsonEncode(server.toJson()));
      }
    });
  }

  /// Schrijf het WebDAV-wachtwoord versleuteld naar de keychain (gekeyd op
  /// server-URL + gebruikersnaam). Een leeg wachtwoord wist de entry. Geeft
  /// `true` bij succes. Vangt keychain-fouten zelf af (en logt ze) zodat een
  /// niet-afgewachte aanroep — zoals vanuit de settings-dialoog — nooit een
  /// onafgevangen async-exceptie kan opleveren.
  Future<bool> setWebdavPassword(
    String baseUrl,
    String username,
    String password,
  ) async {
    try {
      if (password.isEmpty) {
        await _secrets.deleteWebdavPassword(baseUrl, username);
      } else {
        await _secrets.writeWebdavPassword(baseUrl, username, password);
      }
      return true;
    } catch (e) {
      logWarning('SettingsNotifier.setWebdavPassword: keychain mislukt', e);
      return false;
    }
  }

  /// Lees het opgeslagen WebDAV-wachtwoord uit de keychain, of `null`.
  Future<String?> readWebdavPassword(String baseUrl, String username) {
    return _secrets.readWebdavPassword(baseUrl, username);
  }

  /// Stel het vrijgaveplafond voor de export-gate in (een TLP-sleutel), of
  /// `null` om de gate uit te zetten. Persisteert in hetzelfde prefs-domein.
  Future<void> setMaxReleaseExportTlp(String? key) async {
    state = key == null
        ? state.copyWith(clearMaxReleaseExportTlp: true)
        : state.copyWith(maxReleaseExportTlpKey: key);
    await _persist('setMaxReleaseExportTlp', (prefs) async {
      if (key == null) {
        await prefs.remove('maxReleaseExportTlp');
      } else {
        await prefs.setString('maxReleaseExportTlp', key);
      }
    });
  }

  /// Stel het vereiste minimumniveau voor export in, of `null` om uit te zetten.
  Future<void> setMinRequiredExportTlp(String? key) async {
    state = key == null
        ? state.copyWith(clearMinRequiredExportTlp: true)
        : state.copyWith(minRequiredExportTlpKey: key);
    await _persist('setMinRequiredExportTlp', (prefs) async {
      if (key == null) {
        await prefs.remove('minRequiredExportTlp');
      } else {
        await prefs.setString('minRequiredExportTlp', key);
      }
    });
  }

  Future<void> setRequireClassificationOnExport(bool enabled) async {
    state = state.copyWith(requireClassificationOnExport: enabled);
    await _persist(
      'setRequireClassificationOnExport',
      (prefs) => prefs.setBool('requireClassificationOnExport', enabled),
    );
  }

  Future<void> setClassificationWatermarkEnabled(bool enabled) async {
    state = state.copyWith(classificationWatermarkEnabled: enabled);
    await _persist(
      'setClassificationWatermarkEnabled',
      (prefs) => prefs.setBool('classificationWatermarkEnabled', enabled),
    );
  }

  Future<void> setUiTextScale(double scale) async {
    final clamped = scale.clamp(1.0, 2.0).toDouble();
    state = state.copyWith(uiTextScale: clamped);
    await _persist(
      'setUiTextScale',
      (prefs) => prefs.setDouble('uiTextScale', clamped),
    );
  }

  Future<void> setQualityWarningsOnExport(bool enabled) async {
    state = state.copyWith(qualityWarningsOnExport: enabled);
    await _persist(
      'setQualityWarningsOnExport',
      (prefs) => prefs.setBool('qualityWarningsOnExport', enabled),
    );
  }

  Future<void> setQualityBlockExportOnErrors(bool enabled) async {
    state = state.copyWith(qualityBlockExportOnErrors: enabled);
    await _persist(
      'setQualityBlockExportOnErrors',
      (prefs) => prefs.setBool('qualityBlockExportOnErrors', enabled),
    );
  }

  Future<void> setContrastMinRatio(double ratio) async {
    final clamped = ratio.clamp(1.0, 7.0).toDouble();
    state = state.copyWith(contrastMinRatio: clamped);
    await _persist(
      'setContrastMinRatio',
      (prefs) => prefs.setDouble('contrastMinRatio', clamped),
    );
  }

  /// Sta live laden van online media (URL-afbeeldingen/-video's en embeds) toe,
  /// of zet het uit (fail-closed). Persisteert in hetzelfde prefs-domein.
  Future<void> setAllowRemoteMedia(bool enabled) async {
    state = state.copyWith(allowRemoteMedia: enabled);
    await _persist(
      'setAllowRemoteMedia',
      (prefs) => prefs.setBool('allowRemoteMedia', enabled),
    );
  }

  /// Recente lijst: de nieuwe JSON-opslag ('recentFilesV2') wint; de oude
  /// paden-lijst ('recentFiles') wordt eenmalig als metadata-loze entries
  /// gemigreerd en daarna alleen nog overschreven bij het wegschrijven.
  List<RecentFile> _loadRecentFiles(SharedPreferences prefs) {
    final v2 = RecentFile.decodeList(prefs.getString('recentFilesV2'));
    if (v2.isNotEmpty) return v2;
    return RecentFile.fromLegacyPaths(prefs.getStringList('recentFiles') ?? []);
  }

  Future<void> _persistRecentFiles(List<RecentFile> files) async {
    // Herkomsten volgen de lijst: wat eruit rolt, raakt ook zijn bron kwijt.
    // Een pad dat opnieuw wordt geopend behoudt zijn herkomst — remote
    // opgehaald blijft remote, ook wanneer de lokale kopie later via
    // "Openen…" of de recente lijst wordt geopend.
    final paths = {for (final f in files) f.path};
    final origins = {
      for (final e in state.recentFileOrigins.entries)
        if (paths.contains(e.key)) e.key: e.value,
    };
    state = state.copyWith(recentFiles: files, recentFileOrigins: origins);
    await _persist('_persistRecentFiles', (prefs) async {
      await prefs.setString('recentFilesV2', RecentFile.encodeList(files));
      await prefs.setString('recentFileOrigins', jsonEncode(origins));
    });
  }

  /// Zet [path] bovenaan de recente lijst en ververs de metadata die bij het
  /// openen bekend is. Eerder geregistreerde export-info blijft bewaard.
  Future<void> addRecentFile(
    String path, {
    int? slideCount,
    TlpLevel? tlp,
  }) async {
    final existing = state.recentFiles.where((f) => f.path == path).firstOrNull;
    final entry = (existing ?? RecentFile(path: path)).copyWith(
      openedAt: DateTime.now(),
      slideCount: slideCount,
      tlp: tlp,
    );
    final updated = [
      entry,
      ...state.recentFiles.where((f) => f.path != path),
    ].take(10).toList();
    await _persistRecentFiles(updated);
  }

  /// Onthoud dat [path] zojuist als [formatLabel] ("PDF", "PPTX", "HTML") is
  /// geëxporteerd, zodat de recente lijst dat kan tonen. Alleen bestanden die
  /// al in de lijst staan worden bijgewerkt — exporteren maakt een bestand
  /// niet "recent geopend".
  Future<void> recordRecentFileExport(String path, String formatLabel) async {
    if (!state.recentFiles.any((f) => f.path == path)) return;
    final updated = [
      for (final f in state.recentFiles)
        f.path == path
            ? f.copyWith(
                lastExportFormat: formatLabel,
                lastExportAt: DateTime.now(),
              )
            : f,
    ];
    await _persistRecentFiles(updated);
  }

  /// Haal een pad uit de recente lijst (bijv. omdat het bestand naar de
  /// prullenbak is verplaatst); de herkomst gaat mee.
  Future<void> removeRecentFile(String path) async {
    if (!state.recentFiles.any((f) => f.path == path)) return;
    await _persistRecentFiles(
      state.recentFiles.where((f) => f.path != path).toList(),
    );
  }

  /// Leg vast waar een recent bestand vandaan is gehaald (Nextcloud-server of
  /// import-URL). Aan te roepen ná [addRecentFile]; alleen paden die in de
  /// recente lijst staan krijgen een herkomst, zodat de map niet meegroeit
  /// met verdwenen vermeldingen.
  Future<void> setRecentFileOrigin(String path, String origin) async {
    if (!state.recentFiles.any((f) => f.path == path)) return;
    final origins = {...state.recentFileOrigins, path: origin};
    state = state.copyWith(recentFileOrigins: origins);
    await _persist(
      'setRecentFileOrigin',
      (prefs) => prefs.setString('recentFileOrigins', jsonEncode(origins)),
    );
  }

  static Map<String, String> _decodeRecentFileOrigins(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      logWarning('SettingsNotifier: recentFileOrigins decode failed', e);
      return const {};
    }
  }

  Future<void> setLanguageCode(String code) async {
    state = state.copyWith(languageCode: code);
    await _persist(
      'setLanguageCode',
      (prefs) => prefs.setString('languageCode', code),
    );
  }

  Future<void> setHomeDirectory(String? path) async {
    state = path == null
        ? state.copyWith(clearHomeDirectory: true)
        : state.copyWith(homeDirectory: path);
    await _persist('setHomeDirectory', (prefs) async {
      if (path == null) {
        await prefs.remove('homeDirectory');
      } else {
        await prefs.setString('homeDirectory', path);
      }
    });
  }

  Future<void> setExportDirectory(String? path) async {
    state = path == null
        ? state.copyWith(clearExportDirectory: true)
        : state.copyWith(exportDirectory: path);
    await _persist('setExportDirectory', (prefs) async {
      if (path == null) {
        await prefs.remove('exportDirectory');
      } else {
        await prefs.setString('exportDirectory', path);
      }
    });
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
    await _persist(
      'selectThemeProfile',
      (prefs) => prefs.setString('selectedThemeProfileName', name),
    );
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
    await _persist(
      'selectAppAppearanceProfile',
      (prefs) => prefs.setString('selectedAppAppearanceProfileName', name),
    );
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
      selectedAppAppearanceProfileName: 'Europa',
    );
    await _saveAppearanceProfiles();
  }

  Future<void> selectCockpitColorScheme(String name) async {
    if (!state.cockpitColorSchemes.any((scheme) => scheme.name == name)) {
      return;
    }
    state = state.copyWith(selectedCockpitColorSchemeName: name);
    await _persist(
      'selectCockpitColorScheme',
      (prefs) => prefs.setString('selectedCockpitColorSchemeName', name),
    );
  }

  Future<CockpitColorScheme> createCockpitColorScheme({
    CockpitColorScheme? base,
  }) async {
    final source = base ?? state.cockpitColorScheme;
    final created = source.copyWith(
      name: _uniqueCockpitSchemeName('Eigen schema'),
      isBuiltIn: false,
    );
    state = state.copyWith(
      cockpitColorSchemes: [...state.cockpitColorSchemes, created],
      selectedCockpitColorSchemeName: created.name,
    );
    await _saveCockpitSchemes();
    return created;
  }

  Future<void> saveCockpitColorScheme(
    CockpitColorScheme scheme, {
    required String previousName,
  }) async {
    final existing = state.cockpitColorSchemes.firstWhere(
      (item) => item.name == previousName,
      orElse: () => scheme,
    );
    if (existing.isBuiltIn) return;
    final name = _uniqueCockpitSchemeName(
      scheme.name,
      exceptName: previousName,
    );
    final saved = scheme.copyWith(name: name, isBuiltIn: false);
    final schemes = [
      for (final item in state.cockpitColorSchemes)
        if (item.name == previousName) saved else item,
    ];
    state = state.copyWith(
      cockpitColorSchemes: schemes,
      selectedCockpitColorSchemeName: name,
    );
    await _saveCockpitSchemes();
  }

  Future<void> deleteCockpitColorScheme(String name) async {
    final scheme = state.cockpitColorSchemes.firstWhere(
      (item) => item.name == name,
      orElse: () => CockpitColorScheme.standard,
    );
    if (scheme.isBuiltIn) return;
    final schemes = state.cockpitColorSchemes
        .where((item) => item.name != name)
        .toList();
    state = state.copyWith(
      cockpitColorSchemes: schemes,
      selectedCockpitColorSchemeName: 'Standaard',
    );
    await _saveCockpitSchemes();
  }

  Future<void> _saveCockpitSchemes() async {
    final customSchemes = state.cockpitColorSchemes
        .where((scheme) => !scheme.isBuiltIn)
        .map((scheme) => scheme.toJson())
        .toList();
    await _persist('_saveCockpitSchemes', (prefs) async {
      await prefs.setString('cockpitColorSchemes', jsonEncode(customSchemes));
      await prefs.setString(
        'selectedCockpitColorSchemeName',
        state.selectedCockpitColorSchemeName,
      );
    });
  }

  List<CockpitColorScheme> _mergeCockpitSchemes(
    List<CockpitColorScheme> loaded,
  ) {
    final result = [...CockpitColorScheme.builtIns];
    for (final scheme in loaded.where((scheme) => !scheme.isBuiltIn)) {
      result.add(
        scheme.copyWith(
          name: _uniqueCockpitSchemeName(scheme.name, schemes: result),
          isBuiltIn: false,
        ),
      );
    }
    return result;
  }

  String _uniqueCockpitSchemeName(
    String rawName, {
    List<CockpitColorScheme>? schemes,
    String? exceptName,
  }) {
    final existing = schemes ?? state.cockpitColorSchemes;
    final base = rawName.trim().isEmpty ? 'Eigen schema' : rawName.trim();
    final used = existing
        .map((scheme) => scheme.name)
        .where((name) => name != exceptName)
        .toSet();
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base $index')) {
      index++;
    }
    return '$base $index';
  }

  Future<void> _saveAppearanceProfiles() async {
    final customProfiles = state.appAppearanceProfiles
        .where((profile) => !profile.isBuiltIn)
        .map((profile) => profile.toJson())
        .toList();
    await _persist('_saveAppearanceProfiles', (prefs) async {
      await prefs.setString(
        'appAppearanceProfiles',
        jsonEncode(customProfiles),
      );
      await prefs.setString(
        'selectedAppAppearanceProfileName',
        state.selectedAppAppearanceProfileName,
      );
    });
  }

  Future<void> _saveProfiles() async {
    state = state.copyWith(themeProfiles: _uniqueProfiles(state.themeProfiles));
    await _persist('_saveProfiles', (prefs) async {
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
    });
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
