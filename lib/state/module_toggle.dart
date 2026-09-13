// De gedeelde schakelaar-state voor module-notifiers.
//
// Drie module-notifiers (managementsysteem, elearning, procesverbetering)
// hadden een identieke state-klasse en bijna-identieke init/setEnabled-logica.
// Deze base centraliseert het SharedPreferences-lezen en -schrijven; subclasses
// overschrijven [onEnabled] voor side-effecten zoals het voorverwarmen van een
// catalogus.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

/// State voor een module-schakelaar: aan/uit + nog-aan-het-laden.
class ModuleToggleState {
  const ModuleToggleState({this.enabled = false, this.loading = true});

  /// Of de module aan staat. Standaard uit.
  final bool enabled;

  /// Voorkeuren worden nog geladen bij de eerste opbouw.
  final bool loading;

  ModuleToggleState copyWith({bool? enabled, bool? loading}) =>
      ModuleToggleState(
        enabled: enabled ?? this.enabled,
        loading: loading ?? this.loading,
      );
}

/// Base voor module-schakelaar-notifiers. Leest de voorkeur uit SharedPreferences
/// bij init, schrijft hem bij setEnabled. Subclasses overschrijven [onEnabled]
/// voor side-effecten (bijvoorbeeld een catalogus voorverwarmen).
class ModuleToggleNotifier extends Notifier<ModuleToggleState> {
  ModuleToggleNotifier(this.enabledKey);

  /// De SharedPreferences-sleutel. Hernoemen mag niet: dan staat de module bij
  /// een bestaande installatie stil weer uit.
  final String enabledKey;

  @override
  ModuleToggleState build() {
    _initialize();
    return const ModuleToggleState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(enabledKey) ?? false;
      state = ModuleToggleState(enabled: enabled, loading: false);
      if (enabled) await onEnabled();
    } catch (e, s) {
      // Onleesbare voorkeuren: module blijft uit (veilige kant), laden stopt.
      logError('$runtimeType._initialize: read module state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = ModuleToggleState(enabled: value, loading: false);
    if (value) await onEnabled();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, value);
    } catch (e, s) {
      // Stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('$runtimeType: prefs write failed', e, s);
    }
  }

  /// Hook die draait wanneer de module aangaat — bij init als hij al aan stond,
  /// en bij setEnabled(true). Override voor side-effecten.
  Future<void> onEnabled() async {}

  Future<void> enable() => setEnabled(true);

  Future<void> disable() => setEnabled(false);
}
