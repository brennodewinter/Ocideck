import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/scope_matrix_editor.dart';

/// Behaviour tests for the `scopeMatrix` slide editor: it edits the title and
/// per-row object/note into the slide's title and `tableRows`, adds/removes
/// rows, and — because the test standard is bound to the object type — shows the
/// type's standard read-only and stores the stable English type/status tokens.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is EditorField && w.label == label),
    matching: find.byType(TextField),
  );

  // A scope-matrix slide with an explicit row count, so each test controls how
  // many rows the editor starts with (the default `Slide.create` seeds one).
  Slide slideWithRows(int n, {String title = ''}) =>
      Slide.create(SlideType.scopeMatrix).copyWith(
        title: title,
        tableRows: ScopeMatrixSpec(
          title: title,
          rows: List.generate(n, (_) => const ScopeRow()),
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
            body: ScopeMatrixEditor(slide: slide, onUpdate: (s) => updated = s),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  testWidgets('renders each row with its bound type standard', (tester) async {
    await pump(tester, slideWithRows(1));

    expect(fieldByLabel('Titel'), findsOneWidget);
    expect(fieldByLabel('Object'), findsOneWidget);
    // The default object type is `web`, whose bound standard is WSTG.
    expect(find.text('Standaard: WSTG'), findsOneWidget);
  });

  testWidgets('shows the "generate checklists" action (feedback #8)', (
    tester,
  ) async {
    await pump(tester, slideWithRows(1));
    expect(
      find.text('Genereer checklists voor scope-objecten'),
      findsOneWidget,
    );
  });

  testWidgets('the only row cannot be deleted', (tester) async {
    await pump(tester, slideWithRows(1));

    final delete = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(delete.onPressed, isNull);
  });

  testWidgets('editing the title emits it as the slide title', (tester) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.enterText(fieldByLabel('Titel'), 'Scope & dekking');
    await tester.pump();

    expect(latest()!.title, 'Scope & dekking');
  });

  testWidgets('editing the object writes it into the table', (tester) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.enterText(fieldByLabel('Object'), 'https://app.voorbeeld');
    await tester.pump();

    final spec = ScopeMatrixSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.single.object, 'https://app.voorbeeld');
  });

  testWidgets('"Object toevoegen" appends a row', (tester) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.tap(find.text('Object toevoegen'));
    await tester.pumpAndSettle();

    expect(fieldByLabel('Object'), findsNWidgets(2));
    final spec = ScopeMatrixSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.length, 2);
  });

  testWidgets('changing the type updates the shown standard and stored token', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.tap(find.byType(DropdownButtonFormField<ScopeObjectType>));
    await tester.pumpAndSettle();
    // `Infrastructuur` is the Dutch label for the `infra` type (standard PTES).
    await tester.tap(find.text('Infrastructuur').last);
    await tester.pumpAndSettle();

    expect(find.text('Standaard: PTES'), findsOneWidget);
    final spec = ScopeMatrixSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.single.type, ScopeObjectType.infra);
    expect(latest()!.tableRows[1][1], 'Infra');
  });

  testWidgets('changing the status dropdown writes the English token', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(1));

    await tester.tap(find.byType(DropdownButtonFormField<ScopeStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afwijking').last);
    await tester.pumpAndSettle();

    final spec = ScopeMatrixSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.single.status, ScopeStatus.deviation);
    expect(latest()!.tableRows[1][3], 'Deviation');
  });

  testWidgets('move-down reorders the objects', (tester) async {
    final slide = Slide.create(SlideType.scopeMatrix).copyWith(
      tableRows: ScopeMatrixSpec(
        rows: const [
          ScopeRow(object: 'A'),
          ScopeRow(object: 'B'),
        ],
      ).toTableRows(),
    );
    final latest = await pump(tester, slide);

    // Row 0's "down" button moves A below B.
    await tester.tap(find.byIcon(Icons.arrow_downward).first);
    await tester.pumpAndSettle();

    final spec = ScopeMatrixSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.map((r) => r.object), ['B', 'A']);
  });

  testWidgets('setting the confidentiality rating writes its token', (
    tester,
  ) async {
    final latest = await pump(tester, slideWithRows(1));

    // The three CIA dropdowns are confidentiality, integrity, availability; the
    // first is confidentiality. Value labels render in the interface language.
    await tester.tap(find.byType(DropdownButton<CiaLevel>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('H · Hoog').last);
    await tester.pumpAndSettle();

    final spec = ScopeMatrixSpec.fromSlide(
      latest()!.title,
      latest()!.tableRows,
    );
    expect(spec.rows.single.cia.confidentiality, CiaLevel.high);
    // C is the sixth column (index 5), empty for the still-unset I and A.
    expect(latest()!.tableRows[1].sublist(5), ['H', '', '']);
  });
}
