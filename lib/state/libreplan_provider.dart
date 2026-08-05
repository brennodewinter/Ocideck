/// Riverpod-handvatten voor de LibrePlan-connector-module.
///
/// Spiegelt het patroon uit `module_registry.dart` voor AI: een enabled-provider
/// (de bewaarde schakelaar) en een reveal-provider (aan, óf er is al een server
/// geconfigureerd — zodat uitzetten bestaand werk niet onbereikbaar maakt, #648).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

/// Of de LibrePlan-schakelaar aan staat (de bewaarde stand, niet het formulier).
final libreplanEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider.select((s) => s.libreplanSettings.enabled));
});

/// LibrePlan-reveal op providerniveau: de module is zichtbaar zodra de
/// schakelaar aan staat óf er een server geconfigureerd is. Spiegelt
/// `aiModuleRevealProvider`.
final libreplanRevealProvider = Provider<bool>((ref) {
  final lp = ref.watch(settingsProvider.select((s) => s.libreplanSettings));
  return lp.enabled || lp.hasBackend;
});
