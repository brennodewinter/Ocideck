import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/attendee_input.dart';
import 'package:ocideck/models/presentation_cost.dart';
import 'package:ocideck/widgets/dialogs/attendee_rates_dialog.dart';

const _eur = CostCurrency('EUR', '€', 2);
const _usd = CostCurrency('USD', '\$', 2);

AttendeeInput _input(
  int minor,
  CostPeriod period, [
  CostCurrency currency = _eur,
]) => AttendeeInput(amountMinor: minor, period: period, currency: currency);

void main() {
  group('hourlyRateMinorFor', () {
    const a = CostAssumptions(); // 40,0 uur × 52 weken, 0% opslag

    test('per uur is het bedrag zelf, ongeacht de aannames', () {
      expect(hourlyRateMinorFor(_input(7550, CostPeriod.hour), a), 7550);
      expect(
        hourlyRateMinorFor(
          _input(7550, CostPeriod.hour),
          const CostAssumptions(employerMarkupPercent: 40),
        ),
        7550,
      );
    });

    test('jaarloon deelt door uren × weken', () {
      // € 83.200/jaar bij 40×52 = € 40/uur
      expect(hourlyRateMinorFor(_input(8320000, CostPeriod.year), a), 4000);
    });

    test('maandloon deelt door uren × weken / 12', () {
      // € 5.200/maand bij 40×52 = € 30/uur (520000×12 / 2080 = 3000)
      expect(hourlyRateMinorFor(_input(520000, CostPeriod.month), a), 3000);
    });

    test('werkgeverslasten-opslag telt mee bij salaris', () {
      const m = CostAssumptions(employerMarkupPercent: 25);
      // € 40/uur bruto + 25% = € 50
      expect(hourlyRateMinorFor(_input(8320000, CostPeriod.year), m), 5000);
    });

    test('nul werkuren levert null terug, geen deling door nul', () {
      const zero = CostAssumptions(paidHoursPerWeekTenths: 0);
      expect(
        hourlyRateMinorFor(_input(8320000, CostPeriod.year), zero),
        isNull,
      );
    });
  });

  group('sumAttendeeRatesMinor', () {
    const a = CostAssumptions();

    test('telt alleen de sessievaluta; vreemde wachten op #2438', () {
      final sum = sumAttendeeRatesMinor(
        [
          _input(4000, CostPeriod.hour),
          _input(5000, CostPeriod.hour, _usd),
          _input(3000, CostPeriod.hour),
        ],
        a,
        _eur,
      );
      expect(sum, 7000);
    });

    test('lege invoer is nul', () {
      expect(sumAttendeeRatesMinor(const [], a, _eur), 0);
    });
  });

  group('AttendeeRatesDialog', () {
    Future<AttendeeRatesResult?> pump(WidgetTester tester) async {
      AttendeeRatesResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await AttendeeRatesDialog.show(
                    context,
                    sessionCurrency: _eur,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return Future.value(result);
    }

    testWidgets('annuleren geeft null terug — de sessie start dan niet', (
      tester,
    ) async {
      late AttendeeRatesResult? result;
      var resolved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await AttendeeRatesDialog.show(
                    context,
                    sessionCurrency: _eur,
                  );
                  resolved = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attendee-cancel')));
      await tester.pumpAndSettle();
      expect(resolved, isTrue);
      expect(result, isNull);
    });

    testWidgets('start knop is uit bij lege invoer — geen nulprijs-start', (
      tester,
    ) async {
      await pump(tester);
      final start = tester.widget<FilledButton>(
        find.byKey(const ValueKey('attendee-start')),
      );
      expect(start.onPressed, isNull);
    });

    testWidgets('ongeldige invoer blokkeert de start', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('attendee-amount-0')),
        'abc',
      );
      await tester.pump();
      final start = tester.widget<FilledButton>(
        find.byKey(const ValueKey('attendee-start')),
      );
      expect(start.onPressed, isNull);
    });

    testWidgets('geldige uurtarief-invoer kan starten en levert de regels', (
      tester,
    ) async {
      late AttendeeRatesResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await AttendeeRatesDialog.show(
                    context,
                    sessionCurrency: _eur,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('attendee-amount-0')),
        '75',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('attendee-start')));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.attendees, hasLength(1));
      expect(result!.attendees.single.amountMinor, 7500);
      expect(result!.attendees.single.period, CostPeriod.hour);
      expect(result!.assumptions.weeksPerYear, 52);
    });
  });
}
