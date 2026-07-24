import '../../../models/conversion_issue.dart';
import '../../../models/source_chart.dart';
import 'iwa_archive.dart';
import 'iwa_document.dart';
import 'proto_wire.dart';

/// Reconstruct a [SourceChart] from a Keynote IWA `ChartDrawableArchive`.
///
/// A chart drawable carries a `TSCH.ChartArchive` extension (field 10000) on its
/// `TSD.DrawableArchive` super. The chart archive describes the chart type and
/// either embeds a `ChartGridArchive` (field 7) or points at a mediator that
/// references a grid. The grid stores row/column names and the numeric values.
///
/// Only data that maps to OciDeck's `SourceChart` model is salvaged:
/// bar, stackedBar, line, pie, radar and scatter. More exotic or 3D chart
/// types are mapped to the closest supported type and reported as issues.
class ChartReconstructor {
  ChartReconstructor(this.doc);

  final IwaDocument doc;

  /// Conversion issues raised while reconstructing this chart.
  final List<ConversionIssue> issues = [];

  /// Parses the chart from [chartDrawable] (a `TSCH.ChartDrawableArchive`).
  SourceChart? reconstruct(IwaObject chartDrawable, int slideIndex) {
    issues.clear();
    final chartArchive = chartDrawable.message.message(10000);
    if (chartArchive == null) return null;

    final chartType = chartArchive.varint(1);
    final seriesDirection = chartArchive.varint(5);
    final scatterFormat = chartArchive.varint(2);
    if (chartType == null) return null;

    final grid = _gridMessage(chartDrawable, chartArchive);
    if (grid == null) return null;

    final rowNames = grid.strings(1);
    final columnNames = grid.strings(2);
    final matrix = _readMatrix(grid);
    if (matrix.isEmpty) return null;

    final (type, typeIssue) = _mapChartType(chartType, scatterFormat);
    if (typeIssue != null) {
      issues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Ondersteund grafiektype',
          description: typeIssue,
          salvagedAs: _chartTypeName(type),
        ),
      );
    }

    final byRow = _isByRow(seriesDirection, matrix, columnNames);
    final (x, series) = _buildSeries(
      type,
      matrix,
      rowNames,
      columnNames,
      byRow,
      scatterFormat,
    );

    if (series.isEmpty) return null;

    if (scatterFormat != null && scatterFormat == 1) {
      // scatter_format_separate_x: each series has its own x values.
      // OciDeck's SourceChart only supports a shared x axis, so note it.
      issues.add(
        ConversionIssue(
          slideIndex: slideIndex,
          feature: 'Scatter x-as',
          description:
              'Scatter-grafiek met aparte x-waardes per serie kan '
              'niet volledig worden weergegeven.',
          salvagedAs: 'gedeelde x-as gebruikt',
        ),
      );
    }

    return SourceChart(type: type, x: x, series: series, title: '');
  }

  /// Returns the `ChartGridArchive` message for [chartArchive], either embedded
  /// or reached through a `ChartMediatorArchive`.
  ProtoMessage? _gridMessage(
    IwaObject chartDrawable,
    ProtoMessage chartArchive,
  ) {
    final embedded = chartArchive.message(7);
    if (embedded != null) return embedded;

    final mediatorRef = chartArchive.varint(8);
    if (mediatorRef == null) return null;
    final mediator = doc.resolveReference(chartDrawable, mediatorRef);
    if (mediator == null) return null;

    final infoRef = mediator.message.varint(1);
    if (infoRef == null) return null;
    final grid = doc.resolveReference(mediator, infoRef);
    return grid?.message;
  }

  /// Reads the matrix of `GridValue` doubles from [grid].
  List<List<double>> _readMatrix(ProtoMessage grid) {
    final matrix = <List<double>>[];
    for (final row in grid.messages(3)) {
      final values = <double>[];
      for (final value in row.messages(1)) {
        values.add(value.double64(1) ?? value.double64(2) ?? 0.0);
      }
      if (values.isNotEmpty) matrix.add(values);
    }
    return matrix;
  }

  /// True when the data is organised by row (series are rows). If the archive
  /// does not specify, we fall back to a sensible default based on the shape.
  bool _isByRow(
    int? seriesDirection,
    List<List<double>> matrix,
    List<String> columnNames,
  ) {
    if (seriesDirection == 1) return true; // series_direction_by_row
    if (seriesDirection == 2) return false; // series_direction_by_column
    // Fallback: when there are fewer rows than columns, rows are the series.
    return matrix.length <= columnNames.length;
  }

  /// Builds the OciDeck `x` labels and `series` list from the chart grid.
  (List<String>, List<SourceChartSeries>) _buildSeries(
    SourceChartType type,
    List<List<double>> matrix,
    List<String> rowNames,
    List<String> columnNames,
    bool byRow,
    int? scatterFormat,
  ) {
    final x = <String>[];
    final series = <SourceChartSeries>[];

    if (byRow) {
      final categories = columnNames;
      if (type == SourceChartType.scatter && scatterFormat == 2) {
        // shared x: first column is the x axis, remaining columns are y series.
        x.addAll(matrix.map((r) => _formatNumber(r.first)));
        for (var c = 1; c < categories.length; c++) {
          final data = <double>[];
          for (var r = 0; r < matrix.length; r++) {
            if (c < matrix[r].length) data.add(matrix[r][c]);
          }
          series.add(
            SourceChartSeries(name: _label(categories, c), data: data),
          );
        }
      } else {
        x.addAll(categories);
        for (var r = 0; r < matrix.length; r++) {
          if (type == SourceChartType.pie && series.isNotEmpty) continue;
          final data = <double>[];
          for (var c = 0; c < matrix[r].length; c++) {
            data.add(matrix[r][c]);
          }
          series.add(SourceChartSeries(name: _label(rowNames, r), data: data));
        }
      }
    } else {
      final categories = rowNames;
      if (type == SourceChartType.scatter && scatterFormat == 2) {
        // shared x: first row is the x axis, remaining rows are y series.
        x.addAll(matrix[0].map(_formatNumber));
        for (var r = 1; r < matrix.length; r++) {
          final data = <double>[];
          for (var c = 0; c < matrix[r].length; c++) {
            data.add(matrix[r][c]);
          }
          series.add(
            SourceChartSeries(name: _label(categories, r), data: data),
          );
        }
      } else {
        x.addAll(categories);
        final colCount = matrix.isEmpty ? 0 : matrix.first.length;
        for (var c = 0; c < colCount; c++) {
          if (type == SourceChartType.pie && series.isNotEmpty) continue;
          final data = <double>[];
          for (var r = 0; r < matrix.length; r++) {
            if (c < matrix[r].length) data.add(matrix[r][c]);
          }
          series.add(
            SourceChartSeries(name: _label(columnNames, c), data: data),
          );
        }
      }
    }

    return (x, series);
  }

  String _label(List<String> names, int index) {
    if (index < names.length && names[index].trim().isNotEmpty) {
      return names[index].trim();
    }
    return 'Serie ${index + 1}';
  }

  String _formatNumber(double v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(12).replaceFirstMapped(RegExp(r'0+$'), (m) => '');
  }

  (SourceChartType, String?) _mapChartType(int chartType, int? scatterFormat) {
    switch (chartType) {
      case 1: // columnChartType2D
        return (SourceChartType.bar, null);
      case 2: // barChartType2D
        return (SourceChartType.bar, null);
      case 3: // lineChartType2D
        return (SourceChartType.line, null);
      case 4: // areaChartType2D
        return (
          SourceChartType.line,
          'Area-grafiek is geconverteerd naar lijn.',
        );
      case 5: // pieChartType2D
        return (SourceChartType.pie, null);
      case 6: // stackedColumnChartType2D
        return (SourceChartType.stackedBar, null);
      case 7: // stackedBarChartType2D
        return (SourceChartType.stackedBar, null);
      case 8: // stackedAreaChartType2D
        return (
          SourceChartType.stackedBar,
          'Gestapelde area-grafiek is geconverteerd naar gestapelde balken.',
        );
      case 9: // scatterChartType2D
        return (SourceChartType.scatter, null);
      case 10: // mixedChartType2D
        return (
          SourceChartType.line,
          'Mixed grafiek is geconverteerd naar lijn.',
        );
      case 11: // twoAxisChartType2D
        return (
          SourceChartType.line,
          'Twee-as grafiek is geconverteerd naar lijn.',
        );
      case 20: // multiDataColumnChartType2D
        return (SourceChartType.bar, null);
      case 21: // multiDataBarChartType2D
        return (SourceChartType.bar, null);
      case 22: // bubbleChartType2D
        return (
          SourceChartType.scatter,
          'Bubble-grootte is genegeerd bij conversie naar scatter.',
        );
      case 23: // multiDataScatterChartType2D
        return (SourceChartType.scatter, null);
      case 24: // multiDataBubbleChartType2D
        return (
          SourceChartType.scatter,
          'Bubble-grootte is genegeerd bij conversie naar scatter.',
        );
      case 12: // columnChartType3D
        return (
          SourceChartType.bar,
          '3D-kolomgrafiek is geconverteerd naar 2D-balken.',
        );
      case 13: // barChartType3D
        return (
          SourceChartType.bar,
          '3D-balkgrafiek is geconverteerd naar 2D-balken.',
        );
      case 14: // lineChartType3D
        return (
          SourceChartType.line,
          '3D-lijndiagram is geconverteerd naar 2D-lijn.',
        );
      case 15: // areaChartType3D
        return (
          SourceChartType.line,
          '3D-area-grafiek is geconverteerd naar 2D-lijn.',
        );
      case 16: // pieChartType3D
        return (
          SourceChartType.pie,
          '3D-cirkeldiagram is geconverteerd naar 2D-cirkel.',
        );
      case 17: // stackedColumnChartType3D
        return (
          SourceChartType.stackedBar,
          '3D-gestapelde kolommen zijn geconverteerd naar 2D-gestapelde balken.',
        );
      case 18: // stackedBarChartType3D
        return (
          SourceChartType.stackedBar,
          '3D-gestapelde balken zijn geconverteerd naar 2D-gestapelde balken.',
        );
      case 19: // stackedAreaChartType3D
        return (
          SourceChartType.stackedBar,
          '3D-gestapelde area is geconverteerd naar 2D-gestapelde balken.',
        );
      default:
        return (
          SourceChartType.bar,
          'Onbekend grafiektype is geconverteerd naar balken.',
        );
    }
  }

  String _chartTypeName(SourceChartType t) => switch (t) {
    SourceChartType.bar => 'bar',
    SourceChartType.stackedBar => 'stackedBar',
    SourceChartType.line => 'line',
    SourceChartType.pie => 'pie',
    SourceChartType.radar => 'radar',
    SourceChartType.scatter => 'scatter',
  };
}
