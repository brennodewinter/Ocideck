import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/exchange_rate.dart';
import 'package:ocideck/models/presentation_cost.dart';
import 'package:ocideck/models/rehearsal.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/presentation_cost_session.dart';
import 'package:ocideck/widgets/presentation/cost_overlay.dart';
import 'package:ocideck/widgets/presentation/rehearsal_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _eur = CostCurrency('EUR', '€', 2);

RehearsalRun _run(List<SlideTiming> perSlide) => RehearsalRun(
  total: perSlide.fold(Duration.zero, (acc, t) => acc + t.spent),
  target: null,
  perSlide: perSlide,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CostOverlay', () {
    testWidgets('toont het geformatteerde sessiebedrag met semantisch label', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CostOverlay(minor: 1234, currency: _eur, slideWidth: 1280),
          ),
        ),
      );
      expect(find.text('€12,34'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Kostenindicatie: €12,34',
          ),
        ),
        isNotNull,
      );
    });
  });

  group('eindoverzicht met kosten', () {
    final slide = Slide.create(SlideType.title);
    final timing = [
      SlideTiming(slideId: 'x', index: 0, spent: const Duration(minutes: 2)),
    ];

    Future<void> pumpSummary(WidgetTester tester, {CostRun? costRun}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRehearsalSummary(
                  context,
                  run: _run(timing),
                  slides: [slide],
                  costRun: costRun,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('toont totaalbedrag, basis en per-dia-kosten', (tester) async {
      // € 60/uur, 2 minuten op de enige dia → € 2,00 totaal én per dia.
      final cost = CostRun(
        hourlyRateMinor: 6000,
        currency: _eur,
        elapsed: const Duration(minutes: 2),
      );
      await pumpSummary(tester, costRun: cost);
      expect(find.text('Kostenindicatie'), findsOneWidget);
      expect(find.text('€2,00'), findsNWidgets(2)); // totaal + dia
      expect(find.textContaining('€60,00'), findsOneWidget); // de basis
      expect(
        find.textContaining('geen boekhoudkundige kostprijs'),
        findsOneWidget,
      );
    });

    testWidgets('zonder kostensessie staat er geen bedrag', (tester) async {
      await pumpSummary(tester);
      expect(find.text('Kostenindicatie'), findsNothing);
      expect(find.textContaining('€'), findsNothing);
    });

    const usd = CostCurrency('USD', '\$', 2);
    ExchangeRate usdRate({
      String date = '2026-10-15',
      bool manual = false,
      String source = 'Frankfurter (ECB)',
    }) => ExchangeRate(
      code: 'USD',
      eurMicros: 920000,
      source: source,
      date: date,
      manual: manual,
    );

    testWidgets('een USD-sessie toont per dia en totaal het EUR-equivalent', (
      tester,
    ) async {
      // $ 100/uur, 6 minuten → $ 10,00 = € 9,20 bij 0,92.
      final cost = CostRun(
        hourlyRateMinor: 10000,
        currency: usd,
        elapsed: const Duration(minutes: 6),
        eurRate: usdRate(),
      );
      await pumpSummary(tester, costRun: cost);
      expect(find.textContaining('≈ €'), findsWidgets);
      expect(find.textContaining('\$10,00 ≈ €9,20'), findsWidgets);
    });

    testWidgets('de koersbron en peildatum staan bij de berekeningsbasis', (
      tester,
    ) async {
      final cost = CostRun(
        hourlyRateMinor: 10000,
        currency: usd,
        elapsed: const Duration(minutes: 6),
        eurRate: usdRate(),
      );
      await pumpSummary(tester, costRun: cost);
      expect(
        find.textContaining('koers: Frankfurter (ECB), peildatum 2026-10-15'),
        findsOneWidget,
      );
    });

    testWidgets('een handmatige koers heet handmatig, niet naar een dienst', (
      tester,
    ) async {
      final cost = CostRun(
        hourlyRateMinor: 10000,
        currency: usd,
        elapsed: const Duration(minutes: 6),
        eurRate: usdRate(source: '', manual: true),
      );
      await pumpSummary(tester, costRun: cost);
      expect(
        find.textContaining('koers: handmatig, peildatum 2026-10-15'),
        findsOneWidget,
      );
      expect(find.textContaining('Frankfurter'), findsNothing);
    });

    testWidgets('een verouderde koers wordt als zodanig benoemd', (
      tester,
    ) async {
      final cost = CostRun(
        hourlyRateMinor: 10000,
        currency: usd,
        elapsed: const Duration(minutes: 6),
        eurRate: usdRate(date: '2020-01-01'),
      );
      await pumpSummary(tester, costRun: cost);
      expect(find.textContaining('verouderd'), findsOneWidget);
    });

    testWidgets(
      'zonder koers: "koers ontbreekt" en geen verzonnen EUR-bedrag',
      (tester) async {
        final cost = CostRun(
          hourlyRateMinor: 10000,
          currency: usd,
          elapsed: const Duration(minutes: 6),
        );
        await pumpSummary(tester, costRun: cost);
        expect(find.textContaining('koers ontbreekt'), findsOneWidget);
        expect(find.textContaining('≈'), findsNothing);
        expect(find.textContaining('€'), findsNothing);
      },
    );

    testWidgets('niet-omgerekende invoerregels worden benoemd', (tester) async {
      final cost = CostRun(
        hourlyRateMinor: 4000,
        currency: _eur,
        elapsed: const Duration(minutes: 2),
        unconvertedAttendees: 2,
      );
      await pumpSummary(tester, costRun: cost);
      expect(
        find.textContaining('2 invoerregel(s) niet omgerekend'),
        findsOneWidget,
      );
    });

    testWidgets(
      'het klembord noemt ook het EUR-equivalent en de ontbrekende koers',
      (tester) async {
        String? clipboard;
        Future<String?> copy(CostRun cost) async {
          await pumpSummary(tester, costRun: cost);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard = call.arguments['text'] as String?;
              }
              return null;
            },
          );
          await tester.tap(find.text('Kopieer'));
          await tester.pumpAndSettle();
          return clipboard;
        }

        final withRate = await copy(
          CostRun(
            hourlyRateMinor: 10000,
            currency: usd,
            elapsed: const Duration(minutes: 6),
            eurRate: usdRate(),
          ),
        );
        expect(withRate, contains('\$10,00 ≈ €9,20'));

        // Sluit het overzicht en open het opnieuw zonder koers.
        await tester.tap(find.text('Sluiten'));
        await tester.pumpAndSettle();
        clipboard = null;
        final without = await copy(
          CostRun(
            hourlyRateMinor: 10000,
            currency: usd,
            elapsed: const Duration(minutes: 6),
          ),
        );
        expect(without, contains('Koers ontbreekt'));
        expect(without, isNot(contains('≈')));
      },
    );

    testWidgets('het klembord krijgt de kostenregel mee', (tester) async {
      final cost = CostRun(
        hourlyRateMinor: 6000,
        currency: _eur,
        elapsed: const Duration(minutes: 2),
      );
      await pumpSummary(tester, costRun: cost);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = call.arguments['text'] as String?;
          }
          return null;
        },
      );
      await tester.tap(find.text('Kopieer'));
      await tester.pumpAndSettle();
      expect(clipboard, isNotNull);
      expect(clipboard, contains('Kostenindicatie'));
      expect(clipboard, contains('€2,00'));
      expect(clipboard, contains('€60,00'));
    });
  });
}
