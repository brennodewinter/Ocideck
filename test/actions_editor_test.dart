import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/actions_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/actions_editor.dart';

Widget _host({required Slide slide, required ValueChanged<Slide> onUpdate}) =>
    MaterialApp(
      home: Scaffold(
        body: ActionsEditor(slide: slide, onUpdate: onUpdate),
      ),
    );

ActionsSpec _specOf(Slide slide) =>
    ActionsSpec.fromSlide(slide.title, slide.tableRows);

Slide _slideWith(List<ActionItem> items) => Slide.create(
  SlideType.actions,
).copyWith(tableRows: ActionsSpec(items: items).toTableRows());

void main() {
  testWidgets('a fresh slide opens with one line to fill in', (tester) async {
    final slide = Slide.create(SlideType.actions);
    expect(_specOf(slide).items, isEmpty);

    await tester.pumpWidget(_host(slide: slide, onUpdate: (_) {}));
    expect(find.text('Actie'), findsOneWidget);
  });

  testWidgets('typing an action emits it as table rows', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: Slide.create(SlideType.actions),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Testomgeving uit de lucht halen'),
      'acc-oud uit de lucht',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Team Platform'),
      'Infra',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '2026-08-15'),
      '2026-09-01',
    );
    await tester.pump();

    final item = _specOf(emitted!).items.single;
    expect(item.action, 'acc-oud uit de lucht');
    expect(item.owner, 'Infra');
    expect(item.due, DateTime(2026, 9, 1));
  });

  testWidgets('a half-typed date simply does not land yet', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: Slide.create(SlideType.actions),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Testomgeving uit de lucht halen'),
      'Iets doen',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '2026-08-15'),
      '2026-',
    );
    await tester.pump();

    // The row survives; only the unreadable date is left empty, so typing a
    // date one character at a time never destroys the line.
    final item = _specOf(emitted!).items.single;
    expect(item.action, 'Iets doen');
    expect(item.due, isNull);
  });

  testWidgets('choosing what is asked rides along to the slide', (
    tester,
  ) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [ActionItem(action: 'Keuze nodig')]),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<ActionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Besluit gevraagd').last);
    await tester.pumpAndSettle();

    expect(_specOf(emitted!).items.single.kind, ActionKind.decision);
  });

  testWidgets('marking an action done clears its lateness', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: _slideWith([
          ActionItem(action: 'Was laat', due: DateTime(2020, 1, 1)),
        ]),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<ActionStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afgerond').last);
    await tester.pumpAndSettle();

    final item = _specOf(emitted!).items.single;
    expect(item.status, ActionStatus.done);
    expect(item.isOverdue(DateTime(2026, 7, 20)), isFalse);
  });

  testWidgets('lines can be added up to the ceiling, then no further', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(slide: Slide.create(SlideType.actions), onUpdate: (_) {}),
    );

    for (var i = 1; i < actionsMaxItems; i++) {
      await tester.tap(find.text('Actie toevoegen'));
      await tester.pump();
    }
    expect(find.text('Actie'), findsNWidgets(actionsMaxItems));

    final addButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Actie toevoegen'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(addButton.onPressed, isNull);
  });

  testWidgets('reordering moves the whole line, not just the text', (
    tester,
  ) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(
        slide: _slideWith(const [
          ActionItem(action: 'Eerste', owner: 'A'),
          ActionItem(action: 'Tweede', owner: 'B'),
        ]),
        onUpdate: (s) => emitted = s,
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    await tester.pump();

    final items = _specOf(emitted!).items;
    expect(items.map((i) => i.action), ['Tweede', 'Eerste']);
    expect(items.map((i) => i.owner), ['B', 'A']);
  });
}
