import 'dart:math' as math;
import 'dart:ui' show Locale;

import '../l10n/app_localizations.dart';
import '../models/chart.dart';
import '../models/display_window_spec.dart';
import '../models/slide.dart';

/// Result of applying a [DisplayWindowSpec] to a collection of data.
class DisplayWindowResult<T> {
  final T items;
  final int total;
  final int shown;
  final String? countCaption;

  const DisplayWindowResult({
    required this.items,
    required this.total,
    required this.shown,
    this.countCaption,
  });

  bool get wasLimited => shown < total;
}

/// Applies non-destructive view limits to bullets, tables and charts.
///
/// The original data is never modified; callers receive a new projection.
class DisplayWindowService {
  const DisplayWindowService();

  /// Limit a list of bullet strings.
  DisplayWindowResult<List<String>> applyToBullets(
    List<String> bullets,
    DisplayWindowSpec? spec,
  ) {
    final mode = _bulletMode(spec);
    final limit = _effectiveLimit(spec, bullets.length);
    final selected = _selectInOrder(bullets, mode, limit);
    return DisplayWindowResult(
      items: selected,
      total: bullets.length,
      shown: selected.length,
      countCaption: _caption(spec, total: bullets.length, unit: 'punten'),
    );
  }

  /// Limit table rows while keeping the header row.
  ///
  /// [rows] uses the OciDeck convention: the first row is the header. [spec]
  /// applies to the data rows; the header is always kept.
  DisplayWindowResult<List<List<String>>> applyToTable(
    List<List<String>> rows,
    DisplayWindowSpec? spec, {
    String unit = 'regels',
  }) {
    if (rows.isEmpty || !_isActive(spec)) {
      return DisplayWindowResult(
        items: rows,
        total: rows.length <= 1 ? 0 : rows.length - 1,
        shown: rows.length <= 1 ? 0 : rows.length - 1,
      );
    }
    final header = rows.first;
    final data = rows.sublist(1);
    final keyIndex = _resolveTableKeyIndex(header, spec?.key ?? '');
    final mode = spec?.mode ?? DisplayWindowMode.first;
    final limit = _effectiveLimit(spec, data.length);
    final sorted = _sortTableData(data, mode, keyIndex);
    final selected = _take(sorted, mode, limit);
    final other = _computeTableOther(
      data: data,
      selected: selected,
      remainder: spec?.remainder ?? DisplayWindowRemainder.hide,
      header: header,
    );
    final out = [header, ...selected];
    if (other != null) out.add(other);
    return DisplayWindowResult(
      items: out,
      total: data.length,
      shown: selected.length,
      countCaption: _caption(spec, total: data.length, unit: unit),
    );
  }

