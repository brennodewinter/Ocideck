// State for the "Managementsysteem" module (ISO_MANAGEMENTSYSTEEM §5):
// ISO 27001/9001/42001 progress reporting as an opt-in extension, off by
// default.
//
// Same contract as Procesverbetering / Importeren: reveal when the switch is on
// **or** the open deck already carries a `controlStatus` slide, so switching off
// never strands a deck (MODUS-REGEL — slides always render). Callers OR in
// [Deck.hasManagementSystemSlides] with this "module is on" half.
//
// Simpler than the Procesverbetering notifier: the ISO index is bundled `const`
// data (management_system_catalog.dart), so there is no catalog to warm on
// enable — only the preference to persist.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module_toggle.dart';

/// Preference key. Renaming afterwards would silently turn the module off for
/// existing installs.
const managementsysteemEnabledKey = 'managementsysteemModuleEnabled';

final managementsysteemProvider =
    NotifierProvider<ManagementsysteemNotifier, ModuleToggleState>(
      ManagementsysteemNotifier.new,
    );

/// Whether the switch is on.
final managementsysteemEnabledProvider = Provider<bool>((ref) {
  return ref.watch(managementsysteemProvider.select((s) => s.enabled));
});

/// Gate for menus and picker tabs: on, or the open deck already has a
/// `controlStatus` slide. Callers that know about a specific deck also OR in
/// [Deck.hasManagementSystemSlides] at the use site; this provider covers the
/// global "module is on" half.
final managementsysteemRevealProvider = Provider<bool>((ref) {
  return ref.watch(managementsysteemEnabledProvider);
});

class ManagementsysteemNotifier extends ModuleToggleNotifier {
  ManagementsysteemNotifier() : super(managementsysteemEnabledKey);
}
