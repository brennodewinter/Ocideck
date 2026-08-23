import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/chart_editor.dart';

Widget _host(Slide slide, ValueChanged<Slide> onUpdate) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 1600,
          child: ChartEditor(
            slide: slide,
            onUpdate: onUpdate,
            themeAnimationDurationMs: kThemeDefaultAnimationDurationMs,
          ),
        ),
      ),
    ),
  );
}

Slide _chartSlide(ChartSpec spec) =>
    Slide.create(SlideType.chart).copyWith(customMarkdown: spec.toBlock());

/// Pumps on a tall surface so the full editor is realised and the 12-item
/// type dropdown is not scroll-clipped at the default test window height.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(host);
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('changing the chart type emits the new type and shows its hint', (
    tester,
  ) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A', 'B'],
        series: [
          ChartSeries(name: 'Waarde', data: [10, 20]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.tap(find.byType(DropdownButton<ChartType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heatmap').last);
    await tester.pumpAndSettle();

    expect(ChartSpec.parse(updated.customMarkdown).type, ChartType.heatmap);
    expect(find.textContaining('celkleur volgt de waarde'), findsOneWidget);
  });

  testWidgets('adding a row grows the grid', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A', 'B'],
        series: [
          ChartSeries(name: 'Waarde', data: [10, 20]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Rij'));
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).x.length, 3);
  });

  testWidgets('adding a series grows the columns', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A', 'B'],
        series: [
          ChartSeries(name: 'Waarde', data: [10, 20]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reeks'));
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).series.length, 2);
  });

  testWidgets('removing a series column drops it', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A'],
        series: [
          ChartSeries(name: 'Een', data: [1]),
          ChartSeries(name: 'Twee', data: [2]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.tap(find.byTooltip('Kolom verwijderen').first);
    await tester.pump();

    final spec = ChartSpec.parse(updated.customMarkdown);
    expect(spec.series.length, 1);
    expect(spec.series.single.name, 'Twee');
  });

  testWidgets('removing a row drops it', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A', 'B', 'C'],
        series: [
          ChartSeries(name: 'Waarde', data: [1, 2, 3]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.tap(find.byTooltip('Rij verwijderen').first);
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).x, ['B', 'C']);
  });

  testWidgets('editing a value cell emits the number', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A'],
        series: [
          ChartSeries(name: 'Waarde', data: [0]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.enterText(find.byKey(const ValueKey('v-0-0-0')), '99');
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).series.single.data, [99]);
  });

  testWidgets('editing a series name emits', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A'],
        series: [
          ChartSeries(name: 'Reeks 1', data: [1]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.enterText(find.byKey(const ValueKey('s-0-0')), 'Omzet');
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).series.single.name, 'Omzet');
  });

  testWidgets('editing an x label emits', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A'],
        series: [
          ChartSeries(name: 'Waarde', data: [1]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.enterText(find.byKey(const ValueKey('x-0-0')), 'Q1');
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).x, ['Q1']);
  });

  testWidgets('turning off entry animation emits animateOnEnter false', (
    tester,
  ) async {
    // animateOnEnter defaults to true, so the advanced section starts expanded
    // and the switch is visible.
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A'],
        series: [
          ChartSeries(name: 'Waarde', data: [1]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).animateOnEnter, isFalse);
  });

  testWidgets('picking a series colour applies the chosen hex', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A'],
        series: [
          ChartSeries(name: 'Waarde', data: [1]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.tap(find.byTooltip('Kleur van reeks').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '#1A2B3C',
    );
    await tester.pump();
    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    expect(
      ChartSpec.parse(updated.customMarkdown).series.single.color,
      '#1A2B3C',
    );
  });

  testWidgets('picking a row colour applies the chosen hex', (tester) async {
    var updated = _chartSlide(
      const ChartSpec(
        x: ['A'],
        series: [
          ChartSeries(name: 'Waarde', data: [1]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.tap(find.byKey(const ValueKey('chart-row-color-0')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '#4d5e6f',
    );
    await tester.pump();
    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    expect(ChartSpec.parse(updated.customMarkdown).rowColors.first, '#4D5E6F');
  });

  testWidgets('radar type offers scale bounds with scale labels', (
    tester,
  ) async {
    var updated = _chartSlide(
      const ChartSpec(
        type: ChartType.radar,
        x: ['A', 'B', 'C'],
        series: [
          ChartSeries(name: 'Waarde', data: [1, 2, 3]),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));
    await tester.pump();

    expect(find.text('Schaalminimum (optioneel)'), findsOneWidget);
    expect(find.text('Schaalmaximum (optioneel)'), findsOneWidget);
  });
}
