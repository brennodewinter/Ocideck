/// The most actions an `actions` slide carries. A management slide asks for a
/// handful of decisions, not a backlog; past eight the room stops deciding and
/// starts skimming. Applied on both read and write, like [scorecardMaxEntries].
const int actionsMaxItems = 8;

/// What is being asked of the room.
///
/// The distinction is the whole point of the slide: a reader scans for what they
/// have to *do*, and a decision buried among status updates is a decision that
/// does not get taken. [info] reports, [decision] asks, [escalation] warns that
/// asking has not worked so far.
enum ActionKind {
  info('info'),
  decision('decision'),
  escalation('escalation');

  const ActionKind(this.token);

  /// The stable English token written to disk, so the round-trip is
  /// language-independent.
  final String token;
}

/// Where the action stands. Deliberately three plain states — "overdue" is
/// **not** among them, because it is not something an author should be able to
/// assert or forget: see [ActionItem.isOverdue].
enum ActionStatus {
  open('open'),
  inProgress('in-progress'),
  done('done');

  const ActionStatus(this.token);

  final String token;
}

/// One line on an actions slide: what, who, by when, and what is being asked.
class ActionItem {
  const ActionItem({
    this.action = '',
    this.owner = '',
    this.due,
    this.since,
    this.status = ActionStatus.open,
    this.kind = ActionKind.info,
  });

  final String action;

  /// Who carries it. Kept as free text rather than a picked identity: the owner
  /// of an action is often a team, a supplier or a role, and forcing it into a
  /// person would push the honest answers out of the field.
  final String owner;

  /// The agreed date, or null when there is none yet. An action without a date
  /// is a real state worth showing — it is usually the thing to settle in the
  /// meeting.
  final DateTime? due;

  /// When this action was first put on the list. What makes a recurring report
  /// bite: an item that has been carried for three reports is a different
  /// conversation from one raised this week.
  final DateTime? since;

  final ActionStatus status;
  final ActionKind kind;

  /// Nothing filled in yet — the shape the editor hands out for a new line.
  /// Dropped on both read and write, so an untouched row never reaches the
  /// slide and the round-trip stays a fixed point.
  bool get isBlank =>
      action.trim().isEmpty &&
      owner.trim().isEmpty &&
      due == null &&
      since == null;

  /// Whether the deadline has passed without the action being done, judged
  /// against [asOf] (the caller's clock — the preview passes the current date).
  ///
  /// Derived rather than stored, and that is the point. A deck shown two months
  /// after it was written should say so instead of still claiming everything is
  /// on schedule; an "overdue" flag typed in by the author would freeze at
  /// whatever was true the day they wrote it. The same reasoning as deriving a
  /// finding's severity from its vector rather than letting it be typed.
  ///
  /// A completed action is never overdue, however late it was: the slide
  /// reports the current state, not the history of how it got there.
  bool isOverdue(DateTime asOf) {
    final deadline = due;
    if (deadline == null || status == ActionStatus.done) return false;
    return _dateOnly(deadline).isBefore(_dateOnly(asOf));
  }

