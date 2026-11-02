import '../l10n/app_localizations.dart';
import '../models/chart.dart';
import '../utils/inline_markdown.dart';

/// Het tekstalternatief van een grafiek (WCAG 1.1.1): grafiektype, titel en de
/// onderliggende waarden per reeks, zodat een schermlezer dezelfde informatie
/// meegeeft als de visuele codering.
///
/// Gedeeld door de editor (`_ChartPreview`, als `Semantics`-label) en de
/// HTML-export (`<title>` + `role="img"` op de grafiek-SVG), zodat hetzelfde
/// diagram in app en export hetzelfde alternatief draagt (#2732).
String chartSemanticsLabel(AppLocalizations l10n, ChartSpec spec) {
  final typeName = switch (spec.type) {
    ChartType.bar => l10n.d('Staaf'),
    ChartType.stackedBar => l10n.d('Gestapelde staaf'),
    ChartType.line => l10n.d('Lijn'),
    ChartType.area => l10n.d('Vlak'),
    ChartType.pie => l10n.d('Cirkel'),
    ChartType.donut => l10n.d('Donut'),
    ChartType.radar => l10n.d('Spider'),
    ChartType.scatter => l10n.d('Spreiding'),
    ChartType.horizontalBar => l10n.d('Horizontale staaf'),
    ChartType.combo => l10n.d('Combo'),
    ChartType.waterfall => l10n.d('Waterval'),
    ChartType.heatmap => l10n.d('Heatmap'),
    ChartType.horizontalStackedBar =>
      l10n.d('Horizontale gestapelde staaf'),
    ChartType.bullet => l10n.d('Norm en prestatie'),
    ChartType.controlChart => l10n.d('Regelkaart'),
    ChartType.histogram => l10n.d('Histogram'),
    ChartType.pareto => l10n.d('Pareto'),
    ChartType.runChart => l10n.d('Run chart'),
    ChartType.boxPlot => l10n.d('Boxplot'),
    ChartType.probabilityPlot => l10n.d('Probability plot'),
    ChartType.mainEffects => l10n.d('Hoofdeffecten'),
    ChartType.interaction => l10n.d('Interactie'),
  };
  final buffer = StringBuffer('${l10n.d('Grafiek')} ($typeName)');
  if (spec.title.isNotEmpty) {
    buffer.write(': ${stripInlineMarkdown(spec.title)}');
  }
  if (!spec.hasInlineData) return buffer.toString();
  for (var si = 0; si < spec.series.length; si++) {
    final series = spec.series[si];
    final name = series.name.isEmpty
        ? '${l10n.d('Reeks')} ${si + 1}'
        : decodeNamedHtmlEntities(series.name);
    final values = [
      for (var xi = 0; xi < spec.x.length && xi < series.data.length; xi++)
        '${decodeNamedHtmlEntities(spec.x[xi])} ${_fmtNum(series.data[xi])}',
    ];
    buffer.write('. $name: ${values.join(', ')}');
  }
  return buffer.toString();
}

String _fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}
