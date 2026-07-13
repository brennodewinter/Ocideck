import '../services/cvss/cvss4.dart';
import '../services/finding_context_score.dart';
import 'finding_spec.dart';
import 'slide.dart';

/// A `findingsSummary` slide's structured content (PENTEST_MIAUW §4.3.4 / §11):
/// a management overview of how many findings fall in each CVSS 4.0 severity
/// band. A typed *view* over the slide's title + a small counts table; the
/// [total] is derived, never stored.
///
/// Unlike the per-finding severity (which is always derived live from the
/// vector), the summary counts are a **deliberate snapshot**: a management
/// roll-up is a point-in-time figure the author refreshes from the deck's
/// findings (via the editor's "refresh from deck"), not a live mirror. Storing
/// the snapshot keeps the slide self-contained — it round-trips losslessly as a
/// plain Markdown table (like `checklist` / `scopeMatrix`) and renders
/// identically in a headless export isolate. A later step (P2-MSUM) adds the
/// automated regeneration; the domain-consistency lint (§10.10) is what catches
/// a snapshot that has drifted from the findings.
class FindingsSummarySpec {
  const FindingsSummarySpec({this.title = '', this.counts = const {}});

  final String title;

  /// Findings per severity band. An absent band reads as zero; [order] fixes the
  /// worst-first display sequence.
  final Map<Cvss4Severity, int> counts;

  /// Fixed English column headers written as the table's first row.
  static const header = ['Severity', 'Count'];

  /// The bands in management-report order (Critical → Informational). Every band
  /// is always rendered/written so the chart axis and the round-trip stay stable.
  static const order = [
    Cvss4Severity.critical,
    Cvss4Severity.high,
    Cvss4Severity.medium,
    Cvss4Severity.low,
    Cvss4Severity.none,
  ];

  int countOf(Cvss4Severity band) => counts[band] ?? 0;

  /// The total number of findings across all bands.
  int get total => order.fold(0, (sum, band) => sum + countOf(band));

  /// Aggregate one [severities] entry per finding into per-band counts.
  factory FindingsSummarySpec.fromSeverities(
    String title,
    Iterable<Cvss4Severity> severities,
  ) {
    final counts = <Cvss4Severity, int>{};
    for (final band in severities) {
      counts[band] = (counts[band] ?? 0) + 1;
    }
    return FindingsSummarySpec(title: title, counts: counts);
  }

  /// Parse the typed counts from [title] + [tableRows]. The first row is the
  /// header (skipped); each remaining row is `severity-token | count`. An
  /// unrecognised band or a non-numeric/negative count is ignored, so a
  /// hand-edited table degrades gracefully instead of throwing.
  factory FindingsSummarySpec.fromSlide(
    String title,
    List<List<String>> tableRows,
  ) {
    final counts = <Cvss4Severity, int>{};
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      if (cells.isEmpty) continue;
      if (i == 0 && _looksLikeHeader(cells)) continue;
      final band = _bandFromToken(cells.first);
      if (band == null) continue;
      final n = int.tryParse((cells.length > 1 ? cells[1] : '').trim());
      if (n == null || n < 0) continue;
      counts[band] = n;
    }
    return FindingsSummarySpec(title: title, counts: counts);
  }

  static bool _looksLikeHeader(List<String> cells) =>
      cells.first.trim().toLowerCase() == header.first.toLowerCase();

  /// Build the table rows (header + one row per band, always all five in
  /// [order]) for [Slide.tableRows]. The severity token is the stable English
  /// FIRST band name so the round-trip is language-independent.
  List<List<String>> toTableRows() => [
    header,
    for (final band in order) [band.label, '${countOf(band)}'],
  ];

  static Cvss4Severity? _bandFromToken(String token) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final band in Cvss4Severity.values) {
      if (band.label.toLowerCase() == t) return band;
    }
    // Management convention: the FIRST "None" band is presented as the
    // "Informational" row, so accept either spelling on read.
    if (t == 'informational' || t == 'informatief') return Cvss4Severity.none;
    return null;
  }

  FindingsSummarySpec copyWith({
    String? title,
    Map<Cvss4Severity, int>? counts,
  }) => FindingsSummarySpec(
    title: title ?? this.title,
    counts: counts ?? this.counts,
  );
}

/// The Dutch source label for a severity [band] as shown in a findings summary.
/// A management roll-up presents the FIRST "None" band as "Informatief"
/// (Informational). Localise the result with `l10n.d(...)`. Shared by the
/// findingsSummary editor and preview so the labels never drift.
String findingsSeverityDutchLabel(Cvss4Severity band) => switch (band) {
  Cvss4Severity.critical => 'Kritiek',
  Cvss4Severity.high => 'Hoog',
  Cvss4Severity.medium => 'Middel',
  Cvss4Severity.low => 'Laag',
  Cvss4Severity.none => 'Informatief',
};

/// Derive the **effective** severity band of every finding in [slides]: each
/// `finding` header slide contributes its finding's context (CIA-weighted) band
/// when its scope object is rated on the scope matrix, otherwise its base band
/// (an absent or invalid vector counts as [Cvss4Severity.none] — an
/// informational finding). Detail and evidence slides of a group are skipped so
/// each finding is counted once. Using the effective band keeps the management
/// roll-up consistent with what the finding shows in the report (§10.3/§10.5).
///
/// Shared by the findingsSummary editor's "refresh from deck" action and the
/// management-summary derivation.
List<Cvss4Severity> deckFindingSeverities(Iterable<Slide> slides) {
  final list = slides is List<Slide> ? slides : slides.toList();
  final ciaIndex = deckScopeCiaIndex(list);
  return [
    for (final slide in list)
      if (slide.type == SlideType.finding &&
          slide.findingRole == FindingRole.header)
        findingEffectiveSeverity(
              FindingSpec.parse(slide.customMarkdown),
              ciaIndex,
            ) ??
            Cvss4Severity.none,
  ];
}
