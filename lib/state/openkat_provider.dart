// De koppeling met OpenKAT (#767, #772, #1158 + live Rocky): of de integratie
// aan staat, de map met exports, en de aangesloten OpenKAT-installaties.
//
// **Waarom de schakelaar hier woont, en niet meer bij de module Importeren.**
// Tot #1158 had OpenKAT bewust geen eigen schakelaar (#772, besluit B1): de
// aan/uit zat in de module Importeren, die ook de presentatie-import dekt. Maar
// #1158 wil integraties elk los kunnen in- en uitschakelen, en dan is één
// gedeelde moduleschakelaar het verkeerde handvat — "OpenKAT uit" zou dan ook
// de presentatie-import doven. OpenKAT is daarom losgemaakt tot een
// eerste-klas integratie met een eigen schakelaar; de module Importeren gaat
// sindsdien alleen nog over presentatie-import.
//
// [enabled] beantwoordt "hoort deze koppeling bij mijn werk",
// [reportDirectory] "waar staan mijn OpenKAT-bestanden",
// [installations] "welke OpenKAT-servers ken ik". Tokens staan in SecretStore.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/openkat/openkat_installation.dart';
import '../models/openkat/openkat_wizard_models.dart';
import '../platform/platform_features.dart';
import '../services/secret_store.dart';
import '../utils/log.dart';
import 'secret_store_provider.dart';

/// De voorkeursleutel van de map. Hernoemen mag nooit: dan is de aangewezen map
/// weg.
const _directoryKey = 'openkatReportDirectory';

/// De voorkeursleutel van de schakelaar (#1158). Harde standaard uit; hernoemen
/// mag hierna niet meer, dan staat de koppeling bij een bestaande installatie
/// stil weer uit.
const _enabledKey = 'openkatIntegrationEnabled';

/// JSON-lijst van [OpenKatInstallation]-metadata (zonder tokens).
const _installationsKey = 'openkatInstallations';

final openKatProvider = NotifierProvider<OpenKatNotifier, OpenKatState>(
  OpenKatNotifier.new,
);

/// De aangewezen map met OpenKAT-exports, of null wanneer er geen staat.
final openKatDirectoryProvider = Provider<String?>((ref) {
  return ref.watch(openKatProvider.select((s) => s.reportDirectory));
});

/// Opgeslagen OpenKAT-installaties (metadata; tokens in de sleutelbos).
final openKatInstallationsProvider = Provider<List<OpenKatInstallation>>((ref) {
  return ref.watch(openKatProvider.select((s) => s.installations));
});

/// Of de OpenKAT-koppeling aan staat (de bewaarde stand). Harde standaard uit.
final openKatIntegrationEnabledProvider = Provider<bool>((ref) {
  return ref.watch(openKatProvider.select((s) => s.enabled));
});

/// Of OpenKAT op dit platform in het Integraties-tabblad hoort te staan.
///
/// Altijd zichtbaar: op web met nette disabled-staat (zoals LibrePlan), op
/// desktop volledig bruikbaar. Mapkiezer en sleutelbos bestaan alleen op
/// desktop — de UI legt dat uit in plaats van het tabblad te verbergen.
final openKatAvailableProvider = Provider<bool>((ref) => true);

/// Of de live/map-functies écht mogen draaien (desktop + lokale mappen).
final openKatDesktopCapableProvider = Provider<bool>((ref) {
  return supportsLocalProjectFolders;
});

/// Wat OpenKAT als "inhoud" inbrengt: een aangewezen map óf minstens één
/// opgeslagen installatie. Uitzetten maakt bestaand werk nooit onbereikbaar.
final openKatHasContentProvider = Provider<bool>((ref) {
  final state = ref.watch(openKatProvider);
  return state.reportDirectory != null || state.installations.isNotEmpty;
});

/// De poort waar het tabblad, de menu-items en het openscherm op kijken: de
/// koppeling staat aan, óf er is al inhoud. Altijd minstens zo ruim als
/// [openKatIntegrationEnabledProvider].
final openKatIntegrationRevealProvider = Provider<bool>((ref) {
  return ref.watch(openKatIntegrationEnabledProvider) ||
      ref.watch(openKatHasContentProvider);
});

class OpenKatState {
  /// Of de koppeling aan staat (#1158). Standaard uit.
  final bool enabled;

  /// De map met OpenKAT-exports; null zolang er geen gekozen is.
  final String? reportDirectory;

  /// Aangesloten OpenKAT-servers (metadata).
  final List<OpenKatInstallation> installations;

  /// Voorkeuren worden nog geladen bij de eerste opbouw.
  final bool loading;

  /// Recept en bron per open deck. De sleutel is de stabiele recovery-id van
  /// het tabblad, niet "het laatst gebruikte rapport": twee OpenKAT-decks
  /// kunnen zo in dezelfde sessie ieder naar hun eigen bron terug.
  final Map<String, OpenKatDeckSession> deckSessions;

  const OpenKatState({
    this.enabled = false,
    this.reportDirectory,
    this.installations = const [],
    this.loading = true,
    this.deckSessions = const {},
  });

  OpenKatState copyWith({
    bool? enabled,
    String? reportDirectory,
    bool clearReportDirectory = false,
    List<OpenKatInstallation>? installations,
    bool? loading,
    Map<String, OpenKatDeckSession>? deckSessions,
  }) => OpenKatState(
    enabled: enabled ?? this.enabled,
    reportDirectory: clearReportDirectory
        ? null
        : (reportDirectory ?? this.reportDirectory),
    installations: installations ?? this.installations,
    loading: loading ?? this.loading,
    deckSessions: deckSessions ?? this.deckSessions,
  );
}

