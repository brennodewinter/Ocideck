import 'package:xml/xml.dart';

import '../../models/source_chart.dart';
import 'odp_context.dart';

/// Salvage an ODF chart sub-document (`ObjectCharts/N/content.xml`) into a
/// best-effort [SourceChart].
///
/// The chart's local `<table:table>` is the data source: row 0 holds the
/// series names (column 0 is the empty corner), and rows 1..n hold the
/// category label in column 0 and the numeric series values in the remaining
/// columns. The chart type is read from `<chart:chart chart:class="...">`.
SourceChart? parseOdpChartXml(String xml) {
  // Geen interne `try/catch`: een misvormde grafiek-XML mag opborrelen naar de
  // `guardParse` in [parsePage], die hem als grafiekverlies noteert (#877) —
  // gelijk aan het PPTX-pad. Een `null`-retour betekent "wel leesbaar, maar geen
  // bruikbare grafiek", niet "onleesbaar"; dat verschil houdt de melding eerlijk.
  final doc = XmlDocument.parse(xml);
  // `<chart:chart>` carries the class attribute; `<office:chart>` does not.
  final chartEl = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'chart' && _attr(e, 'class') != null)
      .firstOrNull;
  if (chartEl == null) return null;

  final type = _chartType(_attr(chartEl, 'class') ?? '');
  final stacked = _attr(chartEl, 'stacked') == 'true';
  final title = _chartTitle(doc);

  final tbl = descendantsLocal(doc, 'table').firstOrNull;
  if (tbl == null) {
    return SourceChart(
      type: type == SourceChartType.bar && stacked
          ? SourceChartType.stackedBar
          : type,
      title: title,
      x: const [],
      series: const [],
    );
  }

  final rows = _tableRows(tbl);
  if (rows.length < 2) return null;

  final header = rows.first;
  final dataRows = rows.sublist(1);
  final x = dataRows.map((r) => r.isEmpty ? '' : r.first).toList();
  final series = <SourceChartSeries>[];
  for (var col = 1; col < header.length; col++) {
    final name = header[col];
    final data = dataRows
        .map((r) => col < r.length ? _asDouble(r[col]) : 0.0)
        .toList();
    if (name.isNotEmpty || data.any((v) => v != 0)) {
      series.add(SourceChartSeries(name: name, data: data));
    }
  }

  return SourceChart(
    type: type == SourceChartType.bar && stacked
        ? SourceChartType.stackedBar
        : type,
    title: title,
    x: x,
    series: series,
  );
}

List<List<String>> _tableRows(XmlElement tbl) {
  final rows = <List<String>>[];
  for (final tr in childrenLocal(tbl, 'table-row')) {
    final cells = <String>[];
    for (final tc in childrenLocal(tr, 'table-cell')) {
      final repeat =
          int.tryParse(_attr(tc, 'number-columns-repeated') ?? '') ?? 1;
      final value = _cellStringValue(tc);
      for (var i = 0; i < repeat; i++) {
        cells.add(value);
      }
    }
    rows.add(cells);
  }
  return rows;
}

String _cellStringValue(XmlElement cell) {
  // Prefer the numeric office:value; fall back to text.
  final v = _attr(cell, 'value');
  if (v != null && v.isNotEmpty) return v;
  final parts = <String>[];
  for (final p in descendantsLocal(cell, 'p')) {
    parts.add(_innerText(p).trim());
  }
  return parts.join(' ').trim();
}

double _asDouble(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[^\d.\-eE]'), '')) ?? 0;

SourceChartType _chartType(String chartClass) {
  // chart:class values look like "chart:bar", "chart:line", etc.
  final c = chartClass.replaceFirst('chart:', '');
  return switch (c) {
    'bar' => SourceChartType.bar,
    'line' => SourceChartType.line,
    'area' => SourceChartType.line,
    'circle' || 'ring' => SourceChartType.pie,
    'radar' => SourceChartType.radar,
    'scatter' => SourceChartType.scatter,
    _ => SourceChartType.bar,
  };
}

String _chartTitle(XmlDocument doc) {
  final title = descendantsLocal(doc, 'title').firstOrNull;
  if (title == null) return '';
  return _innerText(title).trim();
}

String _innerText(XmlElement el) {
  final buf = StringBuffer();
  for (final node in el.descendants) {
    if (node is XmlText) buf.write(node.value);
  }
  return buf.toString();
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
