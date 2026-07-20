import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/scorecard_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/scorecard_editor.dart';

Widget _host({required Slide slide, required ValueChanged<Slide> onUpdate}) =>
    MaterialApp(
      home: Scaffold(
        body: ScorecardEditor(slide: slide, onUpdate: onUpdate),
      ),
    );

ScorecardSpec _specOf(Slide slide) =>
    ScorecardSpec.fromSlide(slide.title, slide.tableRows);

void main() {
  testWidgets('a fresh slide opens with one row to fill in', (tester) async {
    final slide = Slide.create(SlideType.scorecard);
    // Nothing but the header reaches disk — the row exists only in the editor.
    expect(_specOf(slide).entries, isEmpty);

    await tester.pumpWidget(_host(slide: slide, onUpdate: (_) {}));
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Label'), findsOneWidget);
  });

  testWidgets('typing a figure emits it as table rows', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: Slide.create(SlideType.scorecard),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Open bevindingen'),
      'Open bevindingen',
    );
    await tester.enterText(find.widgetWithText(TextField, '96'), '96');
    await tester.enterText(find.widgetWithText(TextField, '120'), '120');
    await tester.pump();

    final spec = _specOf(emitted!);
    expect(spec.entries.single.label, 'Open bevindingen');
    expect(spec.entries.single.value, 96);
    expect(spec.entries.single.previous, 120);
    expect(spec.entries.single.delta, -24);
  });

  testWidgets('choosing a polarity rides along to the slide', (tester) async {
    Slide? emitted;
    final slide = Slide.create(SlideType.scorecard).copyWith(
      tableRows: const ScorecardSpec(
        entries: [ScorecardEntry(label: 'Open', value: 96, previous: 120)],
      ).toTableRows(),
    );
    await tester.pumpWidget(_host(slide: slide, onUpdate: (s) => emitted = s));

    await tester.tap(find.byType(DropdownButtonFormField<ScorecardPolarity>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lager is beter').last);
    await tester.pumpAndSettle();

    final entry = _specOf(emitted!).entries.single;
    expect(entry.polarity, ScorecardPolarity.lowerBetter);
    // The fall now reads as good news, without the arrow having moved.
    expect(entry.direction, ScorecardDirection.down);
    expect(entry.sentiment, ScorecardSentiment.good);
  });

  testWidgets('rows can be added up to the ceiling, then no further', (
    tester,
  ) async {
    // Five cards plus the button do not fit a default test window, and a
    // ListView never builds what is off-screen — so give it room to exist.
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(slide: Slide.create(SlideType.scorecard), onUpdate: (_) {}),
    );

    for (var i = 1; i < scorecardMaxEntries; i++) {
      await tester.tap(find.text('Cijfer toevoegen'));
      await tester.pump();
    }
    expect(find.text('Label'), findsNWidgets(scorecardMaxEntries));

    // At the ceiling the button goes dead rather than silently dropping a row
    // on write. `OutlinedButton.icon` builds a subclass, so match on the base
    // type rather than the exact runtime type byType would demand.
    final addButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Cijfer toevoegen'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(addButton.onPressed, isNull);
  });

  testWidgets('a row can be removed, but never the last one', (tester) async {
    Slide? emitted;
    final slide = Slide.create(SlideType.scorecard).copyWith(
      tableRows: const ScorecardSpec(
        entries: [
          ScorecardEntry(label: 'Eerste', value: 1),
          ScorecardEntry(label: 'Tweede', value: 2),
        ],
      ).toTableRows(),
    );
    await tester.pumpWidget(_host(slide: slide, onUpdate: (s) => emitted = s));

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    expect(_specOf(emitted!).entries.map((e) => e.label), ['Tweede']);

    // One row left: the delete button is disabled rather than leaving the
    // editor with nothing to type into.
    final remaining = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.delete_outline),
        matching: find.byType(IconButton),
      ),
    );
    expect(remaining.onPressed, isNull);
  });

  testWidgets('reordering moves the figure, not just the field', (
    tester,
  ) async {
    Slide? emitted;
    final slide = Slide.create(SlideType.scorecard).copyWith(
      tableRows: const ScorecardSpec(
        entries: [
          ScorecardEntry(label: 'Eerste', value: 1),
          ScorecardEntry(label: 'Tweede', value: 2),
        ],
      ).toTableRows(),
    );
    await tester.pumpWidget(_host(slide: slide, onUpdate: (s) => emitted = s));

    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    await tester.pump();

    final spec = _specOf(emitted!);
    expect(spec.entries.map((e) => e.label), ['Tweede', 'Eerste']);
    expect(spec.entries.map((e) => e.value), [2, 1]);
  });
}
