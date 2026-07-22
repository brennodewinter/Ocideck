import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart' show AppLocalizations;
import '../models/deck.dart' show TlpLevel;
import '../models/privacy_disposition.dart';
import '../models/privacy_finding.dart';
import '../models/settings.dart';
import '../models/storage_connection.dart';
import '../services/disk_traces.dart';
import '../services/privacy/privacy_regions.dart';
import '../services/recovery_service.dart';
import '../services/secret_store.dart';
import '../utils/log.dart';

part 'parts/settings_provider_connections.dart';
part 'parts/settings_provider_git.dart';
part 'parts/settings_provider_privacy.dart';
part 'parts/settings_provider_traces.dart';

/// Vaste startwaarde voor de testsuite, in plaats van de taal van de machine.
///
/// Zonder dit hangt de uitkomst van elke widgettest af van de landinstelling
/// van wie hem draait: de suite zoekt Nederlandse knopteksten, en op een
/// Engelse machine zijn die er niet. `test/flutter_test_config.dart` zet dit
/// één keer voor de hele suite. In productie blijft het null.
@visibleForTesting
String? debugStartupLanguageOverride;

/// De taal voor een installatie die er nog geen heeft.
///
/// Staat los van [SettingsNotifier] omdat het geen toestand is maar een vraag
/// aan het platform, en omdat de klasse aan haar regelplafond zit.
String _startupLanguageCode() {
  return debugStartupLanguageOverride ??
      AppLocalizations.preferredLanguageCode(
        PlatformDispatcher.instance.locales,
      );
}

/// The single owner of application-wide settings: everything in [AppSettings],
/// persisted in one `shared_preferences` domain.
///
/// Two properties this class must keep. **A read never blocks the UI**: the
/// notifier starts from defaults and fills in from disk asynchronously, so a
/// slow or unreadable preference store degrades to "the default is in force"
/// rather than to a frozen app. And **a failed write loses persistence, not the
/// session** — the in-memory state is updated first, so a preference the user
/// just set still applies even when it could not be stored.
///
/// Settings that are somebody's credentials do not live here; they go through
/// `secret_store.dart` into the OS keychain, and only the non-secret half of a
/// storage connection is kept in [AppSettings].
///
/// The class is split across `parts/settings_provider_*.dart` by subject
/// (connections, git, privacy, traces). Those are the same class — add a
/// setting beside its neighbours rather than here.
class SettingsNotifier extends StateNotifier<AppSettings> {
  /// De huidige instellingen, leesbaar en schrijfbaar vanuit een `part`.
  ///
  /// `state` is protected en dus onbereikbaar voor een extension in een
  /// part-bestand — precies het patroon dat `DeckNotifier` al gebruikt.
  AppSettings get currentState => state;
  set currentState(AppSettings value) => state = value;

  SettingsNotifier({SecretStore? secretStore, DiskTraces? diskTraces})
    : _secrets = secretStore ?? SecretStore(),
      _diskTraces = diskTraces ?? DiskTraces(),
      super(const AppSettings()) {
    _load();
  }

  final SecretStore _secrets;

  /// De opruimer voor wat een verbinding op schijf achterlaat. Injecteerbaar,
  /// zodat een test in een tijdelijke map kan kijken in plaats van in de echte
  /// app-supportmap van de gebruiker die de test draait.
  final DiskTraces _diskTraces;

  /// Broadcast: één event (een oplopend volgnummer) per mislukte prefs-schrijf,
  /// zie [_persist]. De app-shell luistert hierop en toont een niet-blokkerende
  /// melding. Het volgnummer garandeert dat opeenvolgende fouten distinct zijn,
  /// zodat de [settingsPersistErrorProvider] ze niet als "ongewijzigd" samenvouwt.
  final StreamController<int> _persistErrors =
      StreamController<int>.broadcast();
  int _persistErrorSeq = 0;

  /// Stroom van persist-fouten voor de UI. Zie [settingsPersistErrorProvider].
  Stream<int> get persistErrors => _persistErrors.stream;

