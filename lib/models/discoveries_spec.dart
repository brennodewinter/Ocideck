/// The most discoveries one slide names. A management slide that lists twenty
/// newly found objects has stopped being a slide and become an appendix; the
/// generator picks the ones worth naming — longest unnoticed, or unowned — and
/// the rest stay in the tool that found them. Applied on both read and write.
const int discoveriesMaxEntries = 6;

/// One newly discovered exposed object: something the scan found that was not
/// in any inventory beforehand.
///
/// "Discovery" here is deliberately narrower than "new asset". The asset
/// overview already counts what is new per category; this is the named list of
/// the ones nobody knew about — shadow IT, a forgotten acceptance environment, a
/// certificate issued by a team that has since been reorganised away.
class Discovery {
  const Discovery({
    this.name = '',
    this.kind = '',
    this.daysUnnoticed,
    this.owner = '',
  });

  /// What was found, named the way the reader will recognise it — a hostname, a
  /// service, an application. This is the one field that is worth a full line.
  final String name;

  /// What kind of object it is: "Webapplicatie", "Mailserver", "Certificaat".
  /// Short by design — it tells a domain from a mail relay and nothing more.
  final String kind;

  /// How long the object was reachable before anyone noticed, in days.
  ///
  /// Null when it is not known, and that is the common case for a first scan:
  /// an object discovered by a tool that has never run before has no history to
  /// measure against. A missing figure draws no bar rather than a zero-length
  /// one — claiming "found immediately" is a much stronger statement than
  /// admitting the question cannot be answered yet.
  ///
  /// This is the number the slide exists for. "We found twelve new things" is a
  /// scan result; "one of them had been open for fourteen months" is the finding
  /// that changes a management meeting.
  final int? daysUnnoticed;

  /// Who owns it now that it is known. Empty means nobody does — the governance
  /// problem, and the reason a discovery can stay a discovery next quarter.
  final String owner;

  /// Nothing filled in — the shape the editor hands out for a new row. Dropped
  /// on both read and write, so an untouched row never reaches the slide.
  bool get isBlank =>
      name.trim().isEmpty &&
      kind.trim().isEmpty &&
      daysUnnoticed == null &&
      owner.trim().isEmpty;

  /// Whether anybody's name is against this object.
  bool get hasOwner => owner.trim().isNotEmpty;

  Discovery copyWith({
    String? name,
    String? kind,
    int? daysUnnoticed,
    bool clearDaysUnnoticed = false,
    String? owner,
  }) => Discovery(
    name: name ?? this.name,
    kind: kind ?? this.kind,
    daysUnnoticed: clearDaysUnnoticed
        ? null
        : (daysUnnoticed ?? this.daysUnnoticed),
    owner: owner ?? this.owner,
  );
}

/// A `discoveries` slide's structured content: the objects this scan turned up
/// that were not known to exist, each with how long it had been exposed and who
/// owns it now.
///
/// A typed *view* over the slide's title + a small Markdown table, exactly like
/// [AssetOverviewSpec] and [ScorecardSpec]: it round-trips losslessly as plain
/// Markdown and renders identically in a headless export isolate.
///
/// Why this is not simply a table slide: every figure on it is drawn to a scale
/// shared with the other rows, and the slide computes a verdict the author never
/// types — the longest exposure, and how many of the finds still have no owner.
/// A table can hold the same four columns but cannot say which row is the
/// problem. That is the whole difference between listing discoveries and
/// reporting them.
class DiscoveriesSpec {
  const DiscoveriesSpec({this.title = '', this.discoveries = const []});

  final String title;
  final List<Discovery> discoveries;

  /// Fixed English column headers written as the table's first row.
  static const header = ['Discovery', 'Kind', 'DaysUnnoticed', 'Owner'];

  bool get isEmpty => discoveries.isEmpty;

  /// How many objects the slide names.
  int get count => discoveries.length;

  /// How many of them still have nobody's name against them.
  int get unownedCount => discoveries.where((d) => !d.hasOwner).length;

