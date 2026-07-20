import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/discoveries_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/discoveries_editor.dart';

Widget _host({required Slide slide, required ValueChanged<Slide> onUpdate}) =>
    MaterialApp(
      home: Scaffold(
        body: DiscoveriesEditor(slide: slide, onUpdate: onUpdate),
      ),
    );

DiscoveriesSpec _specOf(Slide slide) =>
    DiscoveriesSpec.fromSlide(slide.title, slide.tableRows);

Slide _slideWith(List<Discovery> discoveries) => Slide.create(
  SlideType.discoveries,
).copyWith(tableRows: DiscoveriesSpec(discoveries: discoveries).toTableRows());

/// The add button. `OutlinedButton.icon` builds a private subclass, so
/// `find.byType(OutlinedButton)` — which matches on exact runtime type — never
/// sees it; match on the supertype instead.
final _addButton = find.ancestor(
  of: find.text('Ontdekking toevoegen'),
  matching: find.byWidgetPredicate((w) => w is OutlinedButton),
);

/// Renders on a surface tall enough to hold six cards plus the button, so a
/// test about the ceiling is not really a test about scrolling.
Future<void> _pumpTall(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

void main() {
  testWidgets('a fresh slide opens with one row to fill in', (tester) async {
    final slide = Slide.create(SlideType.discoveries);
    expect(_specOf(slide).discoveries, isEmpty);

    await tester.pumpWidget(_host(slide: slide, onUpdate: (_) {}));

    expect(find.text('Wat is gevonden'), findsOneWidget);
    expect(find.text('Dagen onopgemerkt'), findsOneWidget);
  });

  testWidgets('typing a find emits it as table rows', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: Slide.create(SlideType.discoveries),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'betaalportaal-acc.example.nl'),
      'oud-intranet.example.nl',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Webapplicatie'),
      'Webapplicatie',
    );
    await tester.enterText(find.widgetWithText(TextField, '412'), '280');
    await tester.pump();

    final discovery = _specOf(emitted!).discoveries.single;
    expect(discovery.name, 'oud-intranet.example.nl');
    expect(discovery.kind, 'Webapplicatie');
    expect(discovery.daysUnnoticed, 280);
    // Left empty, so it stays empty rather than becoming a name.
    expect(discovery.hasOwner, isFalse);
  });

  testWidgets('the banner follows what you type', (tester) async {
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [Discovery(name: 'a', daysUnnoticed: 10)]),
        onUpdate: (_) {},
      ),
    );

    expect(find.textContaining('1 ontdekking'), findsOneWidget);
    expect(find.textContaining('10 dagen onopgemerkt'), findsOneWidget);

    // A mistyped exposure must show up here, not on the projector.
    await tester.enterText(find.widgetWithText(TextField, '412'), '4120');
    await tester.pump();

    expect(find.textContaining('4120 dagen onopgemerkt'), findsOneWidget);
  });

  testWidgets('an empty owner is counted in the banner', (tester) async {
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [
          Discovery(name: 'a', daysUnnoticed: 10, owner: 'Team A'),
          Discovery(name: 'b', daysUnnoticed: 10),
        ]),
        onUpdate: (_) {},
      ),
    );

    expect(find.textContaining('1 geen eigenaar'), findsOneWidget);
  });

  testWidgets('without any exposure the banner says the headline is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [Discovery(name: 'a')]),
        onUpdate: (_) {},
      ),
    );

    expect(find.textContaining('Nog geen blootstelling'), findsOneWidget);
    expect(find.textContaining('Kop van de slide'), findsNothing);
  });

  testWidgets('the add button stops at the documented maximum', (tester) async {
    await _pumpTall(
      tester,
      _host(
        slide: _slideWith([
          for (var i = 0; i < discoveriesMaxEntries; i++)
            Discovery(name: 'find $i'),
        ]),
        onUpdate: (_) {},
      ),
    );

    expect(tester.widget<OutlinedButton>(_addButton).onPressed, isNull);
  });

  testWidgets('adding and removing a row emits the new list', (tester) async {
    Slide? emitted;
    await _pumpTall(
      tester,
      _host(
        slide: _slideWith(const [Discovery(name: 'a'), Discovery(name: 'b')]),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.tap(_addButton);
    await tester.pump();
    // The new row is blank, so it never reaches the table.
    expect(_specOf(emitted!).discoveries, hasLength(2));

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    expect(_specOf(emitted!).discoveries.single.name, 'b');
  });

  testWidgets('the last row cannot be removed', (tester) async {
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [Discovery(name: 'a')]),
        onUpdate: (_) {},
      ),
    );

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.delete_outline),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('moving a row down reorders the emitted table', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [
          Discovery(name: 'eerst'),
          Discovery(name: 'tweede'),
        ]),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_downward).first);
    await tester.pump();

    expect(_specOf(emitted!).discoveries.map((d) => d.name), [
      'tweede',
      'eerst',
    ]);
  });
}
