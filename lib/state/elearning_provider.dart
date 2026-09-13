// State for the "eLearning" extension (#1999): one master switch for its
// eLearning slide types, package import and configured course entry.
//
// Same contract as Managementsysteem / Procesverbetering: reveal when the
// switch is on **or** the open deck already carries an eLearning slide, so
// switching off never strands a deck (MODUS-REGEL — slides always render).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/elearning_assessment.dart';
import 'module_toggle.dart';

/// Preference key. Renaming afterwards would silently turn the module off for
/// existing installs.
const elearningEnabledKey = 'elearningModuleEnabled';

final elearningProvider = NotifierProvider<ElearningNotifier, ModuleToggleState>(
  ElearningNotifier.new,
);

/// Whether the switch is on.
final elearningEnabledProvider = Provider<bool>((ref) {
  return ref.watch(elearningProvider.select((s) => s.enabled));
});

/// Gate for menus and picker tabs: on, or the open deck already has an
/// eLearning slide. Callers that know about a specific deck also OR in
/// [Deck.hasElearningSlides] at the use site; this provider covers the
/// global "module is on" half.
final elearningRevealProvider = Provider<bool>((ref) {
  return ref.watch(elearningEnabledProvider);
});

class ElearningNotifier extends ModuleToggleNotifier {
  ElearningNotifier() : super(elearningEnabledKey);

  /// Parse an eLearning sidecar (`<name>.elearning.json`) safely. Returns null
  /// on invalid JSON or a version from a newer build (#2006).
  ElearningSidecar? parseSidecar(String raw) => ElearningSidecar.parse(raw);
}
