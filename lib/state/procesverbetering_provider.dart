// State for the "Procesverbetering" module (PROCESS_IMPROVEMENT.md Phase 0):
// Process-improvement authoring as an opt-in extension, off by default.
//
// Same contract as Importeren / Online opslag: reveal when content already
// exists, so switching off never strands a deck that already carries
// improvement slides (MODUS-REGEL — slides always render). Callers OR in
// [Deck.hasImprovementSlides] (true once a `matrix` / later engine type is
// present) with the enabled preference.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/improvement/improvement_template_catalog.dart';
import 'module_toggle.dart';

/// Preference key. Renaming afterwards would silently turn the module off for
/// existing installs.
const procesverbeteringEnabledKey = 'procesverbeteringModuleEnabled';

final procesverbeteringProvider =
    NotifierProvider<ProcesverbeteringNotifier, ModuleToggleState>(
      ProcesverbeteringNotifier.new,
    );

/// Whether the switch is on.
final procesverbeteringEnabledProvider = Provider<bool>((ref) {
  return ref.watch(procesverbeteringProvider.select((s) => s.enabled));
});

/// Gate for menus and picker tabs: on, or the open deck already has
/// improvement slides. Callers that know about a specific deck also OR in
/// [Deck.hasImprovementSlides] at the use site; this provider covers the
/// global "module is on" half.
final procesverbeteringRevealProvider = Provider<bool>((ref) {
  return ref.watch(procesverbeteringEnabledProvider);
});

class ProcesverbeteringNotifier extends ModuleToggleNotifier {
  ProcesverbeteringNotifier() : super(procesverbeteringEnabledKey);

  /// Warm the artefact catalog when the module is switched on so editors
  /// never open against an empty floor-only race with the asset load.
  @override
  Future<void> onEnabled() async {
    // ignore: unawaited_futures
    ImprovementTemplateCatalog.instance.ensureLoaded();
  }
}
