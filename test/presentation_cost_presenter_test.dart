import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/exchange_rate.dart';
import 'package:ocideck/models/presentation_cost.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/presentation_cost_session.dart';
import 'package:ocideck/widgets/presentation/cost_overlay.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De presentator met de kostenmodus aan (#2437): waar het bedrag wel en niet
/// verschijnt, en dat het eindoverzicht niet aan de oefenschakelaar hangt.
Widget _host({
  required PresentationCostConfig cost,
  CostSessionSeed? seed,
  bool showRehearsalSummary = true,
}) {
  final slides = [
    Slide.create(SlideType.bullets).copyWith(title: 'Eerste'),
    Slide.create(SlideType.bullets).copyWith(title: 'Tweede'),
  ];
  return MaterialApp(
    localizationsDelegates: const [
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: FullscreenPresenter(
      slides: slides,
      projectPath: null,
      initialIndex: 0,
      themeProfile: const ThemeProfile(),
      costConfig: cost,
      costSeed: seed,
      showRehearsalSummary: showRehearsalSummary,
    ),
  );
}

const _explicit = PresentationCostConfig(
  mode: PresentationCostMode.explicit,
  groupHourlyRateMinor: 6000,
);
const _normal = PresentationCostConfig(
  mode: PresentationCostMode.normal,
  groupHourlyRateMinor: 6000,
);

Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  group('lopend bedrag', () {
    testWidgets('expliciete modus toont het bedrag, beginnend bij nul', (
      tester,
    ) async {
      await _pump(tester, _host(cost: _explicit));
      expect(find.byType(CostOverlay), findsOneWidget);
      expect(find.text('€0,00'), findsOneWidget);
    });

    testWidgets('de overlay is sessie-bekleding, geen dia-inhoud', (
      tester,
    ) async {
      await _pump(tester, _host(cost: _explicit));
      expect(
        find.descendant(
          of: find.byType(SlidePreviewWidget),
          matching: find.byType(CostOverlay),
        ),
        findsNothing,
        reason: 'binnen de dia zou hij in een render of export meekomen',
      );
    });

    for (final (name, cost) in [
      ('gewone modus', _normal),
      ('modus uit', PresentationCostConfig.off),
    ]) {
      testWidgets('$name toont tijdens de presentatie geen bedrag', (
        tester,
      ) async {
        await _pump(tester, _host(cost: cost));
        expect(find.byType(CostOverlay), findsNothing);
        expect(find.textContaining('€'), findsNothing);
      });
    }

    testWidgets('een USD-sessie met koers toont het EUR-equivalent erbij', (
      tester,
    ) async {
      await _pump(
        tester,
        _host(
          cost: _explicit.copyWith(currencyCode: 'USD'),
          seed: const CostSessionSeed(
            eurRate: ExchangeRate(
              code: 'USD',
              eurMicros: 920000,
              source: 'Frankfurter (ECB)',
              date: '2026-10-15',
              manual: false,
            ),
          ),
        ),
      );
      expect(find.text('\$0,00 ≈ €0,00'), findsOneWidget);
    });

    testWidgets('een USD-sessie zonder koers verzint geen EUR-bedrag', (
      tester,
    ) async {
      await _pump(tester, _host(cost: _explicit.copyWith(currencyCode: 'USD')));
      expect(find.byType(CostOverlay), findsOneWidget);
      expect(find.textContaining('≈'), findsNothing);
      expect(find.textContaining('€'), findsNothing);
    });
  });

  group('eindoverzicht', () {
    testWidgets('verschijnt in de gewone modus ook zonder oefenschakelaar', (
      tester,
    ) async {
      await _pump(tester, _host(cost: _normal, showRehearsalSummary: false));
      await _escape(tester);
      expect(find.text('Kostenindicatie'), findsWidgets);
      expect(find.textContaining('€60,00'), findsOneWidget); // de basis
    });

    testWidgets('verschijnt ook in de expliciete modus', (tester) async {
      await _pump(tester, _host(cost: _explicit, showRehearsalSummary: false));
      await _escape(tester);
      expect(find.text('Kostenindicatie'), findsWidgets);
    });

    testWidgets('ontbreekt als de modus uit staat en de schakelaar ook', (
      tester,
    ) async {
      await _pump(
        tester,
        _host(cost: PresentationCostConfig.off, showRehearsalSummary: false),
      );
      await _escape(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('€'), findsNothing);
    });

    testWidgets('met modus uit blijft het gewone oefenoverzicht kostenloos', (
      tester,
    ) async {
      await _pump(tester, _host(cost: PresentationCostConfig.off));
      await _escape(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Kostenindicatie'), findsNothing);
    });
  });
}
