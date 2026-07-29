import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/improvement_y01.dart';
import 'package:ocideck/services/improvement/chart_derivation.dart';
import 'package:ocideck/services/marp_html_service.dart';

void main() {
  group('resolveChartSpecLimits', () {
    const y01 = ImprovementY01Metric(usl: 12, lsl: 8, target: 10);

    test('local limits when yRef is absent', () {
      final limits = resolveChartSpecLimits(
        yRef: null,
        localUsl: 20,
        localLsl: 5,
        localProcessTarget: 15,
        y01: y01,
      );
      expect(limits.usl, 20);
      expect(limits.lsl, 5);
      expect(limits.processTarget, 15);
    });

    test('deck limits win when yRef is Y-01', () {
      final limits = resolveChartSpecLimits(
        yRef: 'Y-01',
        localUsl: 20,
        localLsl: 5,
        localProcessTarget: 15,
        y01: y01,
      );
      expect(limits.usl, 12);
      expect(limits.lsl, 8);
      expect(limits.processTarget, 10);
    });

    test('yRef match is case-insensitive', () {
      final limits = resolveChartSpecLimits(
        yRef: 'y-01',
        localUsl: 99,
        localLsl: 1,
        localProcessTarget: null,
        y01: y01,
      );
      expect(limits.usl, 12);
      expect(limits.lsl, 8);
    });
  });

  group('deriveHistogram with yRef', () {
    test('uses deck USL even when chart has different local USL', () {
      final data = [for (var i = 0; i < 30; i++) 10.0 + (i % 5) * 0.2];
      const deckY01 = ImprovementY01Metric(usl: 11.5, lsl: 9.5);
      final withYRef = deriveHistogram(
        ChartSpec(
          type: ChartType.histogram,
          yRef: 'Y-01',
          usl: 99,
          lsl: 1,
          x: [for (var i = 0; i < data.length; i++) '$i'],
          series: [ChartSeries(name: 'Y', data: data)],
        ),
        y01: deckY01,
      );
      final localOnly = deriveHistogram(
        ChartSpec(
          type: ChartType.histogram,
          usl: 99,
          lsl: 1,
          x: [for (var i = 0; i < data.length; i++) '$i'],
          series: [ChartSeries(name: 'Y', data: data)],
        ),
      );
      expect(withYRef, isNotNull);
      expect(localOnly, isNotNull);
      expect(withYRef!.cpk, isNotNull);
      expect(localOnly!.cpk, isNotNull);
      expect(withYRef.cpk, isNot(localOnly.cpk));
    });
  });

  group('ChartSpec.toBlock with yRef', () {
    test('keeps local usl/lsl when yRef is Y-01', () {
      final block = ChartSpec(
        type: ChartType.histogram,
        yRef: 'Y-01',
        usl: 20,
        lsl: 5,
        processTarget: 12,
        x: ['a'],
        series: [
          ChartSeries(name: 'Y', data: [1, 2, 3]),
        ],
      ).toBlock();
      expect(block, contains('"usl": 20'));
      expect(block, contains('"lsl": 5'));
      expect(block, contains('"processTarget": 12'));
      expect(block, contains('"yRef": "Y-01"'));
    });
  });

  group('HTML histogram export with yRef', () {
    test('draws USL/LSL lines when deck y01 resolves limits', () {
      final data = [for (var i = 0; i < 30; i++) 10.0 + (i % 5) * 0.2];
      final spec = ChartSpec(
        type: ChartType.histogram,
        yRef: 'Y-01',
        x: [for (var i = 0; i < data.length; i++) '$i'],
        series: [ChartSeries(name: 'Y', data: data)],
      );
      const deckY01 = ImprovementY01Metric(usl: 10.75, lsl: 10.05);
      final html = MarpHtmlService.renderChartBlocks(
        '```chart\n${spec.toBlock()}\n```',
        y01: deckY01,
      );
      expect(html, contains('stroke="#DC2626"'));
      expect(html, contains('<line'));
    });
  });
}
