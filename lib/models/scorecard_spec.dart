/// The most figures a scorecard shows. Five numbers side by side still read as
/// a verdict; a sixth turns the slide into a table, which is what the `table`
/// type is for. Applied on both read and write (like [cockpitMaxMeters]), so a
/// deck that round-trips twice keeps the same shape.
const int scorecardMaxEntries = 5;

/// Whether a *rise* in a figure is good news, bad news, or neither.
///
/// The deck cannot derive this: more assets in view is good when you are
/// inventorying and bad when you are decommissioning, and only the author knows
/// which story this report tells. Keeping it explicit is what lets the preview
/// colour a downward arrow green without ever guessing.
///
/// Note that polarity decides the *colour* of a change, never its *direction* —
/// the numbers alone decide that. Conflating the two produces a green arrow
/// pointing down that no reader can interpret.
enum ScorecardPolarity {
  lowerBetter('lower-better'),
  higherBetter('higher-better'),
  neutral('neutral');

  const ScorecardPolarity(this.token);

  /// The stable English token written to disk, so the round-trip is
  /// language-independent (same convention as the severity band names).
  final String token;
}

/// Which way a figure moved since the previous report.
enum ScorecardDirection { up, down, flat }

/// How that movement should read: [good] and [bad] carry colour, [neutral] does
/// not. Derived from [ScorecardDirection] and [ScorecardPolarity] together.
enum ScorecardSentiment { good, bad, neutral }

/// Below this, two doubles count as the same figure. Guards against a
/// float-rounding artefact rendering as a change of nothing.
const double _epsilon = 1e-9;

/// One figure on a scorecard: what it is, what it is now, and what it was.
class ScorecardEntry {
  const ScorecardEntry({
    this.label = '',
    this.value,
    this.previous,
    this.unit = '',
    this.polarity = ScorecardPolarity.neutral,
  });

  final String label;

  /// The figure now, or null while the author is still filling the row in. A
  /// row being typed genuinely has no number yet, and inventing a zero for it
  /// would put a figure on the slide that nobody chose.
  final double? value;

  /// The same figure in the previous report, or null when there is none — a
  /// first report, or a figure newly added to the set.
  ///
  /// Deliberately the *previous value* rather than a pre-computed delta: the
  /// difference is then derived and always agrees with the two numbers, and the
  /// slide can also show what the figure was. A delta typed in by hand is a
  /// third number that nothing checks.
  final double? previous;

  final String unit;
  final ScorecardPolarity polarity;

  /// Nothing at all in this row — the shape the editor hands out for a figure
  /// the author has not started on. Dropped on both read and write, so an
  /// untouched row never reaches the slide and the round-trip stays a fixed
  /// point.
  bool get isBlank => label.trim().isEmpty && value == null && previous == null;

  /// The change since the previous report, or null when there is nothing to
  /// compare against. Callers must render *no* delta in that case — a "+0"
  /// claims the figure held steady when in fact it was never measured before.
  double? get delta =>
      value == null || previous == null ? null : value! - previous!;

  /// Which way the figure moved, or null when there is no previous figure.
  ScorecardDirection? get direction {
    final d = delta;
    if (d == null) return null;
    if (d.abs() < _epsilon) return ScorecardDirection.flat;
    return d > 0 ? ScorecardDirection.up : ScorecardDirection.down;
  }

  /// Whether the movement is good or bad news, given [polarity]. A figure that
  /// did not move, one with no previous value, and one the author marked
  /// [ScorecardPolarity.neutral] all read as [ScorecardSentiment.neutral] — the
  /// change is shown, the judgement is withheld.
  ScorecardSentiment get sentiment {
    final dir = direction;
    if (dir == null || dir == ScorecardDirection.flat) {
      return ScorecardSentiment.neutral;
    }
    final rose = dir == ScorecardDirection.up;
    return switch (polarity) {
      ScorecardPolarity.higherBetter =>
        rose ? ScorecardSentiment.good : ScorecardSentiment.bad,
      ScorecardPolarity.lowerBetter =>
        rose ? ScorecardSentiment.bad : ScorecardSentiment.good,
      ScorecardPolarity.neutral => ScorecardSentiment.neutral,
    };
  }

  ScorecardEntry copyWith({
    String? label,
    double? value,
    double? previous,
    bool clearPrevious = false,
    String? unit,
    ScorecardPolarity? polarity,
  }) => ScorecardEntry(
    label: label ?? this.label,
    value: value ?? this.value,
    previous: clearPrevious ? null : (previous ?? this.previous),
    unit: unit ?? this.unit,
    polarity: polarity ?? this.polarity,
  );
}

