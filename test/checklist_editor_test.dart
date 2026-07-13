import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/wstg_catalog.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/checklist_editor.dart';

/// Behaviour tests for the `checklist` slide editor: it edits the standard label
/// and per-row fields into the slide's title and `tableRows`, and adds/removes
/// rows. Storage stays a Markdown table, so we assert on the emitted
/// [Slide.tableRows] (header + one row per test) via [ChecklistSpec].
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is EditorField && w.label == label),
    matching: find.byType(TextField),
  );

  // A checklist slide with an explicit row count, so each test controls how many
  // rows the editor starts with (the default `Slide.create` seeds two).
  Slide slideWithRows(int n, {String title = ''}) =>
      Slide.create(SlideType.checklist).copyWith(
        title: title,
        tableRows: ChecklistSpec(
          standardLabel: title,
          rows: List.generate(n, (_) => const ChecklistRow()),
        ).toTableRows(),
      );

  Future<Slide? Function()> pump(WidgetTester tester, Slide slide) async {
    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChecklistEditor(slide: slide, onUpdate: (s) => updated = s),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  testWidgets('renders one row card per checklist row', (tester) async {
    await pump(tester, slideWithRows(2));

    expect(fieldByLabel('Standaard'), findsOneWidget);
    expect(fieldByLabel('ID'), findsNWidgets(2));
    expect(fieldByLabel('Test'), findsNWidgets(2));
  });

  testWidgets('the only row cannot be deleted', (tester) async {
    await pump(tester, slideWithRows(1));

    final delete = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(delete.onPressed, isNull);
  });

  testWidgets('editing the scope-object field emits Slide.checklistScope', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(1));

    final scopeField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'https://app.voorbeeld/login',
    );
    expect(scopeField, findsOneWidget);
    await tester.enterText(scopeField, 'https://app.example/login');
    await tester.pump();

    expect(latest()!.checklistScope, 'https://app.example/login');
  });

  testWidgets('editing the standard label emits it as the slide title', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.enterText(fieldByLabel('Standaard'), 'Checklist — OWASP WSTG');
    await tester.pump();

    expect(latest()!.title, 'Checklist — OWASP WSTG');
  });

  testWidgets('editing a row writes id/test cells into the table', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.enterText(fieldByLabel('ID'), 'WSTG-ATHN-07');
    await tester.enterText(fieldByLabel('Test'), 'Weak password policy');
    await tester.pump();

    final spec = ChecklistSpec.fromSlide(latest()!.title, latest()!.tableRows);
    expect(spec.rows.single.id, 'WSTG-ATHN-07');
    expect(spec.rows.single.test, 'Weak password policy');
  });

  testWidgets('"Test toevoegen" appends a row', (tester) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.tap(find.text('Test toevoegen'));
    await tester.pumpAndSettle();

    expect(fieldByLabel('ID'), findsNWidgets(2));
    final spec = ChecklistSpec.fromSlide(latest()!.title, latest()!.tableRows);
    expect(spec.rows.length, 2);
  });

  testWidgets('deleting a row removes it and re-emits', (tester) async {
    final latest = await pump(tester, slideWithRows(2));

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.delete_outline).first,
    );
    await tester.pumpAndSettle();

    expect(fieldByLabel('ID'), findsOneWidget);
    final spec = ChecklistSpec.fromSlide(latest()!.title, latest()!.tableRows);
    expect(spec.rows.length, 1);
  });

  testWidgets('changing the status dropdown writes the English token', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.tap(find.byType(DropdownButtonFormField<ChecklistStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afwijking').last);
    await tester.pumpAndSettle();

    final spec = ChecklistSpec.fromSlide(latest()!.title, latest()!.tableRows);
    expect(spec.rows.single.status, ChecklistStatus.anomaly);
    // The stable English token — not the Dutch label — is what gets stored.
    expect(latest()!.tableRows[1][2], 'Anomaly');
  });

  testWidgets(
    '"WSTG-testen laden" fills an empty checklist with the standard',
    (tester) async {
      final latest = await pump(tester, slideWithRows(1));

      await tester.tap(find.text('WSTG-testen laden'));
      await tester.pumpAndSettle();

      final spec = ChecklistSpec.fromSlide(
        latest()!.title,
        latest()!.tableRows,
      );
      expect(spec.rows.length, WstgCatalog.instance.tests.length);
      expect(spec.rows.first.id, 'WSTG-INFO-01');
      // The blank starter row is replaced, and the label carries the version.
      expect(latest()!.title, 'OWASP WSTG v4.2');
    },
  );

  testWidgets('loading is non-destructive and keeps existing rows + label', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.checklist).copyWith(
      title: 'Eigen standaard',
      tableRows: const ChecklistSpec(
        standardLabel: 'Eigen standaard',
        rows: [
          ChecklistRow(
            id: 'CUSTOM-01',
            test: 'Eigen test',
            status: ChecklistStatus.tested,
          ),
        ],
      ).toTableRows(),
    );
    final latest = await pump(tester, slide);

    await tester.tap(find.text('WSTG-testen laden'));
    await tester.pumpAndSettle();

    final spec = ChecklistSpec.fromSlide(latest()!.title, latest()!.tableRows);
    expect(spec.rows.length, WstgCatalog.instance.tests.length + 1);
    expect(spec.rows.first.id, 'CUSTOM-01');
    expect(spec.rows.first.status, ChecklistStatus.tested);
    // A non-empty label is left untouched.
    expect(latest()!.title, 'Eigen standaard');
  });

  testWidgets('loading twice does not duplicate tests', (tester) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.tap(find.text('WSTG-testen laden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WSTG-testen laden'));
    await tester.pumpAndSettle();

    final spec = ChecklistSpec.fromSlide(latest()!.title, latest()!.tableRows);
    expect(spec.rows.length, WstgCatalog.instance.tests.length);
  });
}
