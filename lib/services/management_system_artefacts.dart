import '../models/chart.dart';
import 'management_system_progress.dart';

/// Report artefacts derived from the management-system progress
/// (ISO_MANAGEMENTSYSTEEM §6): the burn-up chart. Pure functions over
/// [ManagementSystemProgress] so they are testable and Flutter-free; the deck
/// action wraps the result in a slide and localises the labels at the call site.

/// Green for the implemented controls, grey for the remaining applicable ones —
/// deterministic hexes (matching the checklist/scope status tokens) so the chart
/// renders identically in an export isolate rather than following the deck's
/// series palette, which would drop the done/todo meaning.
const _implementedColor = '#15803D';
const _remainingColor = '#94A3B8';

/// A **burn-up** chart of implementation progress: one horizontal bar per
/// `controlStatus` section, stacked as *implemented* (green) + *remaining*
/// (grey), so each bar's length is the section's applicable controls and its
/// green portion is how far it has burned up toward done. Derived from the deck,
/// a snapshot like the overview table — regenerate to refresh.
///
/// Not-applicable controls are already out of [ControlSectionProgress.applicable],
/// so a section that is entirely out of scope shows an empty bar rather than a
/// misleading full one. Returns an empty spec when there is nothing to plot.
ChartSpec buildManagementSystemProgressChart(
  ManagementSystemProgress progress, {
  required String chartTitle,
  required String implementedLabel,
  required String remainingLabel,
}) {
  if (progress.isEmpty) return const ChartSpec();
  return ChartSpec(
    type: ChartType.horizontalStackedBar,
    title: chartTitle,
    x: [for (final s in progress.sections) s.heading],
    series: [
      ChartSeries(
        name: implementedLabel,
        data: [for (final s in progress.sections) s.implemented.toDouble()],
        color: _implementedColor,
      ),
      ChartSeries(
        name: remainingLabel,
        data: [
          for (final s in progress.sections)
            (s.applicable - s.implemented).toDouble(),
        ],
        color: _remainingColor,
      ),
    ],
  );
}
