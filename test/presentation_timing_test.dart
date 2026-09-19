import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/presentation_timing.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/markdown_validator.dart';
import 'package:ocideck/services/timed_presentation_controller.dart';

void main() {
  group('PechaKucha-preset', () {
    const preset = PresentationTimingConfig.pechaKuchaPreset();

    test('legt het volledige 20 × 20-contract vast', () {
      expect(preset.enabled, isTrue);
      expect(preset.isPechaKucha, isTrue);
      expect(preset.autoplay, isTrue);
      expect(preset.slideDuration, const Duration(seconds: 20));
      expect(preset.requiredSlides, 20);
      expect(preset.maxSlides, 20);
      expect(preset.stopAfterLastSlide, isTrue);
      expect(preset.manualAdvance, isFalse);
      expect(
        preset.durationForSlides(20),
        const Duration(minutes: 6, seconds: 40),
      );
    });

    test('validatie levert live bruikbare aantallen en tijden', () {
      final short = preset.validate(17);
      expect(short.isValid, isFalse);
      expect(short.missingSlides, 3);
      expect(short.excessSlides, 0);
      expect(short.currentDuration, const Duration(minutes: 5, seconds: 40));
      expect(short.targetDuration, const Duration(minutes: 6, seconds: 40));

      expect(preset.validate(20).isValid, isTrue);
      expect(preset.validate(21).excessSlides, 1);
    });
  });

  group('Ignite-preset', () {
    const preset = PresentationTimingConfig.ignitePreset();

    test('legt het volledige 20 × 15-contract vast', () {
      expect(preset.enabled, isTrue);
      expect(preset.isIgnite, isTrue);
      expect(preset.isTimedPreset, isTrue);
      expect(preset.autoplay, isTrue);
      expect(preset.slideDuration, const Duration(seconds: 15));
      expect(preset.requiredSlides, 20);
      expect(preset.maxSlides, 20);
      expect(preset.stopAfterLastSlide, isTrue);
      expect(preset.manualAdvance, isFalse);
      expect(preset.durationForSlides(20), const Duration(minutes: 5));
    });

    test('validatie rekent met vijftien seconden per dia', () {
      final short = preset.validate(19);
      expect(short.missingSlides, 1);
      expect(short.currentDuration, const Duration(minutes: 4, seconds: 45));
      expect(short.targetDuration, const Duration(minutes: 5));
      expect(preset.validate(20).isValid, isTrue);
    });
  });

  group('front matter', () {
    final service = MarkdownService();

    test(
      'format pechakucha parseert als strikt preset en round-tript compact',
      () {
        const source = '''
---
title: Demo
format: pechakucha
timing:
  autoplay: false
  slide-duration: 3s
---

# Een
''';
        final deck = service.parseDeck(source)!;
        expect(deck.presentationTiming.isPechaKucha, isTrue);
        expect(
          deck.presentationTiming.slideDuration,
          const Duration(seconds: 20),
        );
        expect(deck.presentationTiming.manualAdvance, isFalse);

        final saved = service.generateDeck(deck);
        expect(saved, contains('format: pechakucha'));
        expect(saved, isNot(contains('timing:')));
        expect(service.generateDeck(service.parseDeck(saved)!), saved);
      },
    );

    test('format ignite parseert als strikt preset en round-tript compact', () {
      const source = '''
---
title: Demo
format: ignite
timing:
  autoplay: false
  slide-duration: 3s
---

# Een
''';
      final deck = service.parseDeck(source)!;
      expect(deck.presentationTiming.isIgnite, isTrue);
      expect(
        deck.presentationTiming.slideDuration,
        const Duration(seconds: 15),
      );
      expect(deck.presentationTiming.manualAdvance, isFalse);

      final saved = service.generateDeck(deck);
      expect(saved, contains('format: ignite'));
      expect(saved, isNot(contains('timing:')));
      expect(service.generateDeck(service.parseDeck(saved)!), saved);
    });

    test('generieke timing parseert en round-tript zonder presetkennis', () {
      const source = '''
---
title: Demo
timing:
  autoplay: true
  slide-duration: 30s
  max-slides: 12
  required-slides: 10
  stop-after-last-slide: true
  manual-advance: false
---

# Een
''';
      final deck = service.parseDeck(source)!;
      final timing = deck.presentationTiming;
      expect(timing.isPechaKucha, isFalse);
      expect(timing.slideDuration, const Duration(seconds: 30));
      expect(timing.maxSlides, 12);
      expect(timing.requiredSlides, 10);
      expect(timing.manualAdvance, isFalse);

      final reparsed = service.parseDeck(service.generateDeck(deck))!;
      expect(reparsed.presentationTiming.slideDuration, timing.slideDuration);
      expect(reparsed.presentationTiming.maxSlides, 12);
      expect(reparsed.presentationTiming.requiredSlides, 10);
    });

    test('een onbekend format blijft bytegetrouw op zijn plek staan', () {
      const source = '''
---
marp: true
format: ignite-plus
# behoud deze regel
theme: ocideck
---

# Een
''';
      final saved = service.generateDeck(service.parseDeck(source)!);
      expect(saved, contains('format: ignite-plus\n# behoud deze regel'));
      expect(saved.split('format: ignite-plus'), hasLength(2));
      expect(service.parseDeck(saved)!.presentationTiming.enabled, isFalse);
    });

    test('de markdowncontrole meldt een onvolledige PechaKucha', () {
      final result = MarkdownValidator().validate('''
---
format: pechakucha
---

# Een
''');
      expect(
        result.issues.map((issue) => issue.message),
        contains(contains('19 ontbreken')),
      );
    });

    test('de markdowncontrole meldt een onvolledige Ignite', () {
      final result = MarkdownValidator().validate('''
---
format: ignite
---

# Een
''');
      expect(
        result.issues.map((issue) => issue.message),
        contains(contains('Ignite vereist 20 slides; 19 ontbreken')),
      );
    });
  });

  group('TimedPresentationController', () {
    late Duration now;
    late TimedPresentationController controller;

    setUp(() {
      now = Duration.zero;
      controller = TimedPresentationController(
        config: const PresentationTimingConfig.pechaKuchaPreset(),
        slideCount: 20,
        monotonicNow: () => now,
      );
    });

    test('leidt de dia rechtstreeks af uit verstreken tijd zonder drift', () {
      controller.start();
      now = const Duration(minutes: 3, milliseconds: 50);
      expect(controller.currentSlideIndex, 9);
      expect(
        controller.remainingInSlide,
        const Duration(seconds: 19, milliseconds: 950),
      );

      now = const Duration(minutes: 6, seconds: 40, milliseconds: 500);
      expect(controller.currentSlideIndex, 19);
      expect(controller.elapsed, const Duration(minutes: 6, seconds: 40));
      expect(controller.isComplete, isTrue);
    });

    test('pauze telt niet mee en hervat met de resterende diatijd', () {
      controller.start();
      now = const Duration(seconds: 7);
      controller.pause();
      now = const Duration(minutes: 1);
      expect(controller.elapsed, const Duration(seconds: 7));
      expect(controller.remainingInSlide, const Duration(seconds: 13));

      controller.resume();
      now = const Duration(minutes: 1, seconds: 13);
      expect(controller.currentSlideIndex, 1);
      expect(controller.elapsed, const Duration(seconds: 20));
    });

    test('reset brengt de starttoestand volledig terug', () {
      controller.start();
      now = const Duration(seconds: 25);
      controller.reset();
      expect(controller.hasStarted, isFalse);
      expect(controller.elapsed, Duration.zero);
      expect(controller.currentSlideIndex, 0);
    });
  });

  test('Deck.copyWith behoudt en kan timing vervangen', () {
    const deck = Deck(
      title: 'Demo',
      presentationTiming: PresentationTimingConfig.pechaKuchaPreset(),
      slides: [Slide(id: '1', type: SlideType.title)],
    );
    expect(deck.copyWith().presentationTiming.isPechaKucha, isTrue);
    expect(
      deck
          .copyWith(presentationTiming: PresentationTimingConfig.disabled)
          .presentationTiming
          .enabled,
      isFalse,
    );
  });
}
