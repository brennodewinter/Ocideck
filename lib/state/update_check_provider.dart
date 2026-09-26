import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/platform_features.dart';
import '../services/export_metadata.dart' show kOciDeckVersion;
import '../services/update_check_service.dart';
import '../utils/log.dart';
import '../utils/version_compare.dart';
import 'settings_provider.dart';

/// Wat de UI over de versiecheck weet. `latestVersion` is de laatst bekende
/// nieuwste release — óók de waarde die een eerdere sessie bewaarde, zodat de
/// indicator op het openscherm direct zichtbaar is zonder dat er opnieuw naar
/// buiten gebeld hoeft te worden.
class UpdateCheckState {
  const UpdateCheckState({
    this.latestVersion,
    this.checking = false,
    this.checkFailed = false,
  });

  /// De nieuwste versie volgens de meest recente geslaagde check
  /// (genormaliseerd, zonder `v`). `null` wanneer nog nooit een check is
  /// gelukt — de indicator toont dan niets.
  final String? latestVersion;

  /// Er loopt op dit moment een controle (alleen waarneembaar voor de knop op
  /// het Over-tabblad; de automatische check flasht dit niet apart).
  final bool checking;

  /// De laatste controle — door de gebruiker zelf gestart — faalde. Alleen de
  /// handmatige route mag dit tonen: wie op de knop drukt, wacht op een
  /// antwoord; de stille achtergrondcheck is nooit een melding waard.
  final bool checkFailed;

  /// Of `latestVersion` strikt nieuwer is dan het draaiende nummer. Een
  /// ontwikkelbuild die vóórliegt op de releases toont bewust niets.
  bool get updateAvailable =>
      latestVersion != null &&
      AppVersion.isNewer(latestVersion!, kOciDeckVersion);
}

/// De service achter de check — aparte provider zodat tests de naad kunnen
/// vervangen zonder het netwerk te raken.
final updateCheckServiceProvider = Provider<UpdateCheckService>(
  (ref) => const UpdateCheckService(),
);

/// Hoe lang een automatische check minstens op zich laat wachten. Eén ping
/// per dag is genoeg om een release te vinden, en begrenst wat de forge over
/// de gebruiker kan waarnemen tot één metagegeven per dag.
const kUpdateCheckInterval = Duration(hours: 24);

const _latestSeenKey = 'updateCheckLatestSeen';
const _lastCheckKey = 'updateCheckLastCheckMs';

/// Houdt de uitkomst van de versiecheck bij. autoDispose: buiten het
/// openscherm en het Over-tabblad kijkt niemand, en bij terugkeer wordt vers
/// bepaald of de dagelijkse check weer aan de beurt is.
final updateCheckProvider =
    NotifierProvider.autoDispose<UpdateCheckNotifier, UpdateCheckState>(
      UpdateCheckNotifier.new,
    );

class UpdateCheckNotifier extends Notifier<UpdateCheckState> {
  /// Volgnummer dat een laat-terugkomende check zijn eigen uitslag laat
  /// weggooien als de provider intussen opnieuw gebouwd is.
  int _generation = 0;

  @override
  UpdateCheckState build() {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.updateChecksEnabled),
    );
    final generation = ++_generation;
    unawaited(_restoreAndMaybeCheck(generation, enabled));
    return const UpdateCheckState();
  }

  Future<void> _restoreAndMaybeCheck(int generation, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString(_latestSeenKey);
    if (generation != _generation) return;
    if (seen != null && seen.isNotEmpty) {
      state = UpdateCheckState(latestVersion: seen);
    }
    if (!enabled || isWebPlatform) return;
    final lastCheck = DateTime.fromMillisecondsSinceEpoch(
      prefs.getInt(_lastCheckKey) ?? 0,
    );
    if (DateTime.now().difference(lastCheck) < kUpdateCheckInterval) return;
    await _runCheck(generation, manual: false);
  }

  /// Handmatige controle vanaf het Over-tabblad. Gebruiker-geïnitieerd en dus
  /// altijd toegestaan — óók als de automatische check uit staat, en ook op
  /// web niet (de servicelaag weigert daar zelf al).
  Future<void> checkNow() async {
    final generation = ++_generation;
    state = UpdateCheckState(
      latestVersion: state.latestVersion,
      checking: true,
    );
    await _runCheck(generation, manual: true);
  }

  Future<void> _runCheck(int generation, {required bool manual}) async {
    final result = await ref.read(updateCheckServiceProvider).fetchLatest();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Ook een gefaalde poging telt als "vandaag geprobeerd": een offline
      // machine hoeft de forge niet bij elke herstart opnieuw te vragen.
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      if (result != null) {
        await prefs.setString(_latestSeenKey, result.latestVersion);
      }
    } catch (e) {
      // Prefs onbereikbaar: de uitslag staat dan alleen in het geheugen. Dat
      // is prima — de check is toch niet beloofd te overleven.
      logWarning('versiecheck: uitslag bewaren mislukt', e);
    }
    if (generation != _generation) return;
    state = UpdateCheckState(
      latestVersion: result?.latestVersion ?? state.latestVersion,
      checkFailed: manual && result == null,
    );
  }
}
