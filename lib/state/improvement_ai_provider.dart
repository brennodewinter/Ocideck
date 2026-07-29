import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_client_service.dart';
import '../services/secret_store.dart';
import 'consent_provider.dart';
import 'module_registry.dart';
import 'procesverbetering_provider.dart';
import 'settings_provider.dart';

/// AI-assist for Procesverbetering slides is available only when **both**
/// the AI module and the Procesverbetering module are on and a backend is
/// configured (PROCESS_IMPROVEMENT §9 / AI_ASSIST §3).
final improvementAiAvailableProvider = Provider<bool>((ref) {
  if (!ref.watch(aiModuleEnabledProvider)) return false;
  if (!ref.watch(procesverbeteringEnabledProvider)) return false;
  final ai = ref.watch(settingsProvider.select((s) => s.aiSettings));
  return ai.isConfigured;
});

/// Builds the [AiClientService] used by Procesverbetering suggest controls.
/// Overridable in tests so keychain and network stay out of widget pumps.
typedef ImprovementAiClientFactory = Future<AiClientService> Function();

final improvementAiClientFactoryProvider = Provider<ImprovementAiClientFactory>(
  (ref) {
    return () async {
      final settings = ref.read(settingsProvider).aiSettings;
      return AiClientService(
        settings: settings,
        hasOutboundConsent: ref.read(consentProvider).hasAccepted,
        apiKey: await SecretStore().readAiApiKey(settings.baseUrl),
      );
    };
  },
);
