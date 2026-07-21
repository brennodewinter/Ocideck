// State for the "Informatieveiligheid" module (PENTEST_MIAUW.md §6).
//
// A single toggle, OFF by default, persisted in the one shared_preferences
// domain like every other setting. The module's reference data (CWE, WSTG, CVSS,
// MIAUW) is compiled into the app and bundled as an asset, so there is nothing
// to fetch, verify or cache: switching the module on reveals its features — the
// Informatieveiligheid picker tab, MIAUW templates and the
// finding/checklist/scope-matrix/sign-off slide types — at once, offline, and
// without needing the outbound-traffic consent. Consumers gate on
// [infoSafetyRevealProvider].
//
// This is NOT a reusable module framework, despite the enable → reveal shape:
// the preference key and the reveal check are hardcoded to this one module, and
// [infoSafetyRevealProvider] is a single global that its consumers name directly.
// A second module needs a real registry (module id, parameterised keys,
// per-module reveal) — build that when one actually arrives, rather than
// budgeting to "reuse" this.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

/// Draagt met opzet nog de oude modulenaam. De identifiers in de code heten
/// inmiddels allemaal `infoSafety…`, maar deze string staat op de schijf van
/// iedereen die de module ooit heeft aangezet. Hem meehernoemen zou de
/// schakelaar bij al die mensen stilzwijgend op uit zetten — een
/// gedragswijziging vermomd als opruimen, en een die niemand meldt omdat het
/// eruitziet alsof de module gewoon nooit aanstond. Wie hem tóch wil
/// gelijktrekken, schrijft eerst een migratie die de oude sleutel leest.
const _enabledKey = 'secModuleEnabled';

/// Written by the provisioning pipeline this module used to carry. Removed on
/// load so an upgraded install does not keep an orphan key around forever.
const _legacyVersionKey = 'secModulePackVersion';

final infoSafetyProvider =
    NotifierProvider<InfoSafetyNotifier, InfoSafetyState>(
      InfoSafetyNotifier.new,
    );

/// The gating provider the module's features watch.
final infoSafetyRevealProvider = Provider<bool>((ref) {
  return ref.watch(infoSafetyProvider).revealed;
});

class InfoSafetyState {
  final bool enabled;

  /// Prefs still loading on first build.
  final bool loading;

  const InfoSafetyState({this.enabled = false, this.loading = true});

  /// Reveal = the module is on. There is no second condition: the data it needs
  /// ships with the app, so there is no fetch to wait for and no cache to miss.
  bool get revealed => enabled;

  InfoSafetyState copyWith({bool? enabled, bool? loading}) {
    return InfoSafetyState(
      enabled: enabled ?? this.enabled,
      loading: loading ?? this.loading,
    );
  }
}

class InfoSafetyNotifier extends Notifier<InfoSafetyState> {
  @override
  InfoSafetyState build() {
    _initialize();
    return const InfoSafetyState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = state.copyWith(
        enabled: prefs.getBool(_enabledKey) ?? false,
        loading: false,
      );
      if (prefs.containsKey(_legacyVersionKey)) {
        await prefs.remove(_legacyVersionKey);
      }
    } catch (e, s) {
      // Onleesbare voorkeuren: de module blijft uit (de veilige stand) maar het
      // laden stopt wél, anders blijft de UI hangen. Zelfde logweg als de
      // schrijffout hieronder — een `debugPrint` haalde de logstroom niet.
      logError('InfoSafetyNotifier._initialize: read module state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  /// Turn the module on and reveal its features. Nothing is fetched, so there is
  /// no failure path to report and no recourse to offer.
  Future<void> enable() => _setEnabled(true);

  /// Turn the module off: the features hide again. The reference data stays in
  /// the app either way — there is nothing to clean up.
  Future<void> disable() => _setEnabled(false);

  Future<void> _setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // State already updated for this session; only persistence is lost.
      logError('InfoSafetyNotifier: prefs-schrijf mislukt', e, s);
    }
  }
}