class OpenKatDeckSession {
  final String directory;
  final OpenKatWizardRecipe recipe;

  const OpenKatDeckSession({required this.directory, required this.recipe});
}

class OpenKatNotifier extends Notifier<OpenKatState> {
  bool _directoryChanged = false;
  bool _enabledChanged = false;
  bool _installationsChanged = false;

  SecretStore get _secrets => ref.read(secretStoreProvider);

  @override
  OpenKatState build() {
    _initialize();
    return const OpenKatState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final directory = prefs.getString(_directoryKey);
      final storedEnabled = prefs.getBool(_enabledKey) ?? false;
      final installations = _decodeInstallations(
        prefs.getString(_installationsKey),
      );
      // Wat de gebruiker in deze sessie al omzette wint van de opgeslagen
      // waarde: het laden mag een net gemaakte keuze niet terugdraaien.
      final directoryHasContent = directory != null && directory.isNotEmpty;
      state = state.copyWith(
        enabled: _enabledChanged ? null : storedEnabled,
        reportDirectory: _directoryChanged || !directoryHasContent
            ? null
            : directory,
        clearReportDirectory: !_directoryChanged && !directoryHasContent,
        installations: _installationsChanged ? null : installations,
        loading: false,
      );
    } catch (e, s) {
      // Onleesbare voorkeuren: geen map en uit — de veilige kant — maar het
      // laden stopt wél, anders blijft het tabblad hangen.
      logError('OpenKatNotifier._initialize: read integration state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  /// Zet de koppeling aan of uit en bewaart de keuze.
  Future<void> setEnabled(bool value) async {
    _enabledChanged = true;
    state = state.copyWith(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // De stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('OpenKatNotifier: prefs-schrijf mislukt (schakelaar)', e, s);
    }
  }

  /// Wijst de map met OpenKAT-exports aan, of wist hem met null.
  Future<void> setReportDirectory(String? directory) async {
    _directoryChanged = true;
    final trimmed = directory?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    state = state.copyWith(
      reportDirectory: value,
      clearReportDirectory: value == null,
      loading: false,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_directoryKey);
      } else {
        await prefs.setString(_directoryKey, value);
      }
    } catch (e, s) {
      // De stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('OpenKatNotifier: prefs-schrijf mislukt', e, s);
    }
  }

  /// Voegt een installatie toe en schrijft optioneel het token weg.
  Future<void> addInstallation(
    OpenKatInstallation installation, {
    String? token,
  }) async {
    final next = [...state.installations, installation];
    await _persistInstallations(next);
    if (token != null && token.trim().isNotEmpty) {
      await _secrets.writeOpenKatToken(installation.id, token.trim());
    }
  }

  /// Vervangt een bestaande installatie (zelfde id). Leeg [token] = ongewijzigd.
  Future<void> updateInstallation(
    OpenKatInstallation installation, {
    String? token,
  }) async {
    final next = [
      for (final item in state.installations)
        if (item.id == installation.id) installation else item,
    ];
    await _persistInstallations(next);
    if (token != null && token.trim().isNotEmpty) {
      await _secrets.writeOpenKatToken(installation.id, token.trim());
    }
  }

  /// Verwijdert installatie + token. Onomkeerbaar.
  Future<void> removeInstallation(String id) async {
    final next = [
      for (final item in state.installations)
        if (item.id != id) item,
    ];
    await _persistInstallations(next);
    await _secrets.deleteOpenKatToken(id);
  }

  /// Zet de status na een verbindingstest.
  Future<void> markInstallationChecked({
    required String id,
    required OpenKatInstallationStatus status,
  }) async {
    final next = [
      for (final item in state.installations)
        if (item.id == id)
          item.copyWith(
            lastCheckedAt: DateTime.now().toUtc(),
            lastStatus: status,
          )
        else
          item,
    ];
    await _persistInstallations(next);
  }

  Future<String?> readToken(String installationId) =>
      _secrets.readOpenKatToken(installationId);

  Future<bool> hasToken(String installationId) async {
    final token = await readToken(installationId);
    return token != null && token.trim().isNotEmpty;
  }

  OpenKatInstallation? installationById(String id) {
    for (final item in state.installations) {
      if (item.id == id) return item;
    }
    return null;
  }

  OpenKatDeckSession? sessionForDeck(String deckId) =>
      state.deckSessions[deckId];

  /// Bindt de bron en het recept aan één open deck.
  ///
  /// Dit blijft bewust sessiestaat. De directoryvoorkeur mag op schijf, maar
  /// een opgeslagen deck bevat geen verifieerbare koppeling met die directory;
  /// na herstart vraagt bijwerken daarom opnieuw om de bron.
  void rememberDeckSession({
    required String deckId,
    required String directory,
    required OpenKatWizardRecipe recipe,
  }) {
    state = state.copyWith(
      deckSessions: Map.unmodifiable({
        ...state.deckSessions,
        deckId: OpenKatDeckSession(directory: directory, recipe: recipe),
      }),
    );
  }

  Future<void> _persistInstallations(List<OpenKatInstallation> next) async {
    _installationsChanged = true;
    state = state.copyWith(
      installations: List.unmodifiable(next),
      loading: false,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode([for (final item in next) item.toJson()]);
      await prefs.setString(_installationsKey, encoded);
    } catch (e, s) {
      logError('OpenKatNotifier: prefs-schrijf mislukt (installaties)', e, s);
    }
  }

  List<OpenKatInstallation> _decodeInstallations(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            OpenKatInstallation.fromJson(Map<String, Object?>.from(item)),
      ];
    } catch (e, s) {
      logError('OpenKatNotifier: installaties onleesbaar', e, s);
      return const [];
    }
  }
}
