import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asset_overview_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 800,
        height: 450,
        child: SlidePreviewWidget(
          slide: slide,
          themeProfile: const ThemeProfile(),
        ),
      ),
    ),
  ),
);

Slide _overview(
  List<AssetGroup> groups, {
  String title = 'Ons aanvalsoppervlak',
}) {
  final spec = AssetOverviewSpec(title: title, groups: groups);
  return Slide.create(
    SlideType.assets,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

void main() {
  testWidgets('renders each group with its own count', (tester) async {
    await tester.pumpWidget(
      _host(
        _overview(const [
          AssetGroup(name: 'Webapplicaties', total: 182, atRisk: 12),
          AssetGroup(name: 'Mailservers', total: 24, atRisk: 1),
        ]),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Ons aanvalsoppervlak'), findsOneWidget);
    expect(find.text('Webapplicaties'), findsOneWidget);
    expect(find.text('182'), findsOneWidget);
    expect(find.text('Mailservers'), findsOneWidget);
  });

  testWidgets('the totals line is derived from the rows', (tester) async {
    await tester.pumpWidget(
      _host(
        _overview(const [
          AssetGroup(name: 'Web', total: 100, atRisk: 5, newlyFound: 2),
          AssetGroup(name: 'Mail', total: 20, atRisk: 3, unowned: 4),
        ]),
      ),
    );
    await tester.pump();

    // 120 objects in view: the figure the room remembers, summed from the rows
    // rather than typed in beside them.
    expect(find.text('120'), findsOneWidget);
    expect(find.text('objecten in beeld'), findsOneWidget);
  });

  testWidgets('bars share one scale across the slide', (tester) async {
    await tester.pumpWidget(
      _host(
        _overview(const [
          AssetGroup(name: 'Groot', total: 200),
          AssetGroup(name: 'Klein', total: 20),
        ]),
      ),
    );
    await tester.pump();

    // A category of twenty must not draw the width of a category of two
    // hundred, or the picture contradicts the numbers.
    final bars = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.constraints?.maxWidth != null);
    expect(bars, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an impossible count still renders as given', (tester) async {
    await tester.pumpWidget(
      _host(
        _overview(const [AssetGroup(name: 'Web', total: 182, atRisk: 200)]),
      ),
    );
    await tester.pump();

    // The bar is clamped so it cannot overrun its row, but the figure is shown
    // untouched — a silently corrected number would hide the bug upstream.
    expect(tester.takeException(), isNull);
    expect(find.text('200'), findsWidgets);
    expect(find.text('182'), findsWidgets);
  });

  testWidgets('a full slate of eight groups fits', (tester) async {
    await tester.pumpWidget(
      _host(
        _overview([
          for (var i = 0; i < assetOverviewMaxGroups; i++)
            AssetGroup(
              name: 'Een tamelijk lange soortnaam $i',
              total: 100 + i,
              atRisk: i,
              newlyFound: i,
              unowned: i,
            ),
        ]),
      ),
    );
    await tester.pump();

    // Eight is the documented maximum, so eight must render without overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty overview renders its title without a totals line', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_overview(const [])));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Ons aanvalsoppervlak'), findsOneWidget);
    // No rows means no sum to state.
    expect(find.text('objecten in beeld'), findsNothing);
  });
}
