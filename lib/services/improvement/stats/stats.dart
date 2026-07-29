// ── lib/services/improvement/stats/ ──────────────────────────────────────────
// The arithmetic of the Procesverbetering module, and only the arithmetic.
// Pure Dart: no Flutter, no network, no assets, no state. It computes; it never
// decides what to show. Everything a user sees — charts, panels, warnings — is
// built elsewhere from what these functions return.
//
// The rule for this directory is therefore narrower than elsewhere: a change
// belongs here when a published method says something different, not when
// OciDeck wants a friendlier number. Whatever the arithmetic refuses to give,
// no caller may fill in.
//
// Follows the shape of lib/services/cvss/: one library, split into `part`
// files, so the 1000-line file ratchet (tool/check_conventions.dart) is served
// without scattering the subject. File by file: docs/SOURCE_MAP.md.
// ─────────────────────────────────────────────────────────────────────────────
//
// Design decisions carried out of docs/design/PROCESS_IMPROVEMENT.md §4:
//
//   1. Native Dart, no dependency. There is no statistics package worth the
//      supply-chain surface, and a `pubspec.yaml` change forces `make sbom`.
//   2. Refuse rather than guess. Too few observations for a limit throws
//      [StatsRefusal] — a stated refusal, never a number nobody can defend.
//   3. Cp/Cpk never travels alone: every capability result carries the
//      Anderson-Darling normality verdict beside it.
//   4. The 1.5σ shift is off by default and named in every sigma-level result,
//      because "sigma level" means two different numbers in the field and the
//      shift is where two people get two answers.
//   5. Welford for variance, Householder QR for regression — the naïve
//      one-pass alternatives lose all precision on exactly the data an
//      improvement project collects (a tight spread far from zero).
library;

import 'dart:math' as math;

part 'capability.dart';
part 'constants.dart';
part 'control_charts.dart';
part 'descriptives.dart';
part 'distributions.dart';
part 'doe.dart';
part 'inference.dart';
part 'msa.dart';
part 'regression.dart';
part 'rules.dart';
part 'sampling.dart';

/// Thrown when the data cannot support the number that was asked for.
///
/// This is the engine's most important behaviour and the reason it throws
/// rather than returns a nullable: a control limit from three observations, a
/// Cpk from four, a Gage R&R from one operator — each is arithmetically
/// possible and methodologically worthless. A caller that wants a number
/// anyway has to say so in its own code, in the open, instead of receiving one
/// quietly.
class StatsRefusal implements Exception {
  const StatsRefusal(this.what, this.reason);

  /// The quantity that was asked for, e.g. `'X-bar/R control limits'`.
  final String what;

  /// Why it cannot be given, in terms of the data that was offered.
  final String reason;

  @override
  String toString() => 'StatsRefusal: $what — $reason';
}

/// Refuses [what] unless [count] reaches [minimum].
void _requireAtLeast(String what, String unit, int count, int minimum) {
  if (count < minimum) {
    throw StatsRefusal(what, 'needs at least $minimum $unit, got $count');
  }
}

/// How much reference data this engine carries locally, for the module card on
/// Settings → Uitbreidingen. Mirrors `cvss4LookupSize`: it exists so the screen
/// can show a number instead of a promise. The arithmetic never reads it.
int get improvementStatsFactorRows => _controlChartFactors.length;