  /// Broadcast: één event per mislukte keychain-schrijf. Bewust géén tak van
  /// [_persistErrors]: een mislukte prefs-schrijf kost een instelling, maar een
  /// mislukte keychain-schrijf kost een wáchtwoord — en die fout komt later
  /// terug als "verbinding geweigerd", waar de gebruiker zijn wachtwoord gaat
  /// zitten controleren dat nooit is opgeslagen. Dat is precies het spoor waar
  /// hij niets te zoeken heeft, dus verdient het een eigen melding.
  final StreamController<int> _secretErrors = StreamController<int>.broadcast();
  int _secretErrorSeq = 0;

  /// Stroom van keychain-fouten voor de UI. Zie [settingsSecretErrorProvider].
  Stream<int> get secretErrors => _secretErrors.stream;

  /// Meld dat een geheim niet kon worden weggeschreven. Log + signaal; de
  /// aanroeper krijgt daarnaast `false` terug zodat ook een afwachtende
  /// aanroeper (de settings-dialoog) het weet.
  void _reportSecretFailure(String label, Object e) {
    logWarning('SettingsNotifier.$label: keychain mislukt', e);
    if (!_secretErrors.isClosed) _secretErrors.add(++_secretErrorSeq);
  }

  @override
  void dispose() {
    _persistErrors.close();
    _secretErrors.close();
    super.dispose();
  }

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
    final aiJson = prefs.getString('aiSettings');
    var ai = const AiSettings();
    if (aiJson != null) {
      try {
        ai = AiSettings.fromJson(
          Map<String, Object?>.from(jsonDecode(aiJson) as Map),
        );
      } catch (e) {
        logWarning('SettingsNotifier: ongeldige aiSettings-prefs', e);
      }
    }
    // Het laden is asynchroon; een scope die in die tussentijd verdwijnt — een
    // venster dat sluit, een test die afloopt — mag geen "gebruikt na dispose"
    // opleveren. Er valt dan ook niets meer bij te werken.
    if (!mounted) return;
    state = AppSettings(
      languageCode: prefs.getString('languageCode') ?? _startupLanguageCode(),
      connections: _loadConnections(prefs),
      customChecklists: ChecklistTemplate.decodeList(
        prefs.getString('customChecklists'),
      ),
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
      // Standaard AAN: een privacycontrole die je eerst moet aanzetten, helpt
      // precies de mensen niet die niet weten dat ze hem nodig hebben.
      privacyChecksEnabled: prefs.getBool('privacyChecksEnabled') ?? true,
      privacyImageFaceDetection:
          prefs.getBool('privacyImageFaceDetection') ?? true,
      // Standaard uit: aanzetten verandert wat `qualityBlockExportOnErrors`
      // betekent, en dat mag niet gebeuren zonder dat iemand ernaar greep.
      privacyStrictSeverity: prefs.getBool('privacyStrictSeverity') ?? false,
      // Nooit eerder opgeslagen → de standaard-uitgezette regels. Een lege lijst
      // die de gebruiker zelf heeft gemaakt, blijft leeg: dat is een keuze.
      privacyDisabledRules:
          prefs.getStringList('privacyDisabledRules')?.toSet() ??
          defaultDisabledPrivacyRules,
      // Nooit eerder opgeslagen → heel Europa. Een lege verzameling die de
      // gebruiker zelf heeft gemaakt blijft leeg: dan draait alleen de
      // universele laag, en dat is een geldige keuze.
      privacyRegions:
          prefs.getStringList('privacyRegions')?.toSet() ??
          defaultPrivacyRegions,
      privacyExportGate: PrivacyExportGateX.fromKey(
        prefs.getString('privacyExportGate'),
      ),
      // De echte plek is de sleutelbos; dit is de nog niet gemigreerde
      // waarde, die meteen beschikbaar is. Zie [adoptPrivacyOwnIdentity],
      // dat de sleutelbos náást het laden raadpleegt.
      privacyOwnIdentity:
          prefs.getString(SettingsPrivacy.legacyOwnIdentityKey) ?? '',
      uiTextScale: (prefs.getDouble('uiTextScale') ?? 1.0).clamp(1.0, 2.0),
      docReaderTextScale: (prefs.getDouble('docReaderTextScale') ?? 1.0).clamp(
        0.8,
        1.8,
      ),
      qualityWarningsOnExport: prefs.getBool('qualityWarningsOnExport') ?? true,
      qualityBlockExportOnErrors:
          prefs.getBool('qualityBlockExportOnErrors') ?? false,
      contrastMinRatio: (prefs.getDouble('contrastMinRatio') ?? 4.5).clamp(
        1.0,
        7.0,
      ),
      allowRemoteMedia: prefs.getBool('allowRemoteMedia') ?? false,
      allowCveLookup: prefs.getBool('allowCveLookup') ?? false,
      cveApiBaseUrl:
          prefs.getString('cveApiBaseUrl') ?? AppSettings.defaultCveApiBaseUrl,
      aiSettings: ai,
    );
    _persistedLogoPaths = _referencedLogoPaths;
    // Niet awaiten: de sleutelbos mag de instellingen niet ophouden.
    unawaited(adoptPrivacyOwnIdentity(prefs));
    // De opstartveger voor verweesde stijl-logo's hoort hier en niet in de
    // shell: hij vergelijkt tegen de profielenlijst, en die is pas op dit punt
    // geladen. Een veger die eerder draait ziet de ingebouwde profielen, houdt
    // elk geïmporteerd logo voor verweesd, en gooit er een weg dat gewoon in
    // gebruik is.
    unawaited(pruneOrphanStyleLogos());
  }

  /// Persisteer een prefs-mutatie. Vangt schrijffouten af en logt ze, zodat een
  /// niet-afgewachte setter-aanroep (zoals een dropdown-`onChanged` in de
  /// settings-dialoog) nooit een onafgevangen async-exceptie oplevert. De state
  /// is op dat punt al bijgewerkt — de UI klopt voor deze sessie; bij een
  /// schrijffout gaat enkel de persistentie verloren (gelogd). Zelfde rationale
  /// als [setWebdavPassword] voor de keychain.
  /// Haal de inloggegevens uit een herkomst-URL vóórdat die bewaard wordt.
  ///
  /// De herkomst is niets dan een label onder de wolk-badge in de recente
  /// lijst, maar hij gaat wél onversleuteld naar het prefs-domein — en een
  /// import-URL kan het `gebruiker:wachtwoord@`-deel dragen dat een URL vóór de
  /// host toestaat (het `userInfo`-veld). Dan staat er een wachtwoord in gewone
  /// instellingen, precies wat `SecretStore` bestaat om te voorkomen. Het
  /// gebruikersdeel wordt vervangen door `***`, zodat de gebruiker nog steeds
  /// ziet dát er inloggegevens in de link zaten. ASCII, en geen `…`:
  /// `Uri.replace` procent-codeert dat tot `%E2%80%A6`, wat er in de lijst
  /// uitziet als rommel in plaats van als een weggelaten geheim.
  ///
  /// Alleen dit, en niet de query: een sleutel in de query is niet als zodanig
  /// herkenbaar, en de hele query weglaten maakt van twee verschillende
  /// herkomsten één regel.
  @visibleForTesting
  static String scrubbedOrigin(String origin) {
    final uri = Uri.tryParse(origin.trim());
    if (uri == null || !uri.hasAuthority || uri.userInfo.isEmpty) return origin;
    return uri.replace(userInfo: '***').toString();
  }

  Future<void> _persist(
    String label,
    Future<void> Function(SharedPreferences prefs) write,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await write(prefs);
    } catch (e, s) {
      logError('SettingsNotifier.$label: prefs-schrijf mislukt', e, s);
      if (!_persistErrors.isClosed) _persistErrors.add(++_persistErrorSeq);
    }
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
      _reportSecretFailure('setWebdavPassword', e);
      return false;
    }
  }

  /// Lees het opgeslagen WebDAV-wachtwoord uit de keychain, of `null`.
  Future<String?> readWebdavPassword(String baseUrl, String username) {
    return _secrets.readWebdavPassword(baseUrl, username);
  }

  /// Schrijf de S3 secret access key versleuteld naar de keychain (gekeyd op
  /// endpoint + access key id). Een lege waarde wist de entry. Zelfde
  /// foutafhandeling als [setWebdavPassword], en om dezelfde reden.
  Future<bool> setS3SecretKey(
    String endpoint,
    String accessKeyId,
    String secretKey,
  ) async {
    try {
      if (secretKey.isEmpty) {
        await _secrets.deleteS3SecretKey(endpoint, accessKeyId);
      } else {
        await _secrets.writeS3SecretKey(endpoint, accessKeyId, secretKey);
      }
      return true;
    } catch (e) {
      _reportSecretFailure('setS3SecretKey', e);
      return false;
    }
  }

  /// Lees de opgeslagen S3 secret access key uit de keychain, of `null`.
  Future<String?> readS3SecretKey(String endpoint, String accessKeyId) {
    return _secrets.readS3SecretKey(endpoint, accessKeyId);
  }

  /// Bewaar de instellingen van de optionele AI-backend (zonder API-sleutel) in
  /// hetzelfde prefs-domein. Wist enkel deze key — nooit het hele domein (zie
  /// geheugen `ocideck-prefs-storage`).
  Future<void> setAiSettings(AiSettings settings) async {
    state = state.copyWith(aiSettings: settings);
    await _persist('setAiSettings', (prefs) async {
      await prefs.setString('aiSettings', jsonEncode(settings.toJson()));
    });
  }

  /// Schrijf de optionele AI-API-sleutel versleuteld naar de keychain (gekeyd
  /// op de basis-URL). Een lege sleutel wist de entry. Vangt keychain-fouten
  /// zelf af (en logt ze) zodat een niet-afgewachte aanroep — zoals vanuit de
  /// settings-dialoog — nooit een onafgevangen async-exceptie oplevert.
  Future<bool> setAiApiKey(String baseUrl, String apiKey) async {
    try {
      if (apiKey.isEmpty) {
        await _secrets.deleteAiApiKey(baseUrl);
      } else {
        await _secrets.writeAiApiKey(baseUrl, apiKey);
      }
      return true;
    } catch (e) {
      _reportSecretFailure('setAiApiKey', e);
      return false;
    }
  }

  /// Lees de opgeslagen AI-API-sleutel uit de keychain, of `null`.
  Future<String?> readAiApiKey(String baseUrl) {
    return _secrets.readAiApiKey(baseUrl);
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

  /// Ondergrens, bovengrens en stapgrootte voor de documentatielezer-schaal;
  /// gedeeld met de knoppen in de lezer zodat clampen en stappen consistent zijn.
  static const double docReaderTextScaleMin = 0.8;
  static const double docReaderTextScaleMax = 1.8;
  static const double docReaderTextScaleStep = 0.1;

  Future<void> setDocReaderTextScale(double scale) async {
    final clamped = scale
        .clamp(docReaderTextScaleMin, docReaderTextScaleMax)
        .toDouble();
    if (clamped == state.docReaderTextScale) return;
    state = state.copyWith(docReaderTextScale: clamped);
    await _persist(
      'setDocReaderTextScale',
      (prefs) => prefs.setDouble('docReaderTextScale', clamped),
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

  /// Sta het online opzoeken van CVE's toe, of zet het uit (fail-closed).
  Future<void> setAllowCveLookup(bool enabled) async {
    state = state.copyWith(allowCveLookup: enabled);
    await _persist(
      'setAllowCveLookup',
      (prefs) => prefs.setBool('allowCveLookup', enabled),
    );
  }

  /// Stel de CVE-mirror-basis-URL in; leeg valt terug op de standaard.
  Future<void> setCveApiBaseUrl(String url) async {
    final value = url.trim().isEmpty
        ? AppSettings.defaultCveApiBaseUrl
        : url.trim();
    state = state.copyWith(cveApiBaseUrl: value);
    await _persist(
      'setCveApiBaseUrl',
      (prefs) => prefs.setString('cveApiBaseUrl', value),
    );
  }

  Future<void> setLanguageCode(String code) async {
    state = state.copyWith(languageCode: code);
    await _persist(
      'setLanguageCode',
      (prefs) => prefs.setString('languageCode', code),
    );
  }

  /// Voeg een lokale map als verbinding toe. Een leeg pad wordt genegeerd; een
  /// pad dat al als verbinding bestaat wordt niet nog eens toegevoegd (de
  /// bestaande naam blijft dan gelden).
  Future<void> addLibrary(String name, String path) async {
    if (path.trim().isEmpty) return;
    final exists = state.connections.any(
      (c) => c is LocalConnection && c.path == path,
    );
    if (exists) return;
    await addConnection(
      LocalConnection(
        id: StorageConnection.newId(),
        name: name.trim(),
        path: path,
      ),
    );
  }

  /// Schrijf de volledige lijst met eigen checklist-sjablonen weg (feedback #9),
  /// als JSON onder één prefs-sleutel.
  Future<void> setCustomChecklists(List<ChecklistTemplate> templates) async {
    state = state.copyWith(customChecklists: templates);
    await _persist('setCustomChecklists', (prefs) async {
      await prefs.setString(
        'customChecklists',
        ChecklistTemplate.encodeList(templates),
      );
    });
  }

  /// Voeg een sjabloon toe (aan het einde).
  Future<void> addCustomChecklist(ChecklistTemplate template) =>
      setCustomChecklists([...state.customChecklists, template]);

  /// Vervang het sjabloon op [index]. Buiten bereik: no-op.
  Future<void> updateCustomChecklist(
    int index,
    ChecklistTemplate template,
  ) async {
    if (index < 0 || index >= state.customChecklists.length) return;
    await setCustomChecklists([
      for (var i = 0; i < state.customChecklists.length; i++)
        if (i == index) template else state.customChecklists[i],
    ]);
  }

  /// Verwijder het sjabloon op [index]. Buiten bereik: no-op.
  Future<void> removeCustomChecklist(int index) async {
    if (index < 0 || index >= state.customChecklists.length) return;
    await setCustomChecklists([
      for (var i = 0; i < state.customChecklists.length; i++)
        if (i != index) state.customChecklists[i],
    ]);
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

  /// De logo's zoals ze in de laatst weggeschreven profielenlijst stonden.
  ///
  /// Een eigen veld en niet "de staat van vóór het opslaan": de aanroepers
  /// werken de staat bij en persisteren daarná, dus op het moment dat
  /// [_saveProfiles] draait is het verschil al vervlogen. Een extensie in een
  /// `part` kan geen veld dragen, dus dit blijft hier; het gedrag eromheen staat
  /// in `parts/settings_provider_traces.dart`.
  Set<String> _persistedLogoPaths = const {};

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
    await _sweepDroppedLogos();
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

/// Zendt een oplopend volgnummer uit telkens als een prefs-schrijf in
/// [SettingsNotifier] faalt. De app-shell luistert hierop en meldt het
/// niet-blokkerend aan de gebruiker (de wijziging geldt wel voor deze sessie).
final settingsPersistErrorProvider = StreamProvider<int>((ref) {
  return ref.watch(settingsProvider.notifier).persistErrors;
});

/// Zendt een oplopend volgnummer uit telkens als een geheim niet in de
/// sleutelhanger kon worden weggeschreven. De app-shell luistert hierop en
/// meldt het apart van [settingsPersistErrorProvider]: hier is de gevolgschade
/// een verbinding die straks om een wachtwoord blijft vragen.
final settingsSecretErrorProvider = StreamProvider<int>((ref) {
  return ref.watch(settingsProvider.notifier).secretErrors;
});
