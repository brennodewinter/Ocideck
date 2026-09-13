// State for the "Realtime samenwerken" module (SELF_ENCRYPTED_RELAY.md §6): live
// co-authoring as an opt-in extension, off by default. Same contract as the other
// modules — reveal when the content is already there, so an install that already
// configured an account is not stranded after an upgrade.
//
// Two levels, because more transports are coming (Jitsi, XMPP): the module is the
// umbrella switch, and each transport has its own toggle under it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

/// Preference keys. Renaming afterwards would silently reset the choice for
/// existing installs.
const _moduleKey = 'collaborationModuleEnabled';

final collaborationProvider =
    NotifierProvider<CollaborationNotifier, CollaborationState>(
      CollaborationNotifier.new,
    );

/// Whether the module master switch is on (the stored value).
final collaborationEnabledProvider = Provider<bool>(
  (ref) => ref.watch(collaborationProvider.select((s) => s.enabled)),
);

/// The reveal gate for the *Samenwerken* tab: operative.
final collaborationRevealProvider = Provider<bool>((ref) {
  return ref.watch(collaborationEnabledProvider);
});

class CollaborationState {
  const CollaborationState({this.enabled = false, this.loading = true});

  /// Module master switch. Default off.
  final bool enabled;

  /// Preferences still loading on first build.
  final bool loading;

  CollaborationState copyWith({bool? enabled, bool? loading}) =>
      CollaborationState(
        enabled: enabled ?? this.enabled,
        loading: loading ?? this.loading,
      );
}

class CollaborationNotifier extends Notifier<CollaborationState> {
  @override
  CollaborationState build() {
    _initialize();
    return const CollaborationState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = CollaborationState(
        enabled: prefs.getBool(_moduleKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      // Unreadable prefs: stay off (safe side) but stop loading.
      logError('CollaborationNotifier._initialize: read module state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value, loading: false);
    await _persist(_moduleKey, value);
  }

  Future<void> _persist(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e, s) {
      // Session state already updated; only persistence failed.
      logError('CollaborationNotifier: prefs write failed', e, s);
    }
  }
}
