import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/chart_reconstructor.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_archive.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_document.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/proto_wire.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/snappy.dart';
import 'package:ocideck/services/import/models/source_chart.dart';

import 'helpers/key_fixtures.dart' as fx;

void main() {
  final wire = ProtoWire();
  final archive = IwaArchive(wire);
  final snappy = SnappyDecompressor();

  IwaDocument buildDoc(List<int> recordBytes) {
    final stream = fx.iwaStream(recordBytes);
    final objects = archive.parse(snappy.decompressIwaStream(stream));
    return IwaDocument(objects);
  }

  test('reconstructs a column chart by row', () {
    final grid = fx.chartGridPayload(
      rowNames: ['Q1', 'Q2'],
      columnNames: ['A', 'B'],
      gridRows: [
        fx.gridRowPayload([
          fx.gridValuePayload(10.0),
          fx.gridValuePayload(20.0),
        ]),
        fx.gridRowPayload([
          fx.gridValuePayload(30.0),
          fx.gridValuePayload(40.0),
        ]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 1, // columnChartType2D
      chartGrid: grid,
      seriesDirection: 1, // by row
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.bar);
    expect(chart.x, ['A', 'B']);
    expect(chart.series.length, 2);
    expect(chart.series[0].name, 'Q1');
    expect(chart.series[0].data, [10.0, 20.0]);
    expect(chart.series[1].name, 'Q2');
    expect(chart.series[1].data, [30.0, 40.0]);
    expect(reconstructor.issues, isEmpty);
  });

  test('reconstructs a line chart by column', () {
    final grid = fx.chartGridPayload(
      rowNames: ['A', 'B'],
      columnNames: ['Q1', 'Q2'],
      gridRows: [
        fx.gridRowPayload([
          fx.gridValuePayload(10.0),
          fx.gridValuePayload(30.0),
        ]),
        fx.gridRowPayload([
          fx.gridValuePayload(20.0),
          fx.gridValuePayload(40.0),
        ]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 3, // lineChartType2D
      chartGrid: grid,
      seriesDirection: 2, // by column
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.line);
    expect(chart.x, ['A', 'B']);
    expect(chart.series.length, 2);
    expect(chart.series[0].name, 'Q1');
    expect(chart.series[0].data, [10.0, 20.0]);
    expect(chart.series[1].name, 'Q2');
    expect(chart.series[1].data, [30.0, 40.0]);
  });

  test('reconstructs a pie chart and keeps only the first series', () {
    final grid = fx.chartGridPayload(
      rowNames: ['Q1', 'Q2'],
      columnNames: ['A', 'B'],
      gridRows: [
        fx.gridRowPayload([
          fx.gridValuePayload(10.0),
          fx.gridValuePayload(20.0),
        ]),
        fx.gridRowPayload([
          fx.gridValuePayload(30.0),
          fx.gridValuePayload(40.0),
        ]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 5, // pieChartType2D
      chartGrid: grid,
      seriesDirection: 1,
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.pie);
    expect(chart.series.length, 1);
    expect(chart.series.single.data, [10.0, 20.0]);
  });

  test('records an issue for a 3D chart', () {
    final grid = fx.chartGridPayload(
      rowNames: ['Q1'],
      columnNames: ['A'],
      gridRows: [
        fx.gridRowPayload([fx.gridValuePayload(42.0)]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 12, // columnChartType3D
      chartGrid: grid,
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.bar);
    expect(reconstructor.issues, isNotEmpty);
    expect(reconstructor.issues.first.feature, 'Ondersteund grafiektype');
  });

  test('maps many chart types to supported types and records issues', () {
    final cases = [
      (4, SourceChartType.line, true), // area -> line
      (6, SourceChartType.stackedBar, false), // stackedColumn
      (8, SourceChartType.stackedBar, true), // stackedArea -> stackedBar
      (22, SourceChartType.scatter, true), // bubble -> scatter
      (99, SourceChartType.bar, true), // unknown -> bar
    ];
    for (final (chartType, expected, hasIssue) in cases) {
      final grid = fx.chartGridPayload(
        rowNames: ['Q'],
        columnNames: ['A'],
        gridRows: [
          fx.gridRowPayload([fx.gridValuePayload(1.0)]),
        ],
      );
      final chartArchive = fx.chartArchivePayload(
        chartType: chartType,
        chartGrid: grid,
      );
      final chartDrawable = fx.record(
        11,
        6003,
        fx.chartDrawablePayload(chartArchive),
      );
      final doc = buildDoc(chartDrawable);
      final reconstructor = ChartReconstructor(doc);
      final chart = reconstructor.reconstruct(doc[11]!, 0);

      expect(chart, isNotNull, reason: 'chart type $chartType');
      expect(chart!.type, expected, reason: 'chart type $chartType');
      expect(
        reconstructor.issues.isNotEmpty,
        hasIssue,
        reason: 'chart type $chartType',
      );
    }
  });

  test('reconstructs a scatter chart with shared x by row', () {
    final grid = fx.chartGridPayload(
      rowNames: ['S1'],
      columnNames: ['X', 'Y'],
      gridRows: [
        fx.gridRowPayload([fx.gridValuePayload(1.0), fx.gridValuePayload(2.0)]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 9, // scatterChartType2D
      chartGrid: grid,
      scatterFormat: 2, // shared x
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.scatter);
    expect(chart.x, ['1']);
    expect(chart.series.length, 1);
    expect(chart.series.single.name, 'Y');
    expect(chart.series.single.data, [2.0]);
  });

  test('warns when a scatter chart has separate x values', () {
    final grid = fx.chartGridPayload(
      rowNames: ['S1', 'S2'],
      columnNames: ['A', 'B'],
      gridRows: [
        fx.gridRowPayload([fx.gridValuePayload(1.0), fx.gridValuePayload(2.0)]),
        fx.gridRowPayload([fx.gridValuePayload(3.0), fx.gridValuePayload(4.0)]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 9, // scatterChartType2D
      chartGrid: grid,
      scatterFormat: 1, // separate x
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.scatter);
    expect(
      reconstructor.issues.any((i) => i.feature == 'Scatter x-as'),
      isTrue,
    );
  });

  test('falls back to series by column when direction is not set', () {
    final grid = fx.chartGridPayload(
      rowNames: ['Q1', 'Q2'],
      columnNames: ['A'],
      gridRows: [
        fx.gridRowPayload([fx.gridValuePayload(10.0)]),
        fx.gridRowPayload([fx.gridValuePayload(20.0)]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 1, // column
      chartGrid: grid,
      seriesDirection: 0, // unspecified, fallback uses matrix shape
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.x, ['Q1', 'Q2']);
    expect(chart.series.single.name, 'A');
    expect(chart.series.single.data, [10.0, 20.0]);
  });

  test('returns null and uses default labels for empty names', () {
    final grid = fx.chartGridPayload(
      gridRows: [
        fx.gridRowPayload([fx.gridValuePayload(1.0)]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 1, // column
      chartGrid: grid,
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);
    final chart = reconstructor.reconstruct(doc[11]!, 0);

    expect(chart, isNotNull);
    expect(chart!.series.single.name, 'Serie 1');
  });

  test('returns null when the grid has no rows', () {
    final chartArchive = fx.chartArchivePayload(
      chartType: 1,
      chartGrid: fx.chartGridPayload(),
    );
    final chartDrawable = fx.record(
      11,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final doc = buildDoc(chartDrawable);
    final reconstructor = ChartReconstructor(doc);

    expect(reconstructor.reconstruct(doc[11]!, 0), isNull);
  });
}
