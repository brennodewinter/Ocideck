/// The most groups an asset-overview slide shows. A management overview names
/// the handful of categories the estate actually breaks into; a scan that finds
/// four hundred objects still has six or eight kinds of them. Applied on both
/// read and write, like [actionsMaxItems].
const int assetOverviewMaxGroups = 8;

/// One row of an attack-surface overview: a *kind* of exposed object and the
/// four counts that say how it stands.
///
/// Note that "asset" here means an **externally exposed object** — a domain, a
/// mail server, an API, a certificate — and not a media file. Elsewhere in this
/// codebase (`asset_origin.dart`, `AssetStaging`) "asset" means an image or
/// video travelling with the deck. The two never meet, but the word is the same,
/// so this is the place to say which one is meant.
class AssetGroup {
  const AssetGroup({
    this.name = '',
    this.total = 0,
    this.atRisk = 0,
    this.newlyFound = 0,
    this.unowned = 0,
  });

  /// What this kind of object is called, in the reader's words — "Webapplicaties",
  /// not "http/https endpoints".
  final String name;

  /// How many objects of this kind the scan found.
  final int total;

  /// How many of them carry at least one open finding. The subset that costs
  /// somebody an afternoon.
  final int atRisk;

  /// How many were seen for the first time in this scan. The number behind the
  /// most uncomfortable sentence in an attack-surface report: we did not know we
  /// had these.
  final int newlyFound;

  /// How many have nobody's name against them. Not a technical problem but a
  /// governance one — an object without an owner has nobody to fix it, and it is
  /// usually the figure that moves a management meeting.
  final int unowned;

  /// Nothing filled in — the shape the editor hands out for a new row. Dropped
  /// on both read and write, so an untouched row never reaches the slide.
  bool get isBlank =>
      name.trim().isEmpty &&
      total == 0 &&
      atRisk == 0 &&
      newlyFound == 0 &&
      unowned == 0;

  /// [atRisk] as a fraction of [total], clamped to 0..1 for drawing.
  ///
  /// Only the *bar* is clamped, never the printed figure: if a generator claims
  /// 200 at risk out of 182, the slide says so. A silently corrected number
  /// would hide the bug in whatever produced it, which is exactly the kind of
  /// error a report should surface rather than smooth over.
  double get atRiskFraction {
    if (total <= 0) return 0;
    return (atRisk / total).clamp(0.0, 1.0);
  }

  /// Whether the counts are internally possible. A subset cannot outnumber the
  /// set it is drawn from; when this is false the slide still renders what it
  /// was given.
  bool get isConsistent =>
      atRisk <= total && newlyFound <= total && unowned <= total;

  AssetGroup copyWith({
    String? name,
    int? total,
    int? atRisk,
    int? newlyFound,
    int? unowned,
  }) => AssetGroup(
    name: name ?? this.name,
    total: total ?? this.total,
    atRisk: atRisk ?? this.atRisk,
    newlyFound: newlyFound ?? this.newlyFound,
    unowned: unowned ?? this.unowned,
  );
}

/// An `assets` slide's structured content: the attack surface broken into the
/// kinds of object it consists of, with how many of each are at risk, newly
/// found, and unowned.
///
/// Deliberately a *grouped* view rather than one row per object. A scan returns
/// hundreds of objects and a management slide can carry eight lines; listing
/// individual hosts turns the slide into an appendix nobody reads. The per-object
/// detail belongs in the tool that produced it — this slide answers how big the
/// surface is, how much of it needs work, and what nobody owns.
///
/// A typed *view* over the slide's title + a small Markdown table, exactly like
/// [ActionsSpec] / [ScorecardSpec]: it round-trips losslessly as plain Markdown
/// and renders identically in a headless export isolate.
class AssetOverviewSpec {
  const AssetOverviewSpec({this.title = '', this.groups = const []});

  final String title;
  final List<AssetGroup> groups;

  /// Fixed English column headers written as the table's first row.
  static const header = ['Group', 'Total', 'AtRisk', 'New', 'Unowned'];

  bool get isEmpty => groups.isEmpty;

  /// Deck-wide totals, derived and never stored — the same rule as the findings
  /// summary's total. A stored sum is a second number that can disagree with the
  /// rows above it, and the rows are the ones the reader can check.
  int get totalAssets => groups.fold(0, (sum, g) => sum + g.total);
  int get totalAtRisk => groups.fold(0, (sum, g) => sum + g.atRisk);
  int get totalNew => groups.fold(0, (sum, g) => sum + g.newlyFound);
  int get totalUnowned => groups.fold(0, (sum, g) => sum + g.unowned);

  /// The largest [AssetGroup.total] on the slide, so every bar can be drawn to
  /// one shared scale. Without this the groups would each fill their own row and
  /// a category of three would look the size of a category of three hundred.
  int get largestGroup =>
      groups.fold(0, (max, g) => g.total > max ? g.total : max);

  /// Parse the typed groups from [title] + [tableRows]. The first row is the
  /// header (skipped when it looks like one).
  ///
  /// Tolerant like the other table-backed specs: an entirely blank row is
  /// dropped, and an unreadable or negative count reads as zero rather than
  /// costing the row — a category whose name arrived but whose figures did not
  /// is still worth showing as an empty line.
  factory AssetOverviewSpec.fromSlide(
    String title,
    List<List<String>> tableRows,
  ) {
    final groups = <AssetGroup>[];
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      if (cells.isEmpty) continue;
      if (i == 0 && _looksLikeHeader(cells)) continue;
      int count(int n) =>
          parseAssetCount(cells.length > n ? cells[n] : '') ?? 0;
      final group = AssetGroup(
        name: cells.first.trim(),
        total: count(1),
        atRisk: count(2),
        newlyFound: count(3),
        unowned: count(4),
      );
      if (group.isBlank) continue;
      groups.add(group);
    }
    return AssetOverviewSpec(
      title: title,
      groups: groups.take(assetOverviewMaxGroups).toList(),
    );
  }

  static bool _looksLikeHeader(List<String> cells) =>
      cells.first.trim().toLowerCase() == header.first.toLowerCase();

  /// Build the table rows (header + one row per group) for [Slide.tableRows].
  /// Blank rows are skipped here as well as on read, so writing and reading
  /// agree.
  List<List<String>> toTableRows() => [
    header,
    for (final g
        in groups.where((g) => !g.isBlank).take(assetOverviewMaxGroups))
      [g.name, '${g.total}', '${g.atRisk}', '${g.newlyFound}', '${g.unowned}'],
  ];

  AssetOverviewSpec copyWith({String? title, List<AssetGroup>? groups}) =>
      AssetOverviewSpec(
        title: title ?? this.title,
        groups: (groups ?? this.groups).take(assetOverviewMaxGroups).toList(),
      );
}

/// Read a count from a table cell, or null when there is none to read. A
/// negative count is refused: there is no such thing as minus three servers, and
/// reading it as zero beats letting it subtract from a total.
int? parseAssetCount(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final value = int.tryParse(text);
  if (value == null || value < 0) return null;
  return value;
}
