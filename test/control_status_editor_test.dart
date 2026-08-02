import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/control_status_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/control_status_editor.dart';

/// Behaviour tests for the `controlStatus` editor: it edits the heading and the
/// per-control fields into the slide's title and `tableRows`, stores the stable
/// English status token, and — the headline feature — loads a chosen ISO
/// standard's control index in one action.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is EditorField && w.label == label),
    matching: find.byType(TextField),
  );

  Slide slideWithRows(List<ControlStatusRow> rows) =>
      Slide.create(SlideType.controlStatus).copyWith(
        tableRows: ControlStatusSpec(rows: rows).toTableRows(),
      );

  Future<Slide? Function()> pump(WidgetTester tester, Slide slide) async {
    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1100, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ControlStatusEditor(
              slide: slide,
              onUpdate: (s) => updated = s,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  testWidgets('renders the heading and one control row', (tester) async {
    await pump(tester, slideWithRows(const [ControlStatusRow()]));
    expect(fieldByLabel('Kop'), findsOneWidget);
    expect(fieldByLabel('ID'), findsOneWidget);
    expect(fieldByLabel('Beheersmaatregel'), findsOneWidget);
    expect(find.text('Beheersmaatregelen laden…'), findsOneWidget);
  });

  testWidgets('editing the heading emits it as the slide title', (tester) async {
    final latest = await pump(tester, slideWithRows(const [ControlStatusRow()]));
    await tester.enterText(fieldByLabel('Kop'), 'ISO 27001 · A.5');
    await tester.pump();
    expect(latest()!.title, 'ISO 27001 · A.5');
  });

  testWidgets('changing the status writes the English token', (tester) async {
    final latest = await pump(
      tester,
      slideWithRows(const [ControlStatusRow(id: 'A.5.1', control: 'x')]),
    );
    await tester.tap(find.byType(DropdownButtonFormField<ControlStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geïmplementeerd').last);
    await tester.pumpAndSettle();

    final spec = ControlStatusSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.single.status, ControlStatus.implemented);
    expect(latest()!.tableRows[1][2], 'Implemented');
  });

  testWidgets('setting the maturity writes the number', (tester) async {
    final latest = await pump(
      tester,
      slideWithRows(const [ControlStatusRow(id: 'A.5.1')]),
    );
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();

    final spec = ControlStatusSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.single.maturity, 3);
  });

  testWidgets('"Beheersmaatregel toevoegen" appends a row', (tester) async {
    await pump(tester, slideWithRows(const [ControlStatusRow()]));
    await tester.tap(find.text('Beheersmaatregel toevoegen'));
    await tester.pumpAndSettle();
    expect(fieldByLabel('ID'), findsNWidgets(2));
  });

  testWidgets('loading an ISO section fills the controls from the catalog', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(const [ControlStatusRow()]));

    await tester.tap(find.text('Beheersmaatregelen laden…'));
    await tester.pumpAndSettle();
    // Pick the standard…
    await tester.tap(find.text('ISO/IEC 27001:2022'));
    await tester.pumpAndSettle();
    // …then a single section (People controls has 8 entries — light to render).
    await tester.tap(find.text('A.6 · People controls'));
    await tester.pumpAndSettle();

    final spec = ControlStatusSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    // The single blank starter row is replaced by the 8 A.6 controls.
    expect(spec.rows.length, 8);
    expect(spec.rows.first.id, 'A.6.1');
    expect(spec.rows.first.control, 'Screening');
    expect(spec.rows.every((r) => r.status == ControlStatus.notStarted), isTrue);
  });
}