  /// Limit chart labels and series.
  ///
  /// Time-series charts (line, area, scatter) never silently re-sort on value;
  /// top/bottom requested on them falls back to [DisplayWindowMode.last] so the
  /// most recent periods remain visible.
  DisplayWindowResult<ChartSpec> applyToChart(
    ChartSpec chart,
    DisplayWindowSpec? spec,
  ) {
    if (chart.x.isEmpty || chart.series.isEmpty || !_isActive(spec)) {
      return DisplayWindowResult(
        items: chart,
        total: chart.x.length,
        shown: chart.x.length,
      );
    }
    final isTimeSeries =
        chart.type == ChartType.line ||
        chart.type == ChartType.area ||
        chart.type == ChartType.scatter;
    final mode = _chartMode(spec, isTimeSeries);
    final limit = _effectiveLimit(spec, chart.x.length);
    final order = _chartIndexOrder(chart, mode, spec?.key ?? '');
    final selectedIndexes = _takeIndexes(order, mode, limit);
    final otherData = _computeChartOther(
      chart: chart,
      selected: selectedIndexes,
      remainder: spec?.remainder ?? DisplayWindowRemainder.hide,
    );
    final newX = [
      for (final i in selectedIndexes) chart.x[i],
      if (otherData != null) _l10n.d('Overig'),
    ];
    final newSeries = [
      for (final s in chart.series)
        ChartSeries(
          name: s.name,
          color: s.color,
          data: [
            for (final i in selectedIndexes) s.data[i],
            if (otherData != null) otherData[s.name] ?? 0.0,
          ],
        ),
    ];
    final newColors = [
      for (final i in selectedIndexes)
        i < chart.rowColors.length ? chart.rowColors[i] : null,
      if (otherData != null) null,
    ];
    return DisplayWindowResult(
      items: chart.copyWith(x: newX, rowColors: newColors, series: newSeries),
      total: chart.x.length,
      shown: selectedIndexes.length,
      countCaption: _caption(spec, total: chart.x.length, unit: 'categorieën'),
    );
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  bool _isActive(DisplayWindowSpec? spec) =>
      spec != null && spec.limit != null && spec.limit! > 0;

  int _effectiveLimit(DisplayWindowSpec? spec, int total) {
    if (spec?.limit == null) return total;
    return math.min(spec!.limit!, total).clamp(0, total);
  }

  DisplayWindowMode _bulletMode(DisplayWindowSpec? spec) {
    final mode = spec?.mode ?? DisplayWindowMode.first;
    // Bullets only support first/last; top/bottom fall back to first.
    if (mode == DisplayWindowMode.top || mode == DisplayWindowMode.bottom) {
      return DisplayWindowMode.first;
    }
    return mode;
  }

  DisplayWindowMode _chartMode(DisplayWindowSpec? spec, bool isTimeSeries) {
    final mode = spec?.mode ?? DisplayWindowMode.first;
    if (isTimeSeries &&
        (mode == DisplayWindowMode.top || mode == DisplayWindowMode.bottom)) {
      return DisplayWindowMode.last;
    }
    return mode;
  }

  List<T> _selectInOrder<T>(List<T> items, DisplayWindowMode mode, int limit) {
    if (limit >= items.length) return List<T>.from(items);
    switch (mode) {
      case DisplayWindowMode.first:
        return items.sublist(0, limit);
      case DisplayWindowMode.last:
        return items.sublist(items.length - limit);
      case DisplayWindowMode.top:
      case DisplayWindowMode.bottom:
        return items.sublist(0, limit);
    }
  }

  List<T> _take<T>(List<T> sorted, DisplayWindowMode mode, int limit) {
    final n = math.min(limit, sorted.length);
    if (mode == DisplayWindowMode.last) {
      return sorted.sublist(sorted.length - n);
    }
    return sorted.sublist(0, n);
  }

  List<int> _takeIndexes(List<int> order, DisplayWindowMode mode, int limit) {
    final n = math.min(limit, order.length);
    if (mode == DisplayWindowMode.last) {
      return order.sublist(order.length - n);
    }
    return order.sublist(0, n);
  }

  /// De vertaling van dit moment. De constructor-locale is een formaliteit —
  /// `d()` kijkt naar de actieve taal — en dit is dezelfde contextloze route
  /// die `export_service` al neemt: de projectie draait óók in de export,
  /// waar geen BuildContext bestaat.
  AppLocalizations get _l10n => const AppLocalizations(Locale('nl'));

  /// Het "N van totaal"-bijschrift, in de taal van de gebruiker.
  ///
  /// Zichtbare tekst, dus door l10n — hardgecodeerd Nederlands zou in
  /// andermans inhoud belanden, tot in de PDF en het geëxporteerde .md
  /// (bewaker-bevinding #672). [unit] is een Nederlandse bronsleutel
  /// ('punten', 'regels', 'categorieën'); de moduswoorden hergebruiken de
  /// dropdown-labels zodat bijschrift en editor hetzelfde woord spreken.
  String? _caption(
    DisplayWindowSpec? spec, {
    required int total,
    required String unit,
  }) {
    if (!_isActive(spec) || !spec!.showCount) return null;
    final n = spec.limit!;
    final shown = n < total ? n : total;
    final mode = switch (spec.mode) {
      DisplayWindowMode.first => _l10n.d('Eerste'),
      DisplayWindowMode.last => _l10n.d('Laatste'),
      DisplayWindowMode.top => _l10n.d('Hoogste'),
      DisplayWindowMode.bottom => _l10n.d('Laagste'),
    };
    return '$mode $shown ${_l10n.d('van')} $total ${_l10n.d(unit)}';
  }

  // ── Table helpers ──────────────────────────────────────────────────────────

  int _resolveTableKeyIndex(List<String> header, String key) {
    if (key.isEmpty) return 0;
    final asInt = int.tryParse(key);
    if (asInt != null && asInt >= 0 && asInt < header.length) return asInt;
    for (var i = 0; i < header.length; i++) {
      if (header[i].trim() == key) return i;
    }
    return 0;
  }

  List<List<String>> _sortTableData(
    List<List<String>> data,
    DisplayWindowMode mode,
    int keyIndex,
  ) {
    if (mode != DisplayWindowMode.top && mode != DisplayWindowMode.bottom) {
      return List<List<String>>.from(data);
    }
    // Op index gesorteerd zodat gelijke waarden hun bronvolgorde houden —
    // Darts sort is niet stabiel, en een deck mag bij heropenen niet opeens
    // een andere top-N tonen (acceptatiecriterium #672).
    final indexes = List<int>.generate(data.length, (i) => i);
    indexes.sort((a, b) {
      final av = _parseNumber(data[a], keyIndex);
      final bv = _parseNumber(data[b], keyIndex);
      final cmp = av.compareTo(bv);
      if (cmp == 0) return a.compareTo(b);
      // For top, highest first; for bottom, lowest first.
      return mode == DisplayWindowMode.top ? -cmp : cmp;
    });
    return [for (final i in indexes) data[i]];
  }

  double _parseNumber(List<String> row, int index) {
    if (index >= row.length) return 0.0;
    final raw = row[index].replaceAll('%', '').replaceAll(',', '.').trim();
    return double.tryParse(raw) ?? 0.0;
  }

  /// Of kolom [index] in [data] overwegend getallen draagt — publiek omdat de
  /// editor er zijn niet-numeriek-waarschuwing op bouwt (#672); één oordeel,
  /// niet twee die uiteen kunnen lopen.
  bool isNumericColumn(List<List<String>> data, int index) {
    if (data.isEmpty) return false;
    var numeric = 0;
    for (final row in data) {
      if (index < row.length && double.tryParse(row[index].trim()) != null) {
        numeric++;
      }
    }
    return numeric >= data.length / 2;
  }

  List<String>? _computeTableOther({
    required List<List<String>> data,
    required List<List<String>> selected,
    required DisplayWindowRemainder remainder,
    required List<String> header,
  }) {
    if (remainder != DisplayWindowRemainder.other ||
        selected.length >= data.length) {
      return null;
    }
    final hidden = data.where((r) => !selected.contains(r)).toList();
    if (hidden.isEmpty) return null;
    final other = List<String>.filled(header.length, '');
    other[0] = _l10n.d('Overig');
    for (var c = 1; c < header.length; c++) {
      if (isNumericColumn(data, c)) {
        final sum = hidden
            .where((r) => c < r.length)
            .map((r) => _parseNumber(r, c))
            .fold<double>(0.0, (a, b) => a + b);
        other[c] = _formatNumber(sum);
      } else {
        other[c] = '';
      }
    }
    return other;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ── Chart helpers ──────────────────────────────────────────────────────────

  List<int> _chartIndexOrder(
    ChartSpec chart,
    DisplayWindowMode mode,
    String key,
  ) {
    final n = chart.x.length;
    if (mode == DisplayWindowMode.first || mode == DisplayWindowMode.last) {
      return List<int>.generate(n, (i) => i);
    }
    final seriesIndex = _resolveChartSeriesIndex(chart, key);
    final data = chart.series[seriesIndex].data;
    final indexes = List<int>.generate(n, (i) => i);
    indexes.sort((a, b) {
      final av = a < data.length ? data[a] : 0.0;
      final bv = b < data.length ? data[b] : 0.0;
      final cmp = av.compareTo(bv);
      // Bij gelijke waarden beslist de bronpositie — Darts sort is niet
      // stabiel, en een deck mag bij heropenen niet opeens een andere top-N
      // tonen (acceptatiecriterium #672).
      if (cmp == 0) return a.compareTo(b);
      return mode == DisplayWindowMode.top ? -cmp : cmp;
    });
    return indexes;
  }

  int _resolveChartSeriesIndex(ChartSpec chart, String key) {
    if (key.isNotEmpty) {
      for (var i = 0; i < chart.series.length; i++) {
        if (chart.series[i].name == key) return i;
      }
    }
    return chart.series.isNotEmpty ? 0 : 0;
  }

  Map<String, double>? _computeChartOther({
    required ChartSpec chart,
    required List<int> selected,
    required DisplayWindowRemainder remainder,
  }) {
    if (remainder != DisplayWindowRemainder.other ||
        selected.length >= chart.x.length) {
      return null;
    }
    final hidden = <int>[
      for (var i = 0; i < chart.x.length; i++)
        if (!selected.contains(i)) i,
    ];
    if (hidden.isEmpty) return null;
    final out = <String, double>{};
    for (final s in chart.series) {
      final sum = hidden
          .where((i) => i < s.data.length)
          .map((i) => s.data[i])
          .fold<double>(0.0, (a, b) => a + b);
      out[s.name] = sum;
    }
    return out;
  }
}

/// Applies the slide's [DisplayWindowSpec] without touching the stored slide.
///
/// Callers get a new [Slide] whose `bullets`, `tableRows` or chart
/// `customMarkdown` carry only the visible projection, plus an embedded caption
/// when `showCount` is true. The original [Slide] remains unchanged.
extension SlideDisplayWindowX on Slide {
  static const _service = DisplayWindowService();

  Slide projectionWithViewLimit() {
    final spec = viewLimit;
    if (spec == null || !spec.isActive) return this;

    switch (type) {
      case SlideType.bullets:
      case SlideType.twoBullets:
      case SlideType.bulletsImage:
      case SlideType.timeline:
        final result = _service.applyToBullets(bullets, spec);
        if (!result.wasLimited) return this;
        // Geen bijschrift-bullet op een tijdlijn: die leest zijn bullets als
        // `marker :: titel :: beschrijving`, en een kale tekstregel rendert
        // daar als misvormde gebeurtenis (bewaker-bevinding #672).
        final caption = type == SlideType.timeline ? null : result.countCaption;
        final projected = caption != null
            ? [...result.items, caption]
            : result.items;
        return copyWith(bullets: projected);
      case SlideType.table:
      case SlideType.scorecard:
      case SlideType.assets:
      case SlideType.discoveries:
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.findingsSummary:
        final result = _service.applyToTable(tableRows, spec, unit: 'regels');
        if (!result.wasLimited) return this;
        final rows = result.items.toList();
        if (result.countCaption != null) {
          final colCount = rows.isEmpty ? 1 : rows.first.length;
          rows.add([result.countCaption!, ...List.filled(colCount - 1, '')]);
        }
        return copyWith(tableRows: rows);
      case SlideType.chart:
        final chart = ChartSpec.parse(customMarkdown);
        final result = _service.applyToChart(chart, spec);
        if (!result.wasLimited) return this;
        final titled =
            result.countCaption != null && result.countCaption!.isNotEmpty
            ? result.items.copyWith(
                title: result.items.title.isEmpty
                    ? result.countCaption!
                    : '${result.items.title} — ${result.countCaption}',
              )
            : result.items;
        return copyWith(customMarkdown: titled.toBlock());
      default:
        return this;
    }
  }
}
