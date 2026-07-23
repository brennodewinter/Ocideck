// State voor de module "Online opslag" (#570): WebDAV, S3 en git als
// uitbreiding, standaard uit.
//
// Twee redenen, en de tweede weegt zwaarder. Stilte: wie een presentatie komt
// maken hoeft geen drie servertypes, vier bladerdialogen en een
// review/merge/tag-vocabulaire te zien vóór de eerste dia er staat. En
// eerlijkheid over rijpheid: vijf van de tien punten in
// docs/design/VERIFICATION.md zijn remote-opslagpaden die nog nooit een echte
// server hebben gezien — zo'n pad hoort bewust gekozen te worden, niet
// binnengelopen.
//
// De derde module op het Uitbreidingen-tabblad, en net als de twee vorige met
// eigen state (zie de doc-kop van `info_safety_provider.dart` en het
// registerlicht in `module_registry.dart`): er is één voorkeursleutel en één
// afgeleide poort, geen geparametriseerd framework.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/storage_connection.dart';
import '../utils/log.dart';
import 'settings_provider.dart';

/// De voorkeursleutel. Alleen geschreven wanneer de gebruiker de schakelaar
/// zelf omzet; zolang hij ontbreekt volgt de stand de inhoud (zie
/// [onlineStorageEnabledProvider]).
const _enabledKey = 'onlineStorageEnabled';

final onlineStorageProvider =
    NotifierProvider<OnlineStorageNotifier, OnlineStorageState>(
      OnlineStorageNotifier.new,
    );

/// Of er al online verbindingen ingesteld staan — de "inhoud" van deze module.
final _hasRemoteConnectionsProvider = Provider<bool>((ref) {
  return ref.watch(
    settingsProvider.select(
      (s) => s.connections.any((c) => c.kind != StorageConnectionKind.local),
    ),
  );
});

/// Of de module aan staat.
///
/// Zonder opgeslagen keuze volgt de stand de inhoud: wie al een online
/// verbinding had toen deze module verscheen, start met de module áán —
/// default-uit geldt voor nieuwe installaties, niet voor een werkende
/// configuratie (#570). Dit is bewust een afgeleide en geen eenmalige
/// migratieschrijf: de voorkeuren en de verbindingslijst laden asynchroon, en
/// een migratie die te vroeg leest zou "geen verbindingen" vastleggen als
/// "bewust uit".
///
/// Het kantelpunt dat daarbij hoort, en dat een keuze is en geen vergissing:
/// wie nooit een keuze opsloeg en zijn laatste online verbinding verwijdert,
/// ziet de module terugvallen naar uit — geen inhoud en geen keuze ís de
/// standaard. Wie de verbinding alleen opnieuw wilde invoeren, vindt de
/// schakelaar op Uitbreidingen terug (de zoekingang "webdav"/"git" wijst
/// erheen); zijn eigen omgezette schakelaar wint daarna altijd, want die is
/// een opgeslagen keuze.
final onlineStorageEnabledProvider = Provider<bool>((ref) {
  final stored = ref.watch(onlineStorageProvider).stored;
  return stored ?? ref.watch(_hasRemoteConnectionsProvider);
});

/// De poort waar de opslag-oppervlakken op kijken: aan, óf de inhoud is er al.
///
/// Dezelfde vaste regel als bij de checklists (#648) en het AI-tabblad (#731):
/// tonen zodra er inhoud is. Wie verbindingen heeft en de module uitzet, houdt
/// zijn verbindingen, het git-menu en de outbox — uitzetten mag bestaand werk
/// en wachtend werk niet onbereikbaar maken. Wat er dan wél verdwijnt is
/// alleen de mogelijkheid om níéuwe online verbindingen toe te voegen.
final onlineStorageRevealProvider = Provider<bool>((ref) {
  return ref.watch(onlineStorageEnabledProvider) ||
      ref.watch(_hasRemoteConnectionsProvider);
});

class OnlineStorageState {
  /// De opgeslagen keuze, of null wanneer de gebruiker er nooit een maakte.
  final bool? stored;

  /// Prefs still loading on first build.
  final bool loading;

  const OnlineStorageState({this.stored, this.loading = true});

  OnlineStorageState copyWith({bool? stored, bool? loading}) {
    return OnlineStorageState(
      stored: stored ?? this.stored,
      loading: loading ?? this.loading,
    );
  }
}

class OnlineStorageNotifier extends Notifier<OnlineStorageState> {
  @override
  OnlineStorageState build() {
    _initialize();
    return const OnlineStorageState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = OnlineStorageState(
        stored: prefs.getBool(_enabledKey),
        loading: false,
      );
    } catch (e, s) {
      // Onleesbare voorkeuren: geen opgeslagen keuze, dus de stand volgt de
      // inhoud (de veilige kant: niemand raakt iets kwijt), en het laden stopt
      // wél — anders blijft de UI hangen.
      logError('OnlineStorageNotifier._initialize: read module state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = OnlineStorageState(stored: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // State already updated for this session; only persistence is lost.
      logError('OnlineStorageNotifier: prefs-schrijf mislukt', e, s);
    }
  }
}
