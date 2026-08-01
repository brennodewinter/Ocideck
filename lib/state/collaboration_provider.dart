// State for the "Realtime samenwerken" module (SELF_ENCRYPTED_RELAY.md §6): live
// co-authoring as an opt-in extension, off by default. Same contract as the other
// modules — reveal when the content is already there, so an install that already
// configured an account is not stranded after an upgrade.
//
// Two levels, because more transports are coming (Jitsi, XMPP): the module is the
// umbrella switch, and each transport has its own toggle under it. Today that is
// just Matrix; its toggle defaults on, so enabling the module gives a working
// setup, and it can be turned off on its own without leaving the module.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';
import 'matrix_client_provider.dart';

/// Preference keys. Renaming afterwards would silently reset the choice for
/// existing installs.
const _moduleKey = 'collaborationModuleEnabled';
const _matrixKey = 'matrixCollabEnabled';

final collaborationProvider =
    NotifierProvider<CollaborationNotifier, CollaborationState>(
      CollaborationNotifier.new,
    );

/// Whether the module master switch is on (the stored value).
final collaborationEnabledProvider = Provider<bool>(
  (ref) => ref.watch(collaborationProvider.select((s) => s.enabled)),
);

/// Whether the Matrix transport is switched on within the module. One transport
/// today; Jitsi/XMPP will get their own toggles beside it.
final matrixCollabEnabledProvider = Provider<bool>(
  (ref) => ref.watch(collaborationProvider.select((s) => s.matrixEnabled)),
);

/// Matrix is operative: the module is on **and** the Matrix toggle is on. This
/// gates the Matrix host/join actions.
final matrixCollabActiveProvider = Provider<bool>(
  (ref) =>
      ref.watch(collaborationEnabledProvider) &&
      ref.watch(matrixCollabEnabledProvider),
);

/// The reveal gate for the *Samenwerken* tab and the Matrix features: operative,
/// or a Matrix account is already configured (never strand an existing account).
final collaborationRevealProvider = Provider<bool>((ref) {
  if (ref.watch(matrixCollabActiveProvider)) return true;
  return ref.watch(matrixAccountProvider)?.isConfigured ?? false;
});

class CollaborationState {
  const CollaborationState({
    this.enabled = false,
    this.matrixEnabled = true,
    this.loading = true,
  });

  /// Module master switch. Default off.
  final bool enabled;

  /// Matrix transport toggle within the module. Default on — the shipping
  /// transport, so enabling the module works out of the box.
  final bool matrixEnabled;

  /// Preferences still loading on first build.
  final bool loading;

  CollaborationState copyWith({
    bool? enabled,
    bool? matrixEnabled,
    bool? loading,
  }) => CollaborationState(
    enabled: enabled ?? this.enabled,
    matrixEnabled: matrixEnabled ?? this.matrixEnabled,
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
        matrixEnabled: prefs.getBool(_matrixKey) ?? true,
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

  Future<void> setMatrixEnabled(bool value) async {
    state = state.copyWith(matrixEnabled: value, loading: false);
    await _persist(_matrixKey, value);
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
