import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_features.dart';
import '../services/ai_client_service.dart';
import '../services/ai_security_gate.dart';
import '../utils/log.dart';
import 'consent_provider.dart';
import 'secret_store_provider.dart';
import 'settings_provider.dart';

/// Wat het statuscentrum op het welkomscherm over de AI-backend weet.
enum AiAvailability {
  /// De module staat uit — het lampje wordt helemaal niet getoond.
  hidden,

  /// De gate laat het verzoek toe en de controle loopt nog.
  checking,

  /// De gate laat toe én de endpoint antwoordde op `GET /models`.
  reachable,

  /// De gate laat toe, maar de endpoint antwoordde niet (uit, timeout,
  /// HTTP-fout). Tijdelijk van aard: de server kan terugkomen.
  unreachable,

  /// De gate weigert vóór het netwerk — ontbrekende configuratie of
  /// toestemming. [AiStatus.denial] vertelt welke.
  denied,
}

/// De actuele AI-beschikbaarheid voor het statuscentrum. Bewust klein: de
/// tooltiptekst wordt in de widget uit [denial] afgeleid, zodat deze laag
/// taalvrij blijft.
class AiStatus {
  const AiStatus(this.availability, {this.denial});

  final AiAvailability availability;
  final AiGateDenial? denial;
}

/// De netwerknaad voor de statuscontrole. Tests overschrijven deze met een
/// nep-transport zodat geen test het netwerk raakt; de echte pin-transport is
/// dezelfde als de AI-client zelf gebruikt.
final aiHttpTransportProvider = Provider<AiHttpTransport>(
  (ref) => const PinnedAiHttpTransport(),
);

/// Periodieke herting van de endpoint zolang het statuscentrum zichtbaar is.
/// Een minuut is traag genoeg om nooit te spoken en snel genoeg om een
/// teruggekomen lokale server te tonen zonder dat de gebruiker iets doet.
const kAiStatusRefreshInterval = Duration(minutes: 1);

/// Houdt de AI-beschikbaarheid bij voor het statuscentrum. De poort
/// ([AiSecurityGate]) beslist zonder netwerk of er überhaupt gekeken mag
/// worden; alleen een allow leidt tot een `GET /models`-ping. autoDispose:
/// buiten het welkomscherm draait er niets en bij terugkeer wordt vers
/// gecontroleerd.
final aiStatusProvider =
    NotifierProvider.autoDispose<AiStatusNotifier, AiStatus>(
      AiStatusNotifier.new,
    );

class AiStatusNotifier extends Notifier<AiStatus> {
  Timer? _timer;
  int _generation = 0;

  @override
  AiStatus build() {
    final settings = ref.watch(settingsProvider.select((s) => s.aiSettings));
    final consent = ref.watch(consentProvider.select((s) => s.hasAccepted));
    ref.onDispose(() => _timer?.cancel());
    final generation = ++_generation;

    if (!settings.enabled) {
      return const AiStatus(AiAvailability.hidden);
    }
    final decision = AiSecurityGate.evaluate(
      settings,
      hasOutboundConsent: consent,
      cloudConfirmed: settings.cloudConfirmed,
      isWeb: isWebPlatform,
    );
    if (decision is AiGateDeny) {
      return AiStatus(AiAvailability.denied, denial: decision.reason);
    }

    // De gate laat toe: ping de endpoint en hertiek daarna rustig door. De
    // eerdere uitkomst blijft tijdens een herting staan — 'checking' flashen
    // bij elke interval tikt alleen maar onrust in.
    _timer ??= Timer.periodic(
      kAiStatusRefreshInterval,
      (_) => unawaited(_check(generation)),
    );
    unawaited(_check(generation));
    return const AiStatus(AiAvailability.checking);
  }

  /// Handmatige herting vanuit het statuscentrum (klik op het lampje). Toont
  /// bewust wél 'checking': de gebruiker deed iets en mag zien dat er iets
  /// gebeurt.
  Future<void> recheck() async {
    final generation = ++_generation;
    state = const AiStatus(AiAvailability.checking);
    await _check(generation);
  }

  Future<void> _check(int generation) async {
    final settings = ref.read(settingsProvider).aiSettings;
    String? apiKey;
    try {
      apiKey = await ref
          .read(secretStoreProvider)
          .readAiApiKey(settings.baseUrl);
    } catch (error, stack) {
      // Een onleesbare sleutelbos mag de status niet vastzetten: de endpoint
      // kan óók zonder sleutel antwoorden (lokale tier heeft er geen).
      logError('AiStatusNotifier._check: api-sleutel lezen', error, stack);
    }
    final client = AiClientService(
      settings: settings,
      hasOutboundConsent: ref.read(consentProvider).hasAccepted,
      apiKey: apiKey,
      transport: ref.read(aiHttpTransportProvider),
    );
    try {
      await client.testConnection();
      if (generation != _generation) return;
      state = const AiStatus(AiAvailability.reachable);
    } on AiGateException catch (e) {
      // De gate kan onderweg zijn veranderd (instellingen, toestemming).
      if (generation != _generation) return;
      state = AiStatus(AiAvailability.denied, denial: e.reason);
    } catch (error, stack) {
      logError('AiStatusNotifier._check: endpoint ping', error, stack);
      if (generation != _generation) return;
      state = const AiStatus(AiAvailability.unreachable);
    }
  }
}
