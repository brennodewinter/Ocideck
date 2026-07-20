import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asset_overview_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/asset_overview_editor.dart';

Widget _host({required Slide slide, required ValueChanged<Slide> onUpdate}) =>
    MaterialApp(
      home: Scaffold(
        body: AssetOverviewEditor(slide: slide, onUpdate: onUpdate),
      ),
    );

AssetOverviewSpec _specOf(Slide slide) =>
    AssetOverviewSpec.fromSlide(slide.title, slide.tableRows);

Slide _slideWith(List<AssetGroup> groups) => Slide.create(
  SlideType.assets,
).copyWith(tableRows: AssetOverviewSpec(groups: groups).toTableRows());

void main() {
  testWidgets('a fresh slide opens with one row to fill in', (tester) async {
    final slide = Slide.create(SlideType.assets);
    expect(_specOf(slide).groups, isEmpty);

    await tester.pumpWidget(_host(slide: slide, onUpdate: (_) {}));
    expect(find.text('Soort object'), findsOneWidget);
    // A zero would be a figure the author has to select and overwrite; an
    // empty field invites one instead.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('typing counts emits them as table rows', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: Slide.create(SlideType.assets),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Webapplicaties'),
      'Webapplicaties',
    );
    await tester.enterText(find.widgetWithText(TextField, '182'), '182');
    await tester.enterText(find.widgetWithText(TextField, '12'), '12');
    await tester.pump();

    final group = _specOf(emitted!).groups.single;
    expect(group.name, 'Webapplicaties');
    expect(group.total, 182);
    expect(group.atRisk, 12);
    expect(group.unowned, 0);
  });

  testWidgets('the running totals follow what you type', (tester) async {
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [
          AssetGroup(name: 'Web', total: 100, atRisk: 5),
          AssetGroup(name: 'Mail', total: 20, atRisk: 3),
        ]),
        onUpdate: (_) {},
      ),
    );

    // A mistyped figure should be visible in the editor rather than on the
    // projector, so the banner sums as you go.
    expect(find.textContaining('120'), findsWidgets);
  });

  testWidgets('an impossible count is called out, not corrected', (
    tester,
  ) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [AssetGroup(name: 'Web', total: 182)]),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '12'), '200');
    await tester.pump();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // Called out, but the figure still goes through untouched — the author
    // decides what to do about it, not the app.
    expect(_specOf(emitted!).groups.single.atRisk, 200);
  });

  testWidgets('rows can be added up to the ceiling, then no further', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(slide: Slide.create(SlideType.assets), onUpdate: (_) {}),
    );

    for (var i = 1; i < assetOverviewMaxGroups; i++) {
      await tester.tap(find.text('Soort toevoegen'));
      await tester.pump();
    }
    expect(find.text('Soort object'), findsNWidgets(assetOverviewMaxGroups));

    final addButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Soort toevoegen'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(addButton.onPressed, isNull);
  });

  testWidgets('reordering moves the whole group, not just the name', (
    tester,
  ) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [
          AssetGroup(name: 'Eerste', total: 1),
          AssetGroup(name: 'Tweede', total: 2),
        ]),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    await tester.pump();

    final groups = _specOf(emitted!).groups;
    expect(groups.map((g) => g.name), ['Tweede', 'Eerste']);
    expect(groups.map((g) => g.total), [2, 1]);
  });
}
