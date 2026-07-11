/// The MIAUW **tri-state** for a checklist test (PENTEST_MIAUW §3.2). A row is
/// either not yet tested, tested without an anomaly, tested *with* an anomaly
/// (which links to a finding), or judged not testable (with a reason in the
/// note). The [token] is the stable, language-independent word stored in the
/// Markdown table — display labels are localised at the call site.
enum ChecklistStatus {
  notTested(''),
  tested('Tested'),
  anomaly('Anomaly'),
  notTestable('Not testable');

  const ChecklistStatus(this.token);

  /// The canonical English cell value written to the table.
  final String token;

  /// Maps a stored cell value back to a status, tolerant of case and of an
  /// em-dash/empty cell (→ [notTested]); anything unrecognised is [notTested]
  /// so a hand-edited table never throws.
  static ChecklistStatus fromToken(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty || v == '—' || v == '-') return notTested;
    for (final status in values) {
      if (status.token.toLowerCase() == v) return status;
    }
    return notTested;
  }

  /// Whether this counts toward the "tested" tally in the progress header.
  bool get isTested => this != notTested;

  /// The Dutch source label for the UI; localise with `l10n.d(status.dutchLabel)`
  /// at the call site (the model stays Flutter-free).
  String get dutchLabel => switch (this) {
    notTested => 'Niet getoetst',
    tested => 'Getoetst',
    anomaly => 'Afwijking',
    notTestable => 'Niet toetsbaar',
  };
}

/// One checklist row: a standard's test id, its name, the tri-state [status], an
/// optional link to a finding id, and a free note.
class ChecklistRow {
  const ChecklistRow({
    this.id = '',
    this.test = '',
    this.status = ChecklistStatus.notTested,
    this.findingId = '',
    this.note = '',
  });

  final String id;
  final String test;
  final ChecklistStatus status;
  final String findingId;
  final String note;

  ChecklistRow copyWith({
    String? id,
    String? test,
    ChecklistStatus? status,
    String? findingId,
    String? note,
  }) {
    return ChecklistRow(
      id: id ?? this.id,
      test: test ?? this.test,
      status: status ?? this.status,
      findingId: findingId ?? this.findingId,
      note: note ?? this.note,
    );
  }
}

/// A `checklist` slide's structured content (PENTEST_MIAUW §3.2): a
/// standard-driven test list stored as a **plain Markdown table** so it aligns
/// with the existing `table` slide handling and round-trips losslessly. This is
/// a typed *view* over the slide's title (the standard label) and its table
/// rows; the editor and preview build/read it, while storage stays a normal
/// table in `Slide.tableRows`.
///
/// The header row and the status words are **stable English anchors** (like a
/// finding's section headings) so the table round-trips identically regardless
/// of interface language; the UI localises them for display. The tested/total
/// progress is **derived** from the rows, never stored.
class ChecklistSpec {
  const ChecklistSpec({this.standardLabel = '', this.rows = const []});

  /// The heading text, e.g. `Checklist — OWASP WSTG`.
  final String standardLabel;

  final List<ChecklistRow> rows;

  /// The fixed English column headers written as the table's first row.
  static const header = ['ID', 'Test', 'Status', 'Finding', 'Note'];

  int get testedCount => rows.where((r) => r.status.isTested).length;
  int get total => rows.length;

  /// Parse the typed rows from a slide's [title] + [tableRows]. The first table
  /// row is the header (skipped); each remaining row is read **by column
  /// position** (id, test, status, finding, note) so a localised or reordered
  /// header never misroutes a value. A `—` in the finding column means "none".
  factory ChecklistSpec.fromSlide(String title, List<List<String>> tableRows) {
    final rows = <ChecklistRow>[];
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      // Skip a leading header row (matches our English header, case-insensitive)
      // so re-parsing our own output does not turn the header into a test row.
      if (i == 0 && _looksLikeHeader(cells)) continue;
      String at(int c) => c < cells.length ? cells[c].trim() : '';
      final finding = at(3);
      rows.add(
        ChecklistRow(
          id: at(0),
          test: at(1),
          status: ChecklistStatus.fromToken(at(2)),
          findingId: (finding == '—' || finding == '-') ? '' : finding,
          note: at(4),
        ),
      );
    }
    return ChecklistSpec(standardLabel: title, rows: rows);
  }

  static bool _looksLikeHeader(List<String> cells) {
    if (cells.isEmpty) return false;
    final first = cells.first.trim().toLowerCase();
    return first == 'id' || first == header.first.toLowerCase();
  }

  /// Build the table rows (header + one row per test) for [Slide.tableRows].
  List<List<String>> toTableRows() => [
    header,
    for (final row in rows)
      [
        row.id,
        row.test,
        row.status.token,
        row.findingId.isEmpty ? '—' : row.findingId,
        row.note,
      ],
  ];

  ChecklistSpec copyWith({String? standardLabel, List<ChecklistRow>? rows}) =>
      ChecklistSpec(
        standardLabel: standardLabel ?? this.standardLabel,
        rows: rows ?? this.rows,
      );
}
