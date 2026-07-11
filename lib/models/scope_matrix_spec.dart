/// The type of a scope object, which **drives its required test standard**
/// (PENTEST_MIAUW §2.2 / §10.7): the mapping is fixed, so the standard is derived
/// from the type, never stored independently. The [token] is the stable English
/// word written to the Markdown table; [dutchLabel] is localised for the UI.
enum ScopeObjectType {
  web('Web', 'WSTG', 'Web'),
  infra('Infra', 'PTES', 'Infrastructuur'),
  iot('IoT', 'ISTG', 'IoT'),
  firmware('Firmware', 'FSTM', 'Firmware'),
  api('API', 'WSTG', 'API'),
  mobile('Mobile', 'MASTG', 'Mobiel'),
  other('Other', '', 'Overig');

  const ScopeObjectType(this.token, this.standard, this.dutchLabel);

  /// The on-disk English type token.
  final String token;

  /// The bound test standard for this object type (empty for [other]).
  final String standard;

  /// The Dutch source label for the UI; localise with `l10n.d(...)`.
  final String dutchLabel;

  static ScopeObjectType fromToken(String value) {
    final v = value.trim().toLowerCase();
    for (final type in values) {
      if (type.token.toLowerCase() == v) return type;
    }
    return other;
  }
}

/// Whether a scope object was tested, and how (PENTEST_MIAUW §4.4 / §4.13).
enum ScopeStatus {
  notTested(''),
  tested('Tested'),
  deviation('Deviation'),
  unreachable('Unreachable');

  const ScopeStatus(this.token);

  final String token;

  static ScopeStatus fromToken(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty || v == '—' || v == '-') return notTested;
    for (final status in values) {
      if (status.token.toLowerCase() == v) return status;
    }
    return notTested;
  }

  /// Whether this counts toward the "tested" coverage tally.
  bool get isTested => this != notTested;

  /// Dutch source label for the UI; localise with `l10n.d(status.dutchLabel)`.
  String get dutchLabel => switch (this) {
    notTested => 'Niet getest',
    tested => 'Getest',
    deviation => 'Afwijking',
    unreachable => 'Onbereikbaar',
  };
}

/// One scope-matrix row: the object, its type (which fixes the standard), how it
/// was covered, and a note.
class ScopeRow {
  const ScopeRow({
    this.object = '',
    this.type = ScopeObjectType.web,
    this.status = ScopeStatus.notTested,
    this.note = '',
  });

  final String object;
  final ScopeObjectType type;
  final ScopeStatus status;
  final String note;

  /// The test standard bound to this row's type (§10.7).
  String get standard => type.standard;

  ScopeRow copyWith({
    String? object,
    ScopeObjectType? type,
    ScopeStatus? status,
    String? note,
  }) {
    return ScopeRow(
      object: object ?? this.object,
      type: type ?? this.type,
      status: status ?? this.status,
      note: note ?? this.note,
    );
  }
}

/// A `scopeMatrix` slide's structured content (PENTEST_MIAUW §2.2 / §4.4): the
/// scope objects × their bound standard × the extent of testing, stored as a
/// **plain Markdown table** (like `checklist`) so it round-trips losslessly. A
/// typed *view* over the slide's title + table rows; the standard column is
/// derived from each object's type and the tested/total coverage is derived,
/// never stored.
class ScopeMatrixSpec {
  const ScopeMatrixSpec({this.title = '', this.rows = const []});

  final String title;
  final List<ScopeRow> rows;

  /// Fixed English column headers written as the table's first row.
  static const header = ['Object', 'Type', 'Standard', 'Status', 'Note'];

  int get testedCount => rows.where((r) => r.status.isTested).length;
  int get total => rows.length;

  /// Parse the typed rows from [title] + [tableRows]. The first table row is the
  /// header (skipped); columns are read by position (object, type, standard,
  /// status, note). The standard column is ignored on read — it is re-derived
  /// from the type, which is the source of truth.
  factory ScopeMatrixSpec.fromSlide(
    String title,
    List<List<String>> tableRows,
  ) {
    final rows = <ScopeRow>[];
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      if (i == 0 && _looksLikeHeader(cells)) continue;
      String at(int c) => c < cells.length ? cells[c].trim() : '';
      rows.add(
        ScopeRow(
          object: at(0),
          type: ScopeObjectType.fromToken(at(1)),
          status: ScopeStatus.fromToken(at(3)),
          note: at(4),
        ),
      );
    }
    return ScopeMatrixSpec(title: title, rows: rows);
  }

  static bool _looksLikeHeader(List<String> cells) {
    if (cells.isEmpty) return false;
    final first = cells.first.trim().toLowerCase();
    return first == 'object' || first == header.first.toLowerCase();
  }

  /// Build the table rows (header + one row per object) for [Slide.tableRows].
  List<List<String>> toTableRows() => [
    header,
    for (final row in rows)
      [
        row.object,
        row.type.token,
        row.type.standard,
        row.status.token,
        row.note,
      ],
  ];

  ScopeMatrixSpec copyWith({String? title, List<ScopeRow>? rows}) =>
      ScopeMatrixSpec(title: title ?? this.title, rows: rows ?? this.rows);
}
