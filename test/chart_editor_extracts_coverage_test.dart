import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/improvement_y01.dart';
import 'package:ocideck/services/improvement/chart_derivation.dart';
import 'package:ocideck/utils/table_clipboard.dart';
import 'package:ocideck/widgets/editors/chart_doe_design_dialog.dart';
import 'package:ocideck/widgets/editors/chart_histogram_limits.dart';
import 'package:ocideck/widgets/editors/chart_type_toolbar.dart';

Widget _nlApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('nl'),
    home: Scaffold(body: child),
  );
}

void main() {
  test('chartGridFromClipboardTable leest koprij of synthetische reeks', () {
    final withHeader = chartGridFromClipboardTable([
      ['', 'A', 'B'],
      ['r1', '1', '2'],
    ])!;
    expect(withHeader.seriesNames, ['A', 'B']);
    expect(withHeader.xLabels, ['r1']);
    expect(withHeader.values, [
      ['1', '2'],
    ]);

    final numeric = chartGridFromClipboardTable([
      ['x', '1'],
      ['y', '2'],
    ])!;
    expect(numeric.seriesNames, ['Reeks 1']);
    expect(numeric.xLabels, ['x', 'y']);
  });

  test('chartTypeHint is null voor staaf, gevuld voor spider', () {
    const l10n = AppLocalizations(Locale('nl'));
    expect(chartTypeHint(l10n, ChartType.bar), isNull);
    expect(chartTypeHint(l10n, ChartType.radar), isNotNull);
    expect(chartTypeHint(l10n, ChartType.pie), contains('cirkel'));
  });

  testWidgets('Y-01-schakelaar en lokale limietvelden bouwen', (tester) async {
    final usl = TextEditingController(text: '12');
    final lsl = TextEditingController(text: '2');
    final target = TextEditingController();
    var useDeck = false;

    await tester.pumpWidget(
      _nlApp(
        Builder(
          builder: (context) {
            final l10n = context.l10n;
            return Column(
              children: [
                ChartHistogramY01Controls(
                  l10n: l10n,
                  useDeckY01: useDeck,
                  deckY01: const ImprovementY01Metric(usl: 10, lsl: 1),
                  usl: usl,
                  lsl: lsl,
                  processTarget: target,
                  onUseDeckY01Changed: (v) => useDeck = v,
                ),
                ChartHistogramLocalLimits(
                  l10n: l10n,
                  usl: usl,
                  lsl: lsl,
                  processTarget: target,
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chart-usl')), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(useDeck, isTrue);

    usl.dispose();
    lsl.dispose();
    target.dispose();
  });

  testWidgets('DOE-dialoog levert een ontwerptabel', (tester) async {
    DoeDesignGrid? result;
    await tester.pumpWidget(
      _nlApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<DoeDesignGrid>(
                context: context,
                builder: (_) => const DoeDesignDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In raster zetten'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.seriesNames, isNotEmpty);
    expect(result!.xLabels, isNotEmpty);
  });

  testWidgets('type-toolbar toont procesverbetering-acties', (tester) async {
    var typed = ChartType.bar;
    var pasted = false;
    await tester.pumpWidget(
      _nlApp(
        Builder(
          builder: (context) {
            final l10n = context.l10n;
            return ChartTypeToolbar(
              l10n: l10n,
              type: typed,
              revealProcesverbetering: true,
              showVariants: true,
              onTypeChanged: (t) => typed = t,
              onGageRr: () {},
              onDoeDesign: () {},
              onCreateVariants: () {},
              onPasteClipboard: () => pasted = true,
              onImportCsv: () {},
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('chart-gage-rr')), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-doe-design')), findsOneWidget);
    await tester.tap(find.text('Plakken uit klembord'));
    await tester.pump();
    expect(pasted, isTrue);
  });
}
