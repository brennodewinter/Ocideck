// State for the "Procesverbetering" module (PROCESS_IMPROVEMENT.md Phase 0):
// Lean Six Sigma authoring as an opt-in extension, off by default.
//
// Same contract as Importeren / Online opslag: reveal when content already
// exists, so switching off never strands a deck that already carries
// improvement slides (MODUS-REGEL — slides always render). Callers OR in
// [Deck.hasImprovementSlides] (true once a `matrix` / later engine type is
// present) with the enabled preference.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';
import '../services/improvement/improvement_template_catalog.dart';

/// Preference key. Renaming afterwards would silently turn the module off for
/// existing installs.
const _enabledKey = 'procesverbeteringModuleEnabled';

final procesverbeteringProvider =
    NotifierProvider<ProcesverbeteringNotifier, ProcesverbeteringState>(
      ProcesverbeteringNotifier.new,
    );

/// Whether the switch is on.
final procesverbeteringEnabledProvider = Provider<bool>((ref) {
  return ref.watch(procesverbeteringProvider.select((s) => s.enabled));
});

/// Gate for menus and picker tabs: on, or the open deck already has
/// improvement slides. Callers that know about a specific deck also OR in
/// [Deck.hasImprovementSlides] at the use site; this provider covers the
/// global "module is on" half.
final procesverbeteringRevealProvider = Provider<bool>((ref) {
  return ref.watch(procesverbeteringEnabledProvider);
});

class ProcesverbeteringState {
  /// Whether the module is on. Default off.
  final bool enabled;

  /// Preferences still loading on first build.
  final bool loading;

  const ProcesverbeteringState({this.enabled = false, this.loading = true});

  ProcesverbeteringState copyWith({bool? enabled, bool? loading}) =>
      ProcesverbeteringState(
        enabled: enabled ?? this.enabled,
        loading: loading ?? this.loading,
      );
}

class ProcesverbeteringNotifier extends Notifier<ProcesverbeteringState> {
  @override
  ProcesverbeteringState build() {
    _initialize();
    return const ProcesverbeteringState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_enabledKey) ?? false;
      state = ProcesverbeteringState(enabled: enabled, loading: false);
      if (enabled) {
        await ImprovementTemplateCatalog.instance.ensureLoaded();
      }
    } catch (e, s) {
      // Unreadable prefs: stay off (safe side) but stop loading so the card
      // does not hang.
      logError(
        'ProcesverbeteringNotifier._initialize: read module state',
        e,
        s,
      );
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = ProcesverbeteringState(enabled: value, loading: false);
    if (value) {
      // Warm the artefact catalog when the module is switched on so editors
      // never open against an empty floor-only race with the asset load.
      // ignore: unawaited_futures
      ImprovementTemplateCatalog.instance.ensureLoaded();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // Session state already updated; only persistence failed.
      logError('ProcesverbeteringNotifier: prefs write failed', e, s);
    }
  }

  Future<void> enable() => setEnabled(true);

  Future<void> disable() => setEnabled(false);
}
