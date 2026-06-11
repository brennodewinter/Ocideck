import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _consentKey = 'app_consent_accepted';

final consentProvider =
    NotifierProvider<ConsentNotifier, ConsentState>(() {
  return ConsentNotifier();
});

class ConsentState {
  final bool hasAccepted;
  final bool isLoading;

  const ConsentState({
    required this.hasAccepted,
    this.isLoading = false,
  });

  ConsentState copyWith({
    bool? hasAccepted,
    bool? isLoading,
  }) {
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
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> acceptConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentKey, true);
      state = state.copyWith(hasAccepted: true);
    } catch (e) {
      state = state.copyWith(hasAccepted: true);
    }
  }

  Future<void> revokeConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentKey, false);
      state = state.copyWith(hasAccepted: false);
    } catch (e) {
      state = state.copyWith(hasAccepted: false);
    }
  }
}
