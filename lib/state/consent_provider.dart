import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

const _consentKey = 'app_consent_accepted';

/// Waar de toestemmingsvlag vandaan komt en naartoe gaat.
///
/// Een eigen laagje over `SharedPreferences`, omdat de interessante gevallen
/// hier juist de FOUTgevallen zijn: lezen mislukt (de poort blijft dicht) en
/// schrijven mislukt (de intrekking verdampt bij de volgende start). Met
/// `SharedPreferences.getInstance()` rechtstreeks in de notifier is geen van
/// die paden af te dwingen in een test — de mock slaagt altijd — en dan is de
/// afhandeling ervan een bewering die niemand ooit toetst.
abstract interface class ConsentStore {
  /// De opgeslagen vlag; `false` wanneer er nog niets is vastgelegd.
  Future<bool> read();

  /// Legt de vlag vast. Gooit wanneer dat niet lukt — stil falen is precies
  /// wat hierboven wordt beschreven.
  Future<void> write(bool value);
}

class SharedPreferencesConsentStore implements ConsentStore {
  const SharedPreferencesConsentStore();

  @override
  Future<bool> read() async =>
      (await SharedPreferences.getInstance()).getBool(_consentKey) ?? false;

  @override
  Future<void> write(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_consentKey, value);
}

/// De opslag die [ConsentNotifier] gebruikt. Tests overschrijven hem met een
/// winkel die faalt, zodat de foutpaden echt gedrag zijn en geen dode tekst.
final consentStoreProvider = Provider<ConsentStore>(
  (ref) => const SharedPreferencesConsentStore(),
);

final consentProvider = NotifierProvider<ConsentNotifier, ConsentState>(() {
  return ConsentNotifier();
});

class ConsentState {
  final bool hasAccepted;
  final bool isLoading;

  const ConsentState({required this.hasAccepted, this.isLoading = false});

  ConsentState copyWith({bool? hasAccepted, bool? isLoading}) {
    return ConsentState(
      hasAccepted: hasAccepted ?? this.hasAccepted,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ConsentNotifier extends Notifier<ConsentState> {
  @override
  ConsentState build() {
    _initialize();
    return const ConsentState(hasAccepted: false, isLoading: true);
  }

  Future<void> _initialize() async {
    try {
      final hasAccepted = await ref.read(consentStoreProvider).read();
      state = state.copyWith(hasAccepted: hasAccepted, isLoading: false);
    } catch (e, s) {
      // Can't read the flag: fail closed (gate stays up) but don't hang loading.
      logError('ConsentNotifier._initialize: read consent flag', e, s);
      state = state.copyWith(isLoading: false);
    }
  }

  /// Legt de toestemming vast. Geeft `false` terug wanneer dat niet lukte.
  Future<bool> acceptConsent() async {
    try {
      await ref.read(consentStoreProvider).write(true);
      state = state.copyWith(hasAccepted: true);
      return true;
    } catch (e, s) {
      // Persisting failed; let the user through this session, but the gate will
      // reappear next launch. Surface the failure instead of swallowing it.
      logError('ConsentNotifier.acceptConsent: persist consent', e, s);
      state = state.copyWith(hasAccepted: true);
      return false;
    }
  }

  /// Trekt de toestemming in. Geeft `false` terug wanneer het wegschrijven
  /// mislukte — en dát is het gevaarlijke geval, niet het spiegelbeeld van
  /// [acceptConsent]: de vlag op schijf blijft dan `true`. Deze sessie gedraagt
  /// zich als ingetrokken, maar de volgende start leest de oude toestemming
  /// terug en toont de poort dus NIET. De gebruiker denkt te hebben ingetrokken
  /// terwijl er niets is ingetrokken; daarom moet de aanroeper dit tonen en niet
  /// wegslikken.
  Future<bool> revokeConsent() async {
    try {
      await ref.read(consentStoreProvider).write(false);
      state = state.copyWith(hasAccepted: false);
      return true;
    } catch (e, s) {
      logError('ConsentNotifier.revokeConsent: persist revocation', e, s);
      state = state.copyWith(hasAccepted: false);
      return false;
    }
  }
}
