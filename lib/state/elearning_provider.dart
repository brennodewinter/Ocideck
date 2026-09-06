// State for the "eLearning" module (#1999): question authoring, structural
// slides, and local import of SCORM/QTI/xAPI/AICC/OLX packages.
//
// Same contract as Managementsysteem / Procesverbetering: reveal when the
// switch is on **or** the open deck already carries an eLearning slide, so
// switching off never strands a deck (MODUS-REGEL — slides always render).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

/// Preference key. Renaming afterwards would silently turn the module off for
/// existing installs.
const _enabledKey = 'elearningModuleEnabled';

final elearningProvider = NotifierProvider<ElearningNotifier, ElearningState>(
  ElearningNotifier.new,
);

/// Whether the switch is on.
final elearningEnabledProvider = Provider<bool>((ref) {
  return ref.watch(elearningProvider.select((s) => s.enabled));
});

/// Gate for menus and picker tabs: on, or the open deck already has an
/// eLearning slide. Callers that know about a specific deck also OR in
/// [Deck.hasElearningSlides] at the use site; this provider covers the
/// global "module is on" half.
final elearningRevealProvider = Provider<bool>((ref) {
  return ref.watch(elearningEnabledProvider);
});

class ElearningState {
  /// Whether the module is on. Default off.
  final bool enabled;

  /// Preferences still loading on first build.
  final bool loading;

  const ElearningState({this.enabled = false, this.loading = true});

  ElearningState copyWith({bool? enabled, bool? loading}) => ElearningState(
    enabled: enabled ?? this.enabled,
    loading: loading ?? this.loading,
  );
}

class ElearningNotifier extends Notifier<ElearningState> {
  @override
  ElearningState build() {
    _initialize();
    return const ElearningState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ElearningState(
        enabled: prefs.getBool(_enabledKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      // Unreadable prefs: stay off (safe side) but stop loading so the card
      // does not hang.
      logError('ElearningNotifier._initialize', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = ElearningState(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // Session state already updated; only persistence failed.
      logError('ElearningNotifier: prefs write failed', e, s);
    }
  }

  Future<void> enable() => setEnabled(true);

  Future<void> disable() => setEnabled(false);
}
