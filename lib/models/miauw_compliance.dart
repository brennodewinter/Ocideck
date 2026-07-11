import 'eis_entry.dart';

/// The compliance status of one EIS in the overview (PENTEST_MIAUW §9).
enum EisStatus {
  /// Content check passed (or a manual requirement was confirmed).
  voldaan,

  /// The requirement is not (yet) met — the gap.
  open,

  /// Excluded by the client, with a mandatory reason.
  uitgesloten,
}

/// The evaluated status of a single [EisEntry] against a deck.
class EisResult {
  const EisResult({
    required this.entry,
    required this.status,
    this.waiverReason,
  });

  final EisEntry entry;
  final EisStatus status;

  /// The client's exclusion reason, set only when [status] is
  /// [EisStatus.uitgesloten].
  final String? waiverReason;
}

/// The full MIAUW compliance overview: one [EisResult] per requirement in the
/// bundled schema, plus derived roll-ups. A gap analysis, never a hard gate
/// (§9) — the panel may warn but never blocks.
class MiauwComplianceResult {
  const MiauwComplianceResult(this.results);

  final List<EisResult> results;

  int _count(EisStatus s) => results.where((r) => r.status == s).length;

  int get metCount => _count(EisStatus.voldaan);
  int get openCount => _count(EisStatus.open);
  int get waivedCount => _count(EisStatus.uitgesloten);
  int get total => results.length;

  bool get hasOpen => openCount > 0;

  /// The results belonging to [part], in schema order.
  List<EisResult> forPart(EisPart part) => [
    for (final r in results)
      if (r.entry.part == part) r,
  ];

  /// The foundational requirements (1.1 delivery+hash, 1.6 truthful sign-off)
  /// that were excluded — the panel warns about these, but still never blocks.
  List<EisResult> get foundationalWaived => [
    for (final r in results)
      if (r.status == EisStatus.uitgesloten &&
          (r.entry.id == '1.1' || r.entry.id == '1.6'))
        r,
  ];
}
