import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/presentation_cost.dart';
import 'package:ocideck/models/rehearsal.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/presentation_cost_session.dart';

/// Klok die per aanroep een vaste stap zet — deterministisch voor de
/// sessietests zonder stopwatch.
class _StepClock {
  Duration t = Duration.zero;
  Duration step(Duration s) => t += s;
}

void main() {
  const eur = CostCurrency('EUR', '€', 2);
  const jpy = CostCurrency('JPY', '¥', 0);

  group('geld rekent in kleinste eenheden', () {
    test('een uur tegen het tarief is het tarief', () {
      expect(costMinorForElapsed(7500, const Duration(hours: 1)), 7500);
    });

    test('een half uur tegen €75/uur is €37,50', () {
      expect(costMinorForElapsed(7500, const Duration(minutes: 30)), 3750);
    });

    test('breukminuten ronden halve omhoog af', () {
      // €100/uur over één seconde: 10000 × 1/3600 = 2,777… → 3 cent.
      expect(costMinorForElapsed(10000, const Duration(seconds: 1)), 3);
    });

    test('geen tijd of geen tarief is geen kosten', () {
      expect(costMinorForElapsed(0, const Duration(hours: 2)), 0);
      expect(costMinorForElapsed(7500, Duration.zero), 0);
    });

    test('absurde tarieven over lange sessies overlopen niet', () {
      // 1 miljard cent/uur gedurende 100 uur — buiten 64-bit als je
      // rate × microseconden in een int zou doen (3,6e23).
      final cost = costMinorForElapsed(1000000000, const Duration(hours: 100));
      expect(cost, 100000000000);
    });
  });

  group('bedragen lezen en schrijven', () {
    test('formatteert met symbool en het aantal decimalen van de valuta', () {
      expect(formatAmountMinor(1234, eur), '€12,34');
      expect(formatAmountMinor(1234, jpy), '¥1234');
      expect(formatAmountMinor(-500, eur), '-€5,00');
    });

    test('parst komma en punt als decimaalscheiding', () {
      expect(parseAmountMinor('75', eur), 7500);
      expect(parseAmountMinor('75,50', eur), 7550);
      expect(parseAmountMinor('75.50', eur), 7550);
      expect(parseAmountMinor('€ 75,50', eur), 7550);
    });

    test('weigert rotte invoer', () {
      expect(parseAmountMinor('', eur), isNull);
      expect(parseAmountMinor('-50', eur), isNull);
      expect(parseAmountMinor('abc', eur), isNull);
      expect(parseAmountMinor('1,234', eur), isNull); // te veel decimalen
      expect(parseAmountMinor('1,5', jpy), isNull); // JPY kent geen decimalen
    });

    test('rondt het tarief in de front matter af op de valuta', () {
      expect(formatCostRateMajor(7550, eur), '75.50');
      expect(formatCostRateMajor(100, jpy), '100');
    });
  });

  group('de sessieklok', () {
    test('meet monotone tijd en rekent het lopende bedrag uit', () {
      final clock = _StepClock();
      final session = PresentationCostSession(
        currency: eur,
        hourlyRateMinor: 6000,
        now: () => clock.t,
      );
      expect(session.currentCostMinor, 0);
      clock.step(const Duration(minutes: 15));
      expect(session.currentCostMinor, 1500);
    });

    test('reset zet de teller terug maar houdt tarief en valuta', () {
      final clock = _StepClock();
      final session = PresentationCostSession(
        currency: eur,
        hourlyRateMinor: 6000,
        now: () => clock.t,
      );
      clock.step(const Duration(hours: 1));
      session.reset();
      expect(session.elapsed, Duration.zero);
      expect(session.currentCostMinor, 0);
      clock.step(const Duration(minutes: 30));
      expect(session.finish().totalMinor, 3000);
    });

    test('het eindbedrag splitst per dia op basis van de gemeten tijd', () {
      final clock = _StepClock();
      final session = PresentationCostSession(
        currency: eur,
        hourlyRateMinor: 3600,
        now: () => clock.t,
      );
      clock.step(const Duration(minutes: 10));
      final run = session.finish();
      expect(run.totalMinor, 600);
      expect(
        run.forSlide(
          const SlideTiming(
            slideId: 'a',
            index: 0,
            spent: Duration(minutes: 5),
          ),
        ),
        300,
      );
    });
  });

  group('front matter', () {
    test('een deck zonder kostenmodus schrijft en leest niets', () {
      final service = MarkdownService();
      final deck = Deck(title: 'T', slides: [Slide.create(SlideType.title)]);
      final text = service.generateDeck(deck);
      expect(text, isNot(contains('ocideck_cost')));
      final back = service.parseDeck(text)!;
      expect(back.presentationCosts.isEnabled, isFalse);
    });

    test('de volledige config round-tript door de front matter', () {
      final service = MarkdownService();
      final deck = Deck(
        title: 'T',
        slides: [Slide.create(SlideType.title)],
        presentationCosts: const PresentationCostConfig(
          mode: PresentationCostMode.explicit,
          rateInput: CostRateInput.group,
          groupHourlyRateMinor: 7550,
          currencyCode: 'CHF',
        ),
      );
      final text = service.generateDeck(deck);
      expect(text, contains('ocideck_cost_mode: explicit'));
      expect(text, contains('ocideck_cost_input: group'));
      expect(text, contains('ocideck_cost_currency: CHF'));
      expect(text, contains('ocideck_cost_rate: 75.50'));
      final back = service.parseDeck(text)!;
      expect(back.presentationCosts.mode, PresentationCostMode.explicit);
      expect(back.presentationCosts.rateInput, CostRateInput.group);
      expect(back.presentationCosts.groupHourlyRateMinor, 7550);
      expect(back.presentationCosts.currencyCode, 'CHF');
    });

    test('per-aanwezige invoer bewaart geen tarief in het bestand', () {
      final service = MarkdownService();
      final deck = Deck(
        title: 'T',
        slides: [Slide.create(SlideType.title)],
        presentationCosts: const PresentationCostConfig(
          mode: PresentationCostMode.normal,
          rateInput: CostRateInput.attendees,
        ),
      );
      final text = service.generateDeck(deck);
      expect(text, contains('ocideck_cost_input: attendees'));
      expect(text, isNot(contains('ocideck_cost_rate')));
    });

    test('halve of vreemde sleutels vallen terug op veilige waarden', () {
      final service = MarkdownService();
      final back = service.parseDeck(
        '---\nocideck_cost_mode: raar\nocideck_cost_currency: XXX\n'
        'ocideck_cost_rate: -99\n---\n\n# t\n',
      )!;
      expect(back.presentationCosts.mode, PresentationCostMode.off);
      // 'normal' met onbekende valuta en rot tarief: EUR en 0.
      final half = service.parseDeck(
        '---\nocideck_cost_mode: normal\nocideck_cost_currency: XXX\n'
        'ocideck_cost_rate: -99\n---\n\n# t\n',
      )!;
      expect(half.presentationCosts.currencyCode, 'EUR');
      expect(half.presentationCosts.groupHourlyRateMinor, 0);
    });
  });
}
