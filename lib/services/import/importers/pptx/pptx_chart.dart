import 'package:xml/xml.dart';

import '../../models/source_chart.dart';
import 'pptx_context.dart';

/// Parse a PPTX chart part (`ppt/charts/chartN.xml`) into a best-effort
/// [SourceChart].
///
/// OciDeck's chart model is a small subset of DrawingML charts, so this is a
/// salvage: the chart type, categories, and numeric series are extracted;
/// formatting, axes titles, trendlines, and 3D effects are dropped (the
/// pipeline records those as conversion issues elsewhere).
SourceChart? parseChartXml(String xml) {
  final doc = XmlDocument.parse(xml);
  final plotArea = descendantsLocal(doc, 'plotArea').firstOrNull;
  if (plotArea == null) return null;

  final typeNode = _findChartType(plotArea);
  if (typeNode == null) return null;
  final (type, isStacked) = _chartType(typeNode);

  final firstSer = descendantsLocal(plotArea, 'ser').firstOrNull;
  final x = firstSer == null ? <String>[] : _categories(firstSer);
  final series = <SourceChartSeries>[
    for (final ser in descendantsLocal(plotArea, 'ser'))
      if (_seriesData(ser) != null) _seriesData(ser)!,
  ];

  return SourceChart(
    type: type == SourceChartType.bar && isStacked
        ? SourceChartType.stackedBar
        : type,
    title: _chartTitle(doc),
    x: x,
    series: series,
  );
}

XmlElement? _findChartType(XmlElement plotArea) {
  const typeNames = {
    'barChart',
    'lineChart',
    'pieChart',
    'radarChart',
    'scatterChart',
    'areaChart',
    'doughnutChart',
    'bar3DChart',
    'line3DChart',
    'pie3DChart',
    'area3DChart',
    'ofPieChart',
  };
  for (final child in plotArea.children.whereType<XmlElement>()) {
    if (typeNames.contains(child.name.local)) return child;
  }
  return null;
}

(SourceChartType, bool) _chartType(XmlElement typeNode) {
  switch (typeNode.name.local) {
    case 'barChart':
    case 'bar3DChart':
      final grouping =
          childLocal(typeNode, 'grouping')?.getAttribute('val') ?? 'clustered';
      final stacked = grouping == 'stacked' || grouping == 'percentStacked';
      // barDir "bar" = horizontal bars; OciDeck has only vertical bars, so
      // both map to bar (the orientation loss is noted by the pipeline).
      return (SourceChartType.bar, stacked);
    case 'lineChart':
    case 'line3DChart':
    case 'areaChart':
    case 'area3DChart':
      return (SourceChartType.line, false);
    case 'pieChart':
    case 'pie3DChart':
    case 'doughnutChart':
    case 'ofPieChart':
      return (SourceChartType.pie, false);
    case 'radarChart':
      return (SourceChartType.radar, false);
    case 'scatterChart':
      return (SourceChartType.scatter, false);
  }
  return (SourceChartType.bar, false);
}

String _chartTitle(XmlDocument doc) {
  final title = descendantsLocal(doc, 'title').firstOrNull;
  if (title == null) return '';
  final runs = descendantsLocal(title, 't').map((e) => e.innerText).join('');
  return runs.trim();
}

List<String> _categories(XmlElement ser) {
  final cat = childLocal(ser, 'cat');
  if (cat == null) return const [];
  // String categories preferred; fall back to numeric ones as strings.
  final strCache = descendantsLocal(cat, 'strCache').firstOrNull;
  if (strCache != null) return _strPoints(strCache);
  final numCache = descendantsLocal(cat, 'numCache').firstOrNull;
  if (numCache != null) return _numPoints(numCache).map(_fmt).toList();
  final strLit = descendantsLocal(cat, 'strLit').firstOrNull;
  if (strLit != null) return _strPoints(strLit);
  return const [];
}

List<String> _strPoints(XmlElement cache) => [
  for (final pt in descendantsLocal(cache, 'pt'))
    descendantsLocal(pt, 'v').firstOrNull?.innerText.trim() ?? '',
];

List<double> _numPoints(XmlElement cache) => [
  for (final pt in descendantsLocal(cache, 'pt'))
    double.tryParse(
          descendantsLocal(pt, 'v').firstOrNull?.innerText.trim() ?? '',
        ) ??
        0,
];

SourceChartSeries? _seriesData(XmlElement ser) {
  final name = _seriesName(ser);
  final val = childLocal(ser, 'val');
  if (val == null) return null;
  final numCache = descendantsLocal(val, 'numCache').firstOrNull;
  final data = numCache == null ? <double>[] : _numPoints(numCache);
  if (name.isEmpty && data.isEmpty) return null;
  return SourceChartSeries(name: name, data: data);
}

String _seriesName(XmlElement ser) {
  final tx = childLocal(ser, 'tx');
  if (tx == null) return '';
  final strCache = descendantsLocal(tx, 'strCache').firstOrNull;
  if (strCache != null) {
    return _strPoints(strCache).join(' ').trim();
  }
  final v = descendantsLocal(tx, 'v').firstOrNull?.innerText.trim();
  return v ?? '';
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}
