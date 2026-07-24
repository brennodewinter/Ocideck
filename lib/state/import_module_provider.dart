// State voor de module "Importeren" (#772, besluit B1): materiaal uit andere
// systemen binnenhalen als uitbreiding, standaard uit.
//
// Waarom één module en niet één per bron. Voor de gebruiker is "ik haal er iets
// van buiten in" één gedachte, niet een lijst producten. OpenKAT is vandaag de
// enige importeur; presentatie-import (.pptx/.odp/.key) komt erbij. Elk daarvan
// een eigen schakelaar geven zou het Uitbreidingen-tabblad laten groeien met
// keuzes die niemand los wil maken.
//
// **Het uitbreidpunt is [importerContentProviders].** Een nieuwe importeur
// voegt daar zijn eigen "heb ik al inhoud"-provider toe en erft daarmee de
// vaste regel van dit project: tonen zodra de inhoud er is, en uitzetten mag
// bestaand werk nooit onbereikbaar maken. Dat is bewust een lijst en geen
// steeds langere `||`-expressie — zo staat op één plek wát er als inhoud telt,
// en kan een importeur er niet stil buiten vallen.
//
// De schakelaar woont hier; de instellingen van een importeur wonen bij die
// importeur (OpenKAT: `openkat_provider.dart`). Dat is de scheiding die de
// naamswijziging afdwong en die klopt: de schakelaar beantwoordt "hoort dit bij
// mijn werk", de instelling "waar staan mijn bestanden".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';
import 'openkat_provider.dart';

/// De voorkeursleutel van de schakelaar. Hernoemen mag hierna niet meer: dan
/// staat de module bij een bestaande installatie stil weer uit.
const _enabledKey = 'importModuleEnabled';

/// Wat er per importeur als "inhoud" telt.
///
/// Voeg hier de provider van een nieuwe importeur toe zodra die er is. Staat
/// er ergens al iets ingesteld of geïmporteerd, dan blijft dat bereikbaar ook
/// als de module uit gaat.
final List<Provider<bool>> importerContentProviders = [
  openKatHasContentProvider,
];

final importModuleProvider =
    NotifierProvider<ImportModuleNotifier, ImportModuleState>(
      ImportModuleNotifier.new,
    );

/// Of de schakelaar aan staat.
///
/// Harde standaard uit, en bewust géén afgeleide van de inhoud zoals bij
/// Online opslag: daar bestond de inhoud (verbindingen) al vóórdat de module er
/// was, hier niet. Een nieuwe installatie start dus uit, punt.
final importModuleEnabledProvider = Provider<bool>((ref) {
  return ref.watch(importModuleProvider.select((s) => s.enabled));
});

/// Of er van welke importeur dan ook al inhoud is.
final importHasContentProvider = Provider<bool>((ref) {
  return importerContentProviders.any(ref.watch);
});

/// De poort waar de menu-items en het tabblad Integraties op kijken: aan, óf er
/// is al inhoud.
final importModuleRevealProvider = Provider<bool>((ref) {
  return ref.watch(importModuleEnabledProvider) ||
      ref.watch(importHasContentProvider);
});

class ImportModuleState {
  /// Of de module aan staat. Standaard uit.
  final bool enabled;

  /// Voorkeuren worden nog geladen bij de eerste opbouw.
  final bool loading;

  const ImportModuleState({this.enabled = false, this.loading = true});

  ImportModuleState copyWith({bool? enabled, bool? loading}) =>
      ImportModuleState(
        enabled: enabled ?? this.enabled,
        loading: loading ?? this.loading,
      );
}

class ImportModuleNotifier extends Notifier<ImportModuleState> {
  @override
  ImportModuleState build() {
    _initialize();
    return const ImportModuleState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ImportModuleState(
        enabled: prefs.getBool(_enabledKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      // Onleesbare voorkeuren: de module blijft uit — de veilige kant — maar
      // het laden stopt wél, anders blijft de kaart hangen.
      logError('ImportModuleNotifier._initialize: read module state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = ImportModuleState(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // De stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('ImportModuleNotifier: prefs-schrijf mislukt', e, s);
    }
  }
}
