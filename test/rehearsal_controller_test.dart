import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/rehearsal_controller.dart';

void main() {
  // Bestuurbare klok zodat de timing deterministisch is.
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime(2026, 1, 1, 10, 0, 0));
  void advance(Duration d) => now = now.add(d);

  test('elapsed loopt met de klok mee', () {
    final c = RehearsalController(now: clock);
    expect(c.elapsed, Duration.zero);
    advance(const Duration(seconds: 90));
    expect(c.elapsed, const Duration(seconds: 90));
  });

  test('per-slide-tijd telt op per slide en houdt volgorde aan', () {
    final c = RehearsalController(now: clock);
    c.observe('a', 0);
    advance(const Duration(seconds: 30));
    c.observe('b', 1);
    advance(const Duration(seconds: 20));
    c.observe('a', 0); // terug naar a
    advance(const Duration(seconds: 10));

    final run = c.finish();
    expect(run.total, const Duration(seconds: 60));
    expect(run.perSlide.map((t) => t.slideId).toList(), ['a', 'b']);
    expect(run.perSlide[0].spent, const Duration(seconds: 40)); // 30 + 10
    expect(run.perSlide[1].spent, const Duration(seconds: 20));
  });

  test('observe is idempotent: dezelfde slide sluit niet af', () {
    final c = RehearsalController(now: clock);
    c.observe('a', 0);
    advance(const Duration(seconds: 5));
    c.observe('a', 0); // geen wissel
    advance(const Duration(seconds: 5));
    expect(c.currentSlideElapsed, const Duration(seconds: 10));
  });

  test('aftelling: resterend wordt negatief na de doeltijd', () {
    final c = RehearsalController(
      now: clock,
      target: const Duration(minutes: 1),
    );
    advance(const Duration(seconds: 40));
    expect(c.remaining, const Duration(seconds: 20));
    advance(const Duration(seconds: 30));
    expect(c.remaining, const Duration(seconds: -10));
  });

  test(
    'geen doeltijd → geen resterende tijd; nul-target zet aftelling uit',
    () {
      final c = RehearsalController(now: clock);
      expect(c.remaining, isNull);
      c.target = Duration.zero;
      expect(c.target, isNull);
      c.target = const Duration(minutes: 5);
      expect(c.target, const Duration(minutes: 5));
    },
  );

  test('reset wist run en per-slide-tijden, behoudt doeltijd', () {
    final c = RehearsalController(
      now: clock,
      target: const Duration(minutes: 1),
    );
    c.observe('a', 0);
    advance(const Duration(seconds: 30));
    c.reset();
    expect(c.elapsed, Duration.zero);
    expect(c.target, const Duration(minutes: 1));
    // Na reset is er nog geen geregistreerde slide.
    advance(const Duration(seconds: 5));
    expect(c.finish().perSlide, isEmpty);
  });

  test('hasMeaningfulData vereist een slide én ≥10s', () {
    final c = RehearsalController(now: clock);
    expect(c.hasMeaningfulData, isFalse);
    c.observe('a', 0);
    advance(const Duration(seconds: 9));
    expect(c.hasMeaningfulData, isFalse);
    advance(const Duration(seconds: 1));
    expect(c.hasMeaningfulData, isTrue);
  });

  group('vraagpogingen', () {
    test('elke beantwoorde poging komt apart in de run', () {
      final c = RehearsalController(now: clock);
      c.observe('q', 3);

      c.startQuestion('q', 3);
      advance(const Duration(seconds: 12));
      c.finishQuestion(correct: false);

      c.startQuestion('q', 3);
      advance(const Duration(seconds: 4));
      c.finishQuestion(correct: true);

      final attempts = c.finish().questionAttempts;
      expect(attempts.length, 2);
      expect(attempts[0].spent, const Duration(seconds: 12));
      expect(attempts[0].correct, isFalse);
      expect(attempts[1].spent, const Duration(seconds: 4));
      expect(attempts[1].correct, isTrue);
      expect(attempts.every((a) => a.slideId == 'q' && a.index == 3), isTrue);
    });

    test('een vraag die je verlaat zonder te antwoorden telt niet mee', () {
      final c = RehearsalController(now: clock);
      c.startQuestion('q', 0);
      advance(const Duration(seconds: 30));
      // Geen finishQuestion: doorgebladerd zonder antwoord.
      expect(c.finish().questionAttempts, isEmpty);
    });

    test('een tweede oordeel over dezelfde poging telt niet dubbel', () {
      final c = RehearsalController(now: clock);
      c.startQuestion('q', 0);
      advance(const Duration(seconds: 5));
      c.finishQuestion(correct: false);
      c.finishQuestion(correct: false);
      expect(c.finish().questionAttempts.length, 1);
    });

    test('reset wist ook de vraagpogingen', () {
      final c = RehearsalController(now: clock);
      c.startQuestion('q', 0);
      advance(const Duration(seconds: 5));
      c.finishQuestion(correct: true);
      c.reset();
      expect(c.finish().questionAttempts, isEmpty);
    });
  });

  test('delta beschrijft over/onder de doeltijd', () {
    final c = RehearsalController(
      now: clock,
      target: const Duration(minutes: 1),
    );
    c.observe('a', 0);
    advance(const Duration(seconds: 70));
    final run = c.finish();
    expect(run.delta, const Duration(seconds: 10)); // over de tijd
  });
}
