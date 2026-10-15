import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/presentation_cost.dart';
import 'package:ocideck/widgets/presentation/cost_session_start.dart';

/// De startschermen van de kostenmodus (#2436, #2438) vóór de eerste dia.
void main() {
  Future<Future<CostStart?> Function()> pump(
    WidgetTester tester,
    PresentationCostConfig config, {
    bool rehearsalMode = false,
  }) async {
    CostStart? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await runCostStart(
                  context,
                  config,
                  rehearsalMode: rehearsalMode,
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    return () async => result;
  }

  Future<void> tapStart(WidgetTester tester) async {
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
  }

  const group = PresentationCostConfig(
    mode: PresentationCostMode.explicit,
    groupHourlyRateMinor: 7500,
  );

  testWidgets('kostenmodus uit vraagt niets en geeft geen seed', (
    tester,
  ) async {
    final result = await pump(tester, PresentationCostConfig.off);
    await tester.pump();
    await tapStart(tester);
    expect(find.byType(AlertDialog), findsNothing);
    final r = (await result())!;
    expect(r.cancelled, isFalse);
    expect(r.seed, isNull);
  });

  testWidgets('de oefenmodus vraagt niets, ook met kostenmodus aan', (
    tester,
  ) async {
    final result = await pump(
      tester,
      group.copyWith(rateInput: CostRateInput.attendees),
      rehearsalMode: true,
    );
    await tester.pump();
    await tapStart(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect((await result())!.seed, isNull);
  });

  testWidgets(
    'een groepstarief in euro vraagt niets en neemt het tarief over',
    (tester) async {
      final result = await pump(tester, group);
      await tester.pump();
      await tapStart(tester);
      expect(find.byType(AlertDialog), findsNothing);
      final r = (await result())!;
      expect(r.cancelled, isFalse);
      expect(r.seed!.hourlyRateMinor, 7500);
      expect(r.seed!.eurRate, isNull);
      expect(r.seed!.unconvertedAttendees, 0);
    },
  );

  testWidgets('een USD-groepstarief vraagt om een koers en legt hem vast', (
    tester,
  ) async {
    final result = await pump(tester, group.copyWith(currencyCode: 'USD'));
    await tester.pump();
    await tapStart(tester);
    expect(find.text('Omrekening naar euro'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('rate-USD')), '0,92');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rate-confirm')));
    await tester.pumpAndSettle();
    final r = (await result())!;
    expect(r.seed!.hourlyRateMinor, 7500);
    expect(r.seed!.eurRate!.eurMicros, 920000);
    expect(r.seed!.eurRate!.manual, isTrue);
  });

  testWidgets('zonder koers doorgaan geeft een seed zonder koers', (
    tester,
  ) async {
    final result = await pump(tester, group.copyWith(currencyCode: 'USD'));
    await tester.pump();
    await tapStart(tester);
    await tester.tap(find.byKey(const ValueKey('rate-skip')));
    await tester.pumpAndSettle();
    final r = (await result())!;
    expect(r.cancelled, isFalse);
    expect(r.seed!.eurRate, isNull);
  });

  testWidgets('annuleren van het koersscherm start de presentatie niet', (
    tester,
  ) async {
    final result = await pump(tester, group.copyWith(currencyCode: 'USD'));
    await tester.pump();
    await tapStart(tester);
    await tester.tap(find.byKey(const ValueKey('rate-cancel')));
    await tester.pumpAndSettle();
    final r = (await result())!;
    expect(r.cancelled, isTrue);
    expect(r.seed, isNull);
  });

  testWidgets('per aanwezige: annuleren start de presentatie niet', (
    tester,
  ) async {
    final result = await pump(
      tester,
      group.copyWith(rateInput: CostRateInput.attendees),
    );
    await tester.pump();
    await tapStart(tester);
    expect(find.text('Aanwezigen en tarieven'), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    final r = (await result())!;
    expect(r.cancelled, isTrue);
    expect(r.seed, isNull);
  });

  testWidgets('per aanwezige in euro: de som van de tarieven wordt het seed', (
    tester,
  ) async {
    final result = await pump(
      tester,
      group.copyWith(rateInput: CostRateInput.attendees),
    );
    await tester.pump();
    await tapStart(tester);
    // Het scherm opent met één lege regel; vul het bedrag per uur in.
    await tester.enterText(find.byType(TextField).first, '40');
    await tester.pump();
    await tester.tap(find.text('Start presentatie'));
    await tester.pumpAndSettle();
    final r = (await result())!;
    expect(r.cancelled, isFalse);
    expect(r.seed!.hourlyRateMinor, 4000);
    expect(r.seed!.eurRate, isNull);
    // Geen salarisgegevens in het resultaat: alleen het samengetelde tarief.
    expect(r.seed!.unconvertedAttendees, 0);
  });

  // Zodat de toetsenbordhandeling van de dialogen hier niet blijft hangen.
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
}
