import '../models/control_status_spec.dart';
import '../models/deck.dart';
import '../models/slide.dart';

/// Managementsysteem-voortgang, afgeleid uit de deck (ISO_MANAGEMENTSYSTEEM §6):
/// het overzicht **regenereert uit de `controlStatus`-dia's**, zodat het per
/// constructie klopt met de details — precies zoals de MIAUW-compliance-overview
/// en de management-summary dat doen. Geen opslag: altijd op aanvraag afgeleid.

/// The roll-up of one `controlStatus` slide: its heading plus the tallies the
/// overview needs. All counts are derived from the rows, never stored.
class ControlSectionProgress {
  const ControlSectionProgress({
    required this.heading,
    required this.total,
    required this.applicable,
    required this.implemented,
    required this.partial,
  });

  final String heading;
  final int total;
  final int applicable;
  final int implemented;
  final int partial;

  /// Fully implemented as a share of the *applicable* controls, 0–100 (0 when a
  /// section is entirely out of scope, so no divide-by-zero).
  int get progressPercent =>
      applicable == 0 ? 0 : (100 * implemented / applicable).round();

  factory ControlSectionProgress.fromSpec(ControlStatusSpec spec) {
    return ControlSectionProgress(
      heading: spec.heading,
      total: spec.total,
      applicable: spec.applicableCount,
      implemented: spec.implementedCount,
      partial: spec.rows.where((r) => r.status == ControlStatus.partial).length,
    );
  }
}

/// The deck-wide progress: one [ControlSectionProgress] per `controlStatus`
/// slide, plus derived totals across them.
class ManagementSystemProgress {
  const ManagementSystemProgress(this.sections);

  final List<ControlSectionProgress> sections;

  bool get isEmpty => sections.isEmpty;

  int get total => sections.fold(0, (a, s) => a + s.total);
  int get applicable => sections.fold(0, (a, s) => a + s.applicable);
  int get implemented => sections.fold(0, (a, s) => a + s.implemented);
  int get partial => sections.fold(0, (a, s) => a + s.partial);

  /// Fully implemented as a share of all *applicable* controls, 0–100.
  int get progressPercent =>
      applicable == 0 ? 0 : (100 * implemented / applicable).round();
}

/// Derive the management-system progress from every `controlStatus` slide in
/// [deck], in slide order. A deck with no such slides yields an empty result
/// (never a misleading 0/0 "100%").
ManagementSystemProgress deckManagementSystemProgress(Deck deck) {
  final sections = <ControlSectionProgress>[];
  for (final slide in deck.slides) {
    if (slide.type != SlideType.controlStatus) continue;
    sections.add(
      ControlSectionProgress.fromSpec(
        ControlStatusSpec.fromSlide(slide.title, slide.tableRows),
      ),
    );
  }
  return ManagementSystemProgress(sections);
}
