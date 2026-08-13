import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/slides/chart_hover.dart';

void main() {
  group('ChartHover', () {
    test('value equality and hashCode', () {
      expect(
        const ChartHover(series: 1, category: 2),
        const ChartHover(series: 1, category: 2),
      );
      expect(
        const ChartHover(series: 1, category: 2).hashCode,
        const ChartHover(series: 1, category: 2).hashCode,
      );
      expect(
        const ChartHover(series: 1, category: 2),
        isNot(const ChartHover(series: 1, category: 3)),
      );
    });

    test('isEmpty only when both indices are null', () {
      expect(const ChartHover().isEmpty, isTrue);
      expect(const ChartHover(series: 0).isEmpty, isFalse);
      expect(const ChartHover(category: 0).isEmpty, isFalse);
    });

    test('toJson/fromJson round-trips a hover with both indices', () {
      const hover = ChartHover(series: 2, category: 5);
      final decoded = ChartHover.fromJson(hover.toJson());
      expect(decoded, hover);
    });

    test('fromJson keeps a single-index hover (legend or slice only)', () {
      expect(
        ChartHover.fromJson({'s': 3, 'c': null}),
        const ChartHover(series: 3),
      );
      expect(
        ChartHover.fromJson({'s': null, 'c': 4}),
        const ChartHover(category: 4),
      );
    });

    test('fromJson returns null for a non-map or an all-null payload', () {
      expect(ChartHover.fromJson(null), isNull);
      expect(ChartHover.fromJson('nope'), isNull);
      expect(ChartHover.fromJson({'s': null, 'c': null}), isNull);
    });
  });

  group('ChartHoverController', () {
    test('setLocal notifies and normalises an empty hover to null', () {
      final controller = ChartHoverController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setLocal(const ChartHover(series: 1));
      expect(controller.local, const ChartHover(series: 1));
      expect(notifications, 1);

      // An empty hover clears rather than storing a "nothing" value.
      controller.setLocal(const ChartHover());
      expect(controller.local, isNull);
      expect(notifications, 2);
    });

    test('setLocal skips a no-op change', () {
      final controller = ChartHoverController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setLocal(const ChartHover(category: 2));
      controller.setLocal(const ChartHover(category: 2));
      expect(notifications, 1);
    });

    test('local and external are independent — no echo between them', () {
      final controller = ChartHoverController();

      // The other window's hover arrives as external...
      controller.setExternal(const ChartHover(category: 3));
      expect(controller.external, const ChartHover(category: 3));
      // ...and must not leak into this window's local (which the bridge would
      // otherwise rebroadcast, looping the two windows forever).
      expect(controller.local, isNull);

      controller.setLocal(const ChartHover(series: 0));
      expect(controller.local, const ChartHover(series: 0));
      // Applying local likewise leaves the incoming external untouched.
      expect(controller.external, const ChartHover(category: 3));
    });
  });
}
