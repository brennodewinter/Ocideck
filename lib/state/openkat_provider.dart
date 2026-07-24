// State voor de module "OpenKAT" (#767, #772): rapportages uit OpenKAT inlezen
// en er een managementoverzicht van maken, als uitbreiding, standaard uit.
//
// Waarom een module. OpenKAT is een specifiek product en een specifieke
// werkwijze; wie een presentatie komt maken heeft er niets aan en hoort er dus
// ook geen menu-item van te zien. Dat is dezelfde afweging als bij de drie
// modules ervóór (#570, #648, #731) en dezelfde vaste regel geldt: **tonen
// zodra de inhoud er is.** Uitzetten mag nooit werk onbereikbaar maken.
//
// Anders dan de drie modules ervóór draagt deze een instelling die geen
// schakelaar is: de map waar de OpenKAT-exports staan. Die woont hier en niet
// in `Settings`, om dezelfde reden als de andere modulesleutels — één
// voorkeursleutel per module, geen geparametriseerd framework. Zie de doc-kop
// van `module_registry.dart`.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

/// De voorkeursleutels. Hernoemen mag nooit: dan staat de module bij een
/// bestaande installatie stil weer uit en is de aangewezen map weg.
const _enabledKey = 'openkatModuleEnabled';
const _directoryKey = 'openkatReportDirectory';

final openKatProvider = NotifierProvider<OpenKatNotifier, OpenKatState>(
  OpenKatNotifier.new,
);

/// Of de schakelaar aan staat.
///
/// Harde standaard uit, en bewust géén afgeleide van de inhoud zoals bij
/// Online opslag: daar bestond de inhoud (verbindingen) al vóórdat de module
/// er was, hier niet. Een nieuwe installatie start dus uit, punt.
final openKatEnabledProvider = Provider<bool>((ref) {
  return ref.watch(openKatProvider.select((s) => s.enabled));
});

/// De aangewezen map met OpenKAT-exports, of null wanneer er geen staat.
final openKatDirectoryProvider = Provider<String?>((ref) {
  return ref.watch(openKatProvider.select((s) => s.reportDirectory));
});

/// De poort waar het menu-item op kijkt: aan, óf er is al een map aangewezen.
///
/// De vaste regel van dit project. Wie de module uitzet nadat hij een map heeft
/// aangewezen, houdt het invoerpunt — anders is een deck dat op herimport
/// wacht opeens niet meer bij te werken, en is de enige weg terug het opnieuw
/// aanwijzen van een map waarvan de app al wist waar hij stond.
final openKatRevealProvider = Provider<bool>((ref) {
  final state = ref.watch(openKatProvider);
  return state.enabled || state.reportDirectory != null;
});

class OpenKatState {
  /// Of de module aan staat. Standaard uit.
  final bool enabled;

  /// De map met OpenKAT-exports; null zolang er geen gekozen is.
  final String? reportDirectory;

  /// Voorkeuren worden nog geladen bij de eerste opbouw.
  final bool loading;

  const OpenKatState({
    this.enabled = false,
    this.reportDirectory,
    this.loading = true,
  });

  OpenKatState copyWith({
    bool? enabled,
    String? reportDirectory,
    bool clearReportDirectory = false,
    bool? loading,
  }) => OpenKatState(
    enabled: enabled ?? this.enabled,
    reportDirectory: clearReportDirectory
        ? null
        : (reportDirectory ?? this.reportDirectory),
    loading: loading ?? this.loading,
  );
}

class OpenKatNotifier extends Notifier<OpenKatState> {
  @override
  OpenKatState build() {
    _initialize();
    return const OpenKatState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final directory = prefs.getString(_directoryKey);
      state = OpenKatState(
        enabled: prefs.getBool(_enabledKey) ?? false,
        reportDirectory: (directory != null && directory.isNotEmpty)
            ? directory
            : null,
        loading: false,
      );
    } catch (e, s) {
      // Onleesbare voorkeuren: de module blijft uit — de veilige kant — maar
      // het laden stopt wél, anders blijft de kaart hangen.
      logError('OpenKatNotifier._initialize: read module state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value, loading: false);
    await _write((prefs) => prefs.setBool(_enabledKey, value));
  }

  /// Wijst de map met OpenKAT-exports aan, of wist hem met null.
  Future<void> setReportDirectory(String? directory) async {
    final trimmed = directory?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    state = state.copyWith(
      reportDirectory: value,
      clearReportDirectory: value == null,
      loading: false,
    );
    await _write(
      (prefs) => value == null
          ? prefs.remove(_directoryKey)
          : prefs.setString(_directoryKey, value),
    );
  }

  Future<void> _write(Future<void> Function(SharedPreferences) apply) async {
    try {
      await apply(await SharedPreferences.getInstance());
    } catch (e, s) {
      // De stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('OpenKatNotifier: prefs-schrijf mislukt', e, s);
    }
  }
}
