/// How a data-driven slide should visually limit its items without discarding
/// the underlying data. Stored per slide and round-tripped as a set of
/// `ocideck_view_*` HTML comments in the `.md`.
enum DisplayWindowMode { first, last, top, bottom }

/// What happens to items that fall outside the [DisplayWindowSpec.limit].
enum DisplayWindowRemainder { hide, other }

/// Non-destructive view limit for bullets, tables and charts.
///
/// The original data stays intact in [Slide.bullets], [Slide.tableRows] and
/// [ChartSpec]; the limit is applied at render/export time.
class DisplayWindowSpec {
  /// Maximum number of visible items. `null` or `0` means “show everything”.
  final int? limit;

  /// Which items are shown when [limit] is set.
  final DisplayWindowMode mode;

  /// For tables: column index or stable column identifier to sort on.
  /// For charts: name of the series to rank by.
  /// For bullets: empty / not applicable.
  final String key;

  /// What to do with the items that are not shown.
  final DisplayWindowRemainder remainder;

  /// Whether to render a “N of total” indicator.
  final bool showCount;

  const DisplayWindowSpec({
    this.limit,
    this.mode = DisplayWindowMode.first,
    this.key = '',
    this.remainder = DisplayWindowRemainder.hide,
    this.showCount = true,
  });

  bool get isActive => limit != null && limit! > 0;

  DisplayWindowSpec copyWith({
    int? limit,
    bool clearLimit = false,
    DisplayWindowMode? mode,
    String? key,
    DisplayWindowRemainder? remainder,
    bool? showCount,
  }) => DisplayWindowSpec(
    limit: clearLimit ? null : (limit ?? this.limit),
    mode: mode ?? this.mode,
    key: key ?? this.key,
    remainder: remainder ?? this.remainder,
    showCount: showCount ?? this.showCount,
  );

  static DisplayWindowMode _modeFrom(String? raw) {
    final name = raw?.trim() ?? '';
    return DisplayWindowMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => DisplayWindowMode.first,
    );
  }

  static DisplayWindowRemainder _remainderFrom(String? raw) {
    final name = raw?.trim() ?? '';
    return DisplayWindowRemainder.values.firstWhere(
      (r) => r.name == name,
      orElse: () => DisplayWindowRemainder.hide,
    );
  }

  /// Builds a spec from the `ocideck_view_*` comment values.
  factory DisplayWindowSpec.fromComments(Map<String, String> comments) {
    final limit = int.tryParse(comments['ocideck_view_limit']?.trim() ?? '');
    return DisplayWindowSpec(
      limit: (limit != null && limit > 0) ? limit : null,
      mode: _modeFrom(comments['ocideck_view_mode']),
      key: comments['ocideck_view_key']?.trim() ?? '',
      remainder: _remainderFrom(comments['ocideck_view_remainder']),
      showCount:
          (comments['ocideck_view_show_count']?.trim() ?? 'true') != 'false',
    );
  }

  /// Emits the comment values to be written by the serializer.
  Map<String, String> toComments() {
    final out = <String, String>{};
    if (limit != null && limit! > 0) {
      out['ocideck_view_limit'] = '$limit';
      if (mode != DisplayWindowMode.first) {
        out['ocideck_view_mode'] = mode.name;
      }
      if (key.isNotEmpty) out['ocideck_view_key'] = key;
      if (remainder != DisplayWindowRemainder.hide) {
        out['ocideck_view_remainder'] = remainder.name;
      }
      if (!showCount) out['ocideck_view_show_count'] = 'false';
    }
    return out;
  }

  // Het "N van totaal"-bijschrift woonde hier als hardgecodeerd Nederlands.
  // Het is zichtbare tekst en hoort dus door l10n — maar een model mag geen
  // l10n dragen, dus de opbouw verhuisde naar DisplayWindowService._caption
  // (bewaker-bevinding #672). Dit model blijft zuiver data.
}
