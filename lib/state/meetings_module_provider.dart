// State voor de module "Onlinevergaderingen" (TEAMS_GUEST_CLIENT.md T13):
// meedoen aan een vergadering van een andere aanbieder, standaard uit.
//
// Uit betekent hier meer dan een verborgen knop. Er is geen schilactie, geen
// menu-item en — zodra er een echte adapter is — geen enkele verbinding met
// een aanbieder of tokendienst. Dat maakt T8 ("het laden van OciDeck neemt geen
// contact op") toetsbaar voor wie deze functie nooit wil: de belofte is niet
// "we bellen pas als u klikt" maar "er is niets dat kán bellen".
//
// Eén schakelaar voor bellen als geheel, niet één per aanbieder. Een gebruiker
// denkt "doe ik vergaderingen vanuit hier", niet "wil ik adapter nummer vier";
// wat er per aanbieder geldt hoort in het register van `COLLABORATION.md`
// §7.1.2 en in `lib/meetings/meeting_registry.dart`, niet op het
// instellingenscherm.
//
// De onthulling is `aan || sessie actief`. Bij de andere modules betekent de
// projectregel "uitzetten mag bestaand werk nooit onbereikbaar maken" dat een
// gemaakte checklist of een ingestelde map bereikbaar blijft; hier is er niets
// bewaards en betekent diezelfde regel iets letterlijkers — een lopend gesprek
// mag niet stilvallen doordat iemand een schakelaar omzet, en `Verlaten` moet
// bereikbaar blijven (§17).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';
import 'meeting_session_provider.dart';

/// De voorkeursleutel van de schakelaar. Hernoemen mag hierna niet meer: dan
/// staat de module bij een bestaande installatie stil weer uit.
const _enabledKey = 'meetingsModuleEnabled';

final meetingsModuleProvider =
    NotifierProvider<MeetingsModuleNotifier, MeetingsModuleState>(
      MeetingsModuleNotifier.new,
    );

/// Of de schakelaar aan staat.
///
/// Harde standaard uit, en bewust géén afgeleide van de inhoud zoals bij Online
/// opslag: er ís geen bestaande configuratie die deze module al gebruikte, dus
/// een nieuwe installatie start uit, punt.
final meetingsModuleEnabledProvider = Provider<bool>((ref) {
  return ref.watch(meetingsModuleProvider.select((s) => s.enabled));
});

/// De poort waar de schilactie en de menu-items op kijken: aan, óf er loopt een
/// gesprek.
final meetingsModuleRevealProvider = Provider<bool>((ref) {
  return ref.watch(meetingsModuleEnabledProvider) ||
      ref.watch(meetingSessionActiveProvider);
});

class MeetingsModuleState {
  /// Of de module aan staat. Standaard uit.
  final bool enabled;

  /// Voorkeuren worden nog geladen bij de eerste opbouw.
  final bool loading;

  const MeetingsModuleState({this.enabled = false, this.loading = true});

  MeetingsModuleState copyWith({bool? enabled, bool? loading}) =>
      MeetingsModuleState(
        enabled: enabled ?? this.enabled,
        loading: loading ?? this.loading,
      );
}

class MeetingsModuleNotifier extends Notifier<MeetingsModuleState> {
  @override
  MeetingsModuleState build() {
    _initialize();
    return const MeetingsModuleState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = MeetingsModuleState(
        enabled: prefs.getBool(_enabledKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      // Onleesbare voorkeuren: de module blijft uit — de veilige kant — maar
      // het laden stopt wél, anders blijft de kaart hangen.
      logError('MeetingsModuleNotifier._initialize: read module state', e, s);
      state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = MeetingsModuleState(enabled: value, loading: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, s) {
      // De stand voor deze sessie staat al; alleen het bewaren ging mis.
      logError('MeetingsModuleNotifier: prefs-schrijf mislukt', e, s);
    }
  }
}
