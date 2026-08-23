import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/number_convention.dart';
import 'package:ocideck/widgets/editors/chart_editor.dart';

Widget _host(
  Slide slide,
  ValueChanged<Slide> onUpdate, {
  ValueChanged<List<Slide>>? onAddVariants,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 650,
        child: ChartEditor(
          slide: slide,
          onUpdate: onUpdate,
          onAddVariants: onAddVariants,
          themeAnimationDurationMs: kThemeDefaultAnimationDurationMs,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('chart grid fills the available editor width', (tester) async {
    const spec = ChartSpec(
      x: ['A', 'B'],
      series: [
        ChartSeries(name: 'Waarde', data: [10, 20]),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(slide, (_) {}));
    await tester.pump();

    final gridWidth = tester
        .getSize(find.byKey(const ValueKey('chart-grid')))
        .width;
    expect(gridWidth, greaterThanOrEqualTo(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving a row keeps its values and color together', (
    tester,
  ) async {
    const spec = ChartSpec(
      x: ['B', 'A'],
      rowColors: ['#EF4444', '#10B981'],
      series: [
        ChartSeries(name: 'Waarde', data: [20, 10]),
      ],
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.tap(find.byKey(const ValueKey('chart-row-up-1')));
    await tester.pump();

    final result = ChartSpec.parse(updated.customMarkdown);
    expect(result.x, ['A', 'B']);
    expect(result.rowColors, ['#10B981', '#EF4444']);
    expect(result.series.single.data, [10, 20]);
  });

  testWidgets('sorting a value column moves complete rows', (tester) async {
    const spec = ChartSpec(
      x: ['A', 'B', 'C'],
      rowColors: ['#003399', '#FFCC00', '#EF4444'],
      series: [
        ChartSeries(name: 'Waarde', data: [30, 10, 20]),
      ],
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.tap(find.byKey(const ValueKey('chart-sort-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oplopend sorteren'));
    await tester.pump();

    final result = ChartSpec.parse(updated.customMarkdown);
    expect(result.x, ['B', 'C', 'A']);
    expect(result.rowColors, ['#FFCC00', '#EF4444', '#003399']);
    expect(result.series.single.data, [10, 20, 30]);
  });

  testWidgets('pie dims the third series without disabling its input', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.pie,
      x: ['A'],
      series: [
        ChartSeries(name: 'Een', data: [1]),
        ChartSeries(name: 'Twee', data: [2]),
        ChartSeries(name: 'Drie', data: [3]),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(slide, (_) {}));
    await tester.pump();

    final column = tester.widget<Container>(
      find.byKey(const ValueKey('chart-series-column-2')),
    );
    expect(column.color, const Color(0xFFE2E8F0));
    final input = tester.widget<TextFormField>(
      find.byKey(const ValueKey('v-0-0-2')),
    );
    expect(input.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bound fields are offered for bar/line and emit min/max', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      x: ['A'],
      series: [
        ChartSeries(name: 'Waarde', data: [10]),
      ],
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.pump();

    expect(find.byKey(const ValueKey('chart-min-bound')), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-max-bound')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('chart-max-bound')), '20');
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).maxBound, 20);
  });

  testWidgets('bound fields are hidden for a pie chart', (tester) async {
    const spec = ChartSpec(
      type: ChartType.pie,
      x: ['A'],
      series: [
        ChartSeries(name: 'Een', data: [1]),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(slide, (_) {}));
    await tester.pump();

    expect(find.byKey(const ValueKey('chart-min-bound')), findsNothing);
    expect(find.byKey(const ValueKey('chart-max-bound')), findsNothing);
  });

  testWidgets('chart variants reuse data in the chosen order', (tester) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Omzet',
      x: ['A', 'B'],
      series: [
        ChartSeries(name: 'Waarde', data: [10, 20], color: '#003399'),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());
    List<Slide>? variants;

    await tester.pumpWidget(
      _host(slide, (_) {}, onAddVariants: (value) => variants = value),
    );
    await tester.tap(find.byKey(const ValueKey('chart-create-variants')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chart-variant-down-0')));
    await tester.pump();
    await tester.tap(find.text('Slides toevoegen'));
    await tester.pump();

    final specs = variants!.map((s) => ChartSpec.parse(s.customMarkdown));
    // Het dialoog biedt elk ánder type in enum-volgorde. Die volgorde afleiden
    // in plaats van uitschrijven: de opsomming brak bij elk nieuw grafiektype,
    // wat niets zegt over of het verplaatsen werkt — en dát is wat hier wordt
    // getoetst. De statistische types vallen weg: deze host heeft geen
    // ProviderScope, dus Procesverbetering staat uit.
    final expected = [
      for (final type in ChartType.values)
        if (type != ChartType.bar && !chartTypeRequiresProcesverbetering(type))
          type,
    ];
    // Item 0 één omlaag verwisselt de eerste twee.
    final swapped = [expected[1], expected[0], ...expected.skip(2)];
    expect(specs.map((s) => s.type), swapped);
    expect(specs.first.x, ['A', 'B']);
    expect(specs.first.series.single.data, [10, 20]);
    expect(specs.first.series.single.color, '#003399');
  });

  // A linked chart used to be read-only: the grid was disabled and the
  // Rij/Reeks buttons were hidden, because an edit had no way back to the file
  // and would vanish at the next save. Now that saving writes the file back,
  // linked and inline charts edit exactly alike.
  testWidgets('a chart linked to a data file is still editable', (
    tester,
  ) async {
    const spec = ChartSpec(
      x: ['A', 'B'],
      series: [
        ChartSeries(name: 'Waarde', data: [10, 20]),
      ],
      source: 'data/cijfers.json',
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.pump();

    // The grid takes input...
    await tester.enterText(find.widgetWithText(TextField, '10'), '42');
    await tester.pump();
    expect(
      ChartSpec.parse(updated.customMarkdown).series.single.data.first,
      42,
    );

    // ...and the structural buttons are there, not hidden behind the link.
    expect(find.text('Rij'), findsOneWidget);
    expect(find.text('Reeks'), findsOneWidget);
    await tester.tap(find.text('Rij'));
    await tester.pump();
    expect(ChartSpec.parse(updated.customMarkdown).x.length, 3);

    // The link itself survives editing — the file stays the chart's home.
    expect(ChartSpec.parse(updated.customMarkdown).source, 'data/cijfers.json');
  });

  testWidgets('unlinking a CSV source asks for confirmation first', (
    tester,
  ) async {
    const spec = ChartSpec(
      x: ['A', 'B'],
      series: [
        ChartSeries(name: 'Waarde', data: [10, 20]),
      ],
      source: 'data/cijfers.csv',
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.pump();

    // Annuleren laat de koppeling intact.
    await tester.tap(find.text('Ontkoppelen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(ChartSpec.parse(updated.customMarkdown).source, 'data/cijfers.csv');

    // Bevestigen verbreekt de koppeling echt.
    await tester.tap(find.text('Ontkoppelen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ontkoppelen').last);
    await tester.pumpAndSettle();
    expect(ChartSpec.parse(updated.customMarkdown).source, isNull);
  });

  group('askDecimalConvention', () {
    Future<DecimalConvention?> show(WidgetTester tester) async {
      DecimalConvention? picked;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await askDecimalConvention(context, [
                    '1,234',
                    '2,500',
                  ]);
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return returned ? picked : null;
    }

    testWidgets('shows both readings of the actual values', (tester) async {
      await show(tester);
      // The question is answerable because it is asked about this file's own
      // numbers, not about the words "decimal separator".
      expect(find.text('1,234 · 2,500'), findsOneWidget);
      expect(find.text('1234 · 2500'), findsOneWidget);
      expect(find.text('1.234 · 2.5'), findsOneWidget);
    });

    testWidgets('picking thousands returns the dot convention', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('csv-convention-thousands')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('backing out returns nothing, so the import stops', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('csvUnreadableMessage', () {
    const l10n = AppLocalizations(Locale('nl'));

    test('names the count and quotes the value verbatim', () {
      final message = csvUnreadableMessage(l10n, ['1,234']);
      expect(message, startsWith('1 '));
      // Verbatim, so the user can find it back in the source file.
      expect(message, contains('1,234'));
    });

    test('lists at most five values and marks that there are more', () {
      final message = csvUnreadableMessage(l10n, [
        'aa',
        'bb',
        'cc',
        'dd',
        'ee',
        'ff',
        'gg',
      ]);
      expect(message, startsWith('7 '));
      expect(message, contains('aa · bb · cc · dd · ee'));
      expect(message, isNot(contains('ff')));
      expect(message, endsWith('…'));
    });

    test('no ellipsis when everything fits', () {
      expect(csvUnreadableMessage(l10n, ['aa', 'bb']), endsWith('aa · bb'));
    });
  });
}
