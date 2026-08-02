// State for the "Managementsysteem" module (ISO_MANAGEMENTSYSTEEM §5):
// ISO 27001/9001/42001 progress reporting as an opt-in extension, off by
// default.
//
// Same contract as Procesverbetering / Importeren: reveal when the switch is on
// **or** the open deck already carries a `controlStatus` slide, so switching off
// never strands a deck (MODUS-REGEL — slides always render). Callers OR in
// [Deck.hasManagementSystemSlides] with this "module is on" half.
//
// Simpler than the Procesverbetering notifier: the ISO index is bundled `const`
// data (management_system_catalog.dart), so there is no catalog to warm on
// enable — only the preference to persist.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

/// Preference key. Renaming afterwards would silently turn the module off for
/// existing installs.
const _enabledKey = 'managementsysteemModuleEnabled';

final managementsysteemProvider =
    NotifierProvider<ManagementsysteemNotifier, ManagementsysteemState>(
      ManagementsysteemNotifier.new,
    );

/// Whether the switch is on.
final managementsysteemEnabledProvider = Provider<bool>((ref) {
  return ref.watch(managementsysteemProvider.select((s) => s.enabled));
});

/// Gate for menus and picker tabs: on, or the open deck already has a
/// `controlStatus` slide. Callers that know about a specific deck also OR in
/// [Deck.hasManagementSystemSlides] at the use site; this provider covers the
/// global "module is on" half.
final managementsysteemRevealProvider = Provider<bool>((ref) {
  return ref.watch(managementsysteemEnabledProvider);
});

class ManagementsysteemState {
  /// Whether the module is on. Default off.
  final bool enabled;

  /// Preferences still loading on first build.
  final bool loading;

  const ManagementsysteemState({this.enabled = false, this.loading = true});

  ManagementsysteemState copyWith({bool? enabled, bool? loading}) =>
      ManagementsysteemState(
        enabled: enabled ?? this.enabled,
        loading: loading ?? this.loading,
      );
}

class ManagementsysteemNotifier extends Notifier<ManagementsysteemState> {
  @override
  ManagementsysteemState build() {
    _initialize();
    return const ManagementsysteemState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ManagementsysteemState(
        enabled: prefs.getBool(_enabledKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      // Unreadable prefs: stay off (safe side) but stop loading so the card
      // does not hang.
      logError('ManagementsysteemNotifier._initialize', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = ManagementsysteemState(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // Session state already updated; only persistence failed.
      logError('ManagementsysteemNotifier: prefs write failed', e, s);
    }
  }

  Future<void> enable() => setEnabled(true);

  Future<void> disable() => setEnabled(false);
}