  /// The longest exposure on the slide, or null when no row carries a figure.
  ///
  /// Serves two purposes: it is the headline the slide leads with, and it is the
  /// scale every bar is drawn to. Scaling each bar to its own row would draw a
  /// three-day exposure the same width as a four-hundred-day one, which is the
  /// picture saying the opposite of the numbers.
  int? get longestUnnoticed {
    final known = discoveries
        .map((d) => d.daysUnnoticed)
        .whereType<int>()
        .toList();
    if (known.isEmpty) return null;
    return known.reduce((a, b) => a > b ? a : b);
  }

  /// [Discovery.daysUnnoticed] as a fraction of [longestUnnoticed], for drawing.
  /// Zero when the figure is missing, so an unknown exposure draws no bar.
  double barFraction(Discovery discovery) {
    final longest = longestUnnoticed;
    final days = discovery.daysUnnoticed;
    if (longest == null || longest <= 0 || days == null) return 0;
    return (days / longest).clamp(0.0, 1.0);
  }

  /// Parse the typed discoveries from [title] + [tableRows]. The first row is
  /// the header (skipped when it looks like one).
  ///
  /// Tolerant like the other table-backed specs: an entirely blank row is
  /// dropped, and an unreadable exposure reads as *unknown* rather than as zero
  /// — a row whose name arrived but whose figure did not is still worth naming.
  factory DiscoveriesSpec.fromSlide(
    String title,
    List<List<String>> tableRows,
  ) {
    final discoveries = <Discovery>[];
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      if (cells.isEmpty) continue;
      if (i == 0 && _looksLikeHeader(cells)) continue;
      String cell(int n) => cells.length > n ? cells[n].trim() : '';
      final discovery = Discovery(
        name: cells.first.trim(),
        kind: cell(1),
        daysUnnoticed: parseDaysUnnoticed(cell(2)),
        owner: cell(3),
      );
      if (discovery.isBlank) continue;
      discoveries.add(discovery);
    }
    return DiscoveriesSpec(
      title: title,
      discoveries: discoveries.take(discoveriesMaxEntries).toList(),
    );
  }

  static bool _looksLikeHeader(List<String> cells) =>
      cells.first.trim().toLowerCase() == header.first.toLowerCase();

  /// Build the table rows (header + one row per discovery) for
  /// [Slide.tableRows]. Blank rows are skipped here as well as on read, so
  /// writing and reading agree.
  List<List<String>> toTableRows() => [
    header,
    for (final d
        in discoveries.where((d) => !d.isBlank).take(discoveriesMaxEntries))
      [
        d.name,
        d.kind,
        d.daysUnnoticed == null ? '' : '${d.daysUnnoticed}',
        d.owner,
      ],
  ];

  DiscoveriesSpec copyWith({String? title, List<Discovery>? discoveries}) =>
      DiscoveriesSpec(
        title: title ?? this.title,
        discoveries: (discoveries ?? this.discoveries)
            .take(discoveriesMaxEntries)
            .toList(),
      );
}

/// Read an exposure in days from a table cell, or null when there is none to
/// read. A negative figure is refused: an object cannot have been exposed for
/// minus three days, and reading it as unknown beats drawing a bar backwards.
int? parseDaysUnnoticed(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final value = int.tryParse(text);
  if (value == null || value < 0) return null;
  return value;
}

/// Restate an exposure in the unit a reader actually hears.
///
/// Days are what a scanner records and months are what a management audience
/// understands: 420 means nothing at a glance, "14 maanden" lands immediately.
/// Below two months the day count is the more precise statement and is kept.
///
/// Returns the figure and which unit it is in, leaving the *word* to the caller
/// — the number belongs to the model, the grammar to the widget that has an
/// [AppLocalizations] to hand.
({int value, bool inMonths}) scaleDaysUnnoticed(int days) => days < 60
    ? (value: days, inMonths: false)
    : (value: (days / 30.44).round(), inMonths: true);
