import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';

const _consentKey = 'app_consent_accepted';

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
      final prefs = await SharedPreferences.getInstance();
      final hasAccepted = prefs.getBool(_consentKey) ?? false;
      state = state.copyWith(hasAccepted: hasAccepted, isLoading: false);
    } catch (e, s) {
      // Can't read the flag: fail closed (gate stays up) but don't hang loading.
      logError('ConsentNotifier._initialize: read consent flag', e, s);
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> acceptConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentKey, true);
      state = state.copyWith(hasAccepted: true);
    } catch (e, s) {
      // Persisting failed; let the user through this session, but the gate will
      // reappear next launch. Surface the failure instead of swallowing it.
      logError('ConsentNotifier.acceptConsent: persist consent', e, s);
      state = state.copyWith(hasAccepted: true);
    }
  }

  Future<void> revokeConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentKey, false);
      state = state.copyWith(hasAccepted: false);
    } catch (e, s) {
      // Asymmetrisch met acceptConsent, en gevaarlijker: de vlag op schijf
      // blijft `true`. Deze sessie gedraagt zich als ingetrokken, de volgende
      // start leest de oude toestemming terug en toont de poort dus NIET —
      // de intrekking is stil verdampt. Het log is voorlopig de enige plek
      // waar dat te zien is; de gebruiker krijgt er nog geen melding van.
      logError('ConsentNotifier.revokeConsent: persist revocation', e, s);
      state = state.copyWith(hasAccepted: false);
    }
  }
}