/// A `scorecard` slide's structured content: a handful of headline figures,
/// each with the figure it replaces, so a recurring report leads with what
/// changed rather than with what the number happens to be.
///
/// A typed *view* over the slide's title + a small Markdown table, exactly like
/// [FindingsSummarySpec] / `checklist` / `scopeMatrix`: it round-trips losslessly
/// as plain Markdown, stays readable and editable outside the app, and renders
/// identically in a headless export isolate.
class ScorecardSpec {
  const ScorecardSpec({this.title = '', this.entries = const []});

  final String title;
  final List<ScorecardEntry> entries;

  /// Fixed English column headers written as the table's first row.
  static const header = ['Label', 'Value', 'Previous', 'Unit', 'Polarity'];

  bool get isEmpty => entries.isEmpty;

  /// Parse the typed figures from [title] + [tableRows]. The first row is the
  /// header (skipped when it looks like one).
  ///
  /// Tolerant in the same way as the other table-backed specs, so a hand-edited
  /// or machine-generated table degrades instead of throwing: an entirely blank
  /// row is dropped, an unreadable figure leaves that half empty rather than
  /// costing the whole row, and an unrecognised polarity falls back to neutral —
  /// showing the change but withholding the colour, which is the safe half of
  /// the guess.
  factory ScorecardSpec.fromSlide(String title, List<List<String>> tableRows) {
    final entries = <ScorecardEntry>[];
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      if (cells.isEmpty) continue;
      if (i == 0 && _looksLikeHeader(cells)) continue;
      final entry = ScorecardEntry(
        label: cells.first.trim(),
        value: parseScorecardNumber(cells.length > 1 ? cells[1] : ''),
        previous: parseScorecardNumber(cells.length > 2 ? cells[2] : ''),
        unit: cells.length > 3 ? cells[3].trim() : '',
        polarity: scorecardPolarityFromToken(cells.length > 4 ? cells[4] : ''),
      );
      if (entry.isBlank) continue;
      entries.add(entry);
    }
    return ScorecardSpec(
      title: title,
      entries: entries.take(scorecardMaxEntries).toList(),
    );
  }

  static bool _looksLikeHeader(List<String> cells) =>
      cells.first.trim().toLowerCase() == header.first.toLowerCase();

  /// Build the table rows (header + one row per figure) for [Slide.tableRows].
  /// An absent figure is written as an empty cell rather than a zero, keeping
  /// "not measured" distinct from "was nought". Blank rows are skipped here as
  /// well as on read, so writing and reading agree.
  List<List<String>> toTableRows() => [
    header,
    for (final e in entries.where((e) => !e.isBlank).take(scorecardMaxEntries))
      [
        e.label,
        e.value == null ? '' : formatScorecardNumber(e.value!),
        e.previous == null ? '' : formatScorecardNumber(e.previous!),
        e.unit,
        e.polarity.token,
      ],
  ];

  ScorecardSpec copyWith({String? title, List<ScorecardEntry>? entries}) =>
      ScorecardSpec(
        title: title ?? this.title,
        entries: (entries ?? this.entries).take(scorecardMaxEntries).toList(),
      );
}

/// Read a figure from a table cell, or null when there is none to read.
///
/// Accepts a comma as the decimal mark when it is unambiguous (exactly one
/// comma and no dot), because a table edited by hand in a Dutch locale is a
/// normal way for this data to arrive. Anything genuinely ambiguous — thousands
/// separators, several commas — is refused rather than guessed at.
double? parseScorecardNumber(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final direct = double.tryParse(text);
  if (direct != null) return direct;
  if (!text.contains('.') && ','.allMatches(text).length == 1) {
    return double.tryParse(text.replaceFirst(',', '.'));
  }
  return null;
}

/// Write a figure back to a table cell: whole numbers without a decimal tail,
/// everything else as-is. Always a dot, so the file stays machine-readable
/// regardless of the author's locale.
String formatScorecardNumber(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? value.toInt().toString()
    : value.toString();

/// A change written for display: always signed, so a rise still reads as a rise
/// when the slide is printed in greyscale and the colour is gone.
String formatScorecardDelta(double delta) {
  final magnitude = formatScorecardNumber(delta.abs());
  return delta < 0 ? '-$magnitude' : '+$magnitude';
}

/// Read a polarity token, falling back to [ScorecardPolarity.neutral].
ScorecardPolarity scorecardPolarityFromToken(String raw) {
  final token = raw.trim().toLowerCase();
  for (final polarity in ScorecardPolarity.values) {
    if (polarity.token == token) return polarity;
  }
  return ScorecardPolarity.neutral;
}

/// The Dutch source label for a [polarity] as shown in the editor. Localise the
/// result with `l10n.d(...)`, the same convention as
/// [findingsSeverityDutchLabel].
String scorecardPolarityDutchLabel(ScorecardPolarity polarity) =>
    switch (polarity) {
      ScorecardPolarity.lowerBetter => 'Lager is beter',
      ScorecardPolarity.higherBetter => 'Hoger is beter',
      ScorecardPolarity.neutral => 'Neutraal',
    };