  ActionItem copyWith({
    String? action,
    String? owner,
    DateTime? due,
    bool clearDue = false,
    DateTime? since,
    bool clearSince = false,
    ActionStatus? status,
    ActionKind? kind,
  }) => ActionItem(
    action: action ?? this.action,
    owner: owner ?? this.owner,
    due: clearDue ? null : (due ?? this.due),
    since: clearSince ? null : (since ?? this.since),
    status: status ?? this.status,
    kind: kind ?? this.kind,
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// An `actions` slide's structured content: what has to happen, who does it, by
/// when, and — the column that makes a recurring report bite — what is actually
/// being asked of the room.
///
/// A typed *view* over the slide's title + a small Markdown table, exactly like
/// [ScorecardSpec] / `checklist` / `scopeMatrix`: it round-trips losslessly as
/// plain Markdown, stays readable and editable outside the app, and renders
/// identically in a headless export isolate.
class ActionsSpec {
  const ActionsSpec({this.title = '', this.items = const []});

  final String title;
  final List<ActionItem> items;

  /// Fixed English column headers written as the table's first row.
  static const header = ['Action', 'Owner', 'Due', 'Status', 'Kind', 'Since'];

  bool get isEmpty => items.isEmpty;

  /// How many items are asks rather than reports — the figure that says whether
  /// this slide needs the room's attention or merely its eyes.
  int get askCount => items.where((i) => i.kind != ActionKind.info).length;

  /// How many items are past their deadline as of [asOf].
  int overdueCount(DateTime asOf) =>
      items.where((i) => i.isOverdue(asOf)).length;

  /// Parse the typed items from [title] + [tableRows]. The first row is the
  /// header (skipped when it looks like one).
  ///
  /// Tolerant like the other table-backed specs: an entirely blank row is
  /// dropped, an unreadable date leaves that field empty rather than costing the
  /// row, and an unrecognised status or kind falls back to the quietest value
  /// (`open` / `info`) — understating an ask is recoverable, inventing one is
  /// not.
  factory ActionsSpec.fromSlide(String title, List<List<String>> tableRows) {
    final items = <ActionItem>[];
    for (var i = 0; i < tableRows.length; i++) {
      final cells = tableRows[i];
      if (cells.isEmpty) continue;
      if (i == 0 && _looksLikeHeader(cells)) continue;
      String cell(int n) => cells.length > n ? cells[n].trim() : '';
      final item = ActionItem(
        action: cell(0),
        owner: cell(1),
        due: parseActionDate(cell(2)),
        status: actionStatusFromToken(cell(3)),
        kind: actionKindFromToken(cell(4)),
        since: parseActionDate(cell(5)),
      );
      if (item.isBlank) continue;
      items.add(item);
    }
    return ActionsSpec(
      title: title,
      items: items.take(actionsMaxItems).toList(),
    );
  }

  static bool _looksLikeHeader(List<String> cells) =>
      cells.first.trim().toLowerCase() == header.first.toLowerCase();

  /// Build the table rows (header + one row per item) for [Slide.tableRows].
  /// An absent date is written as an empty cell; blank rows are skipped here as
  /// well as on read, so writing and reading agree.
  List<List<String>> toTableRows() => [
    header,
    for (final item in items.where((i) => !i.isBlank).take(actionsMaxItems))
      [
        item.action,
        item.owner,
        formatActionDate(item.due),
        item.status.token,
        item.kind.token,
        formatActionDate(item.since),
      ],
  ];

  ActionsSpec copyWith({String? title, List<ActionItem>? items}) => ActionsSpec(
    title: title ?? this.title,
    items: (items ?? this.items).take(actionsMaxItems).toList(),
  );
}

/// Read an ISO `yyyy-mm-dd` date from a table cell, or null when there is none
/// to read.
///
/// Only the ISO form is accepted. A date is the one field here where guessing
/// is genuinely dangerous — `05-08-2026` is two different days depending on who
/// wrote it, and an action's deadline is not a good place to be wrong by three
/// months. The editor writes ISO, so an unreadable cell means it was hand-typed
/// in some other form, and refusing it surfaces that rather than burying it.
DateTime? parseActionDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final parsed = DateTime(year, month, day);
  // Reject a date the calendar rolled over (31 February became 3 March).
  if (parsed.month != month || parsed.day != day) return null;
  return parsed;
}

/// Write a date back as ISO `yyyy-mm-dd`, or an empty cell when there is none.
String formatActionDate(DateTime? date) {
  if (date == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Read a status token, falling back to [ActionStatus.open].
ActionStatus actionStatusFromToken(String raw) {
  final token = raw.trim().toLowerCase();
  for (final status in ActionStatus.values) {
    if (status.token == token) return status;
  }
  return ActionStatus.open;
}

/// Read a kind token, falling back to [ActionKind.info].
ActionKind actionKindFromToken(String raw) {
  final token = raw.trim().toLowerCase();
  for (final kind in ActionKind.values) {
    if (kind.token == token) return kind;
  }
  return ActionKind.info;
}

/// The Dutch source label for a [kind]. Localise with `l10n.d(...)`, the same
/// convention as [scorecardPolarityDutchLabel].
String actionKindDutchLabel(ActionKind kind) => switch (kind) {
  ActionKind.info => 'Ter informatie',
  ActionKind.decision => 'Besluit gevraagd',
  ActionKind.escalation => 'Escalatie',
};

/// The Dutch source label for a [status].
String actionStatusDutchLabel(ActionStatus status) => switch (status) {
  ActionStatus.open => 'Open',
  ActionStatus.inProgress => 'Loopt',
  ActionStatus.done => 'Afgerond',
};
