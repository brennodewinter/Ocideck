/// The `controlStatus` slide's structured content (ISO_MANAGEMENTSYSTEEM §3.1):
/// a per-control implementation-status list for one management-system standard,
/// stored as a **plain Markdown table** in [Slide.tableRows] so it aligns with
/// the existing `table`/`checklist` handling and round-trips losslessly. This is
/// a typed *view* over the slide's title (the section heading) and its rows; the
/// editor and preview build/read it while storage stays a normal table.
///
/// The header row and the status/maturity words are **stable English anchors**
/// (like [ChecklistStatus.token]) so the table round-trips identically whatever
/// the interface language; the UI localises them for display. The progress
/// tally is **derived** from the rows, never stored.
library;

/// Where a control stands in its implementation (ISO_MANAGEMENTSYSTEEM §3.1).
/// This is the management-system equivalent of [ChecklistStatus] — but it tracks
/// *implementation*, not *testing*, so the states differ: a control moves from
/// not-started through planned/partial to implemented, or is judged not
/// applicable (a Statement of Applicability exclusion, which wants a reason in
/// the note).
enum ControlStatus {
  notStarted(''),
  planned('Planned'),
  partial('Partial'),
  implemented('Implemented'),
  notApplicable('NotApplicable');

  const ControlStatus(this.token);

  /// The canonical English cell value written to the table.
  final String token;

  /// Maps a stored cell value back to a status, tolerant of case and of an
  /// em-dash/empty cell (→ [notStarted]); anything unrecognised is [notStarted]
  /// so a hand-edited table never throws.
  static ControlStatus fromToken(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty || v == '—' || v == '-') return notStarted;
    for (final status in values) {
      if (status.token.toLowerCase() == v) return status;
    }
    return notStarted;
  }

  /// Whether this control counts in the *denominator* of the progress tally.
  /// Not-applicable controls are excluded — reporting 60/93 when 10 are out of
  /// scope understates progress; the honest base is the applicable controls.
  bool get isApplicable => this != notApplicable;

  /// Whether this control counts as fully done in the progress tally. Partial is
  /// shown but deliberately not counted as done — a conservative, honest metric.
  bool get isImplemented => this == implemented;

  /// The Dutch source label for the UI; localise with `l10n.d(status.dutchLabel)`
  /// at the call site (the model stays Flutter-free).
  String get dutchLabel => switch (this) {
    notStarted => 'Niet gestart',
    planned => 'Gepland',
    partial => 'Deels',
    implemented => 'Geïmplementeerd',
    notApplicable => 'Niet van toepassing',
  };
}

/// The maturity scale a control may optionally carry (0–5). 0 means *not rated*
/// — a control can have a status without anyone having scored its maturity yet —
/// and renders as an em-dash. Kept separate from [ControlStatus] because the two
/// answer different questions: status is "is it in place?", maturity is "how
/// well?". The progress tally counts status, never maturity.
const int controlMaturityMax = 5;

int _parseMaturity(String value) {
  final n = int.tryParse(value.trim());
  if (n == null || n < 0) return 0;
  return n > controlMaturityMax ? controlMaturityMax : n;
}

/// One control row: its id, its (canonical) title, the [status], an optional
/// [maturity] (0 = not rated), the responsible [owner], a [target] date/period,
/// an [evidence] reference, and a free [note].
class ControlStatusRow {
  const ControlStatusRow({
    this.id = '',
    this.control = '',
    this.status = ControlStatus.notStarted,
    this.maturity = 0,
    this.owner = '',
    this.target = '',
    this.evidence = '',
    this.note = '',
  });

  final String id;
  final String control;
  final ControlStatus status;
  final int maturity;
  final String owner;
  final String target;
  final String evidence;
  final String note;

  ControlStatusRow copyWith({
    String? id,
    String? control,
    ControlStatus? status,
    int? maturity,
    String? owner,
    String? target,
    String? evidence,
    String? note,
  }) {
    return ControlStatusRow(
      id: id ?? this.id,
      control: control ?? this.control,
      status: status ?? this.status,
      maturity: maturity ?? this.maturity,
      owner: owner ?? this.owner,
      target: target ?? this.target,
      evidence: evidence ?? this.evidence,
      note: note ?? this.note,
    );
  }
}

/// A `controlStatus` slide's structured content: a section heading (the slide
/// title, e.g. `ISO 27001 · Annex A — Organisatorisch (A.5)`) plus one row per
/// control. The tally is derived, never stored.
class ControlStatusSpec {
  const ControlStatusSpec({this.heading = '', this.rows = const []});

  /// The section heading text, shown as the slide title.
  final String heading;

  final List<ControlStatusRow> rows;

  /// The fixed English column headers written as the table's first row.
  static const header = [
    'ID',
    'Control',
    'Status',
    'Maturity',
    'Owner',
    'Target',
    'Evidence',
    'Note',
  ];

  int get total => rows.length;

  /// Controls that count toward progress (everything except not-applicable).
  int get applicableCount => rows.where((r) => r.status.isApplicable).length;

  int get implementedCount => rows.where((r) => r.status.isImplemented).length;

  /// Fully implemented as a share of the *applicable* controls, 0–100. Zero when
  /// nothing is applicable (a section entirely out of scope) so the reader never
  /// sees a divide-by-zero artefact.
  int get progressPercent => applicableCount == 0
      ? 0
      : (100 * implementedCount / applicableCount).round();

  /// Parse the typed rows from a slide's [title] + [tableRows]. The first table
  /// row is the header (skipped); each remaining row is read **by column
  /// position** so a localised or reordered header never misroutes a value. An
  /// em-dash in an optional column means "none".
  factory ControlStatusSpec.fromSlide(
    String title,
    List<List<String>> tableRows,
  ) {
    final rows = <ControlStatusRow>[];
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      if (i == 0 && _looksLikeHeader(cells)) continue;
      String at(int c) => c < cells.length ? cells[c].trim() : '';
      String clean(int c) {
        final v = at(c);
        return (v == '—' || v == '-') ? '' : v;
      }

      rows.add(
        ControlStatusRow(
          id: at(0),
          control: at(1),
          status: ControlStatus.fromToken(at(2)),
          maturity: _parseMaturity(at(3)),
          owner: clean(4),
          target: clean(5),
          evidence: clean(6),
          note: at(7),
        ),
      );
    }
    return ControlStatusSpec(heading: title, rows: rows);
  }

  static bool _looksLikeHeader(List<String> cells) {
    if (cells.isEmpty) return false;
    final first = cells.first.trim().toLowerCase();
    return first == 'id' || first == header.first.toLowerCase();
  }

  /// Build the table rows (header + one row per control) for [Slide.tableRows].
  /// Optional empty columns write an em-dash so the table stays rectangular and
  /// reads cleanly; a maturity of 0 (not rated) also renders as an em-dash.
  List<List<String>> toTableRows() => [
    header,
    for (final row in rows)
      [
        row.id,
        row.control,
        row.status.token,
        row.maturity == 0 ? '—' : '${row.maturity}',
        row.owner.isEmpty ? '—' : row.owner,
        row.target.isEmpty ? '—' : row.target,
        row.evidence.isEmpty ? '—' : row.evidence,
        row.note,
      ],
  ];

  ControlStatusSpec copyWith({String? heading, List<ControlStatusRow>? rows}) =>
      ControlStatusSpec(
        heading: heading ?? this.heading,
        rows: rows ?? this.rows,
      );
}
