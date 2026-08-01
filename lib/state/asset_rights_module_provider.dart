import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

const assetRightsModuleEnabledKey = 'assetRightsModuleEnabled';

final assetRightsModuleProvider =
    NotifierProvider<AssetRightsModuleNotifier, AssetRightsModuleState>(
      AssetRightsModuleNotifier.new,
    );

final assetRightsModuleEnabledProvider = Provider<bool>((ref) {
  return ref.watch(assetRightsModuleProvider.select((state) => state.enabled));
});

/// Er is buiten de repository geen verborgen gebruikersinhoud die bereikbaar
/// moet blijven. De beheerresultaten blijven in git staan wanneer de module
/// uitgaat en verschijnen weer zodra zij opnieuw wordt aangezet.
final assetRightsModuleRevealProvider = assetRightsModuleEnabledProvider;

class AssetRightsModuleState {
  final bool enabled;
  final bool loading;

  const AssetRightsModuleState({this.enabled = false, this.loading = true});
}

class AssetRightsModuleNotifier extends Notifier<AssetRightsModuleState> {
  @override
  AssetRightsModuleState build() {
    _initialize();
    return const AssetRightsModuleState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AssetRightsModuleState(
        enabled: prefs.getBool(assetRightsModuleEnabledKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      logError('AssetRightsModuleNotifier: voorkeur lezen', e, s);
      state = const AssetRightsModuleState(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = AssetRightsModuleState(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(assetRightsModuleEnabledKey, value);
    } catch (e, s) {
      logError('AssetRightsModuleNotifier: voorkeur schrijven', e, s);
    }
  }
}
