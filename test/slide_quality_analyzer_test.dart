import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/utils/color_contrast.dart';

void main() {
  const analyzer = SlideQualityAnalyzer();

  group('color_contrast', () {
    test('black on white meets AA for normal text', () {
      expect(meetsWcagAa('#000000', '#FFFFFF'), isTrue);
      expect(hexContrastRatio('#000000', '#FFFFFF'), closeTo(21.0, 0.5));
    });

    test('light gray on white fails AA for normal text', () {
      expect(meetsWcagAa('#CCCCCC', '#FFFFFF'), isFalse);
    });

    test('invalid hex returns null ratio', () {
      expect(hexContrastRatio('not-a-color', '#FFFFFF'), isNull);
    });
  });

  group('SlideQualityAnalyzer', () {
    test('clean deck has no issues', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Kort',
            bullets: ['Eerste punt'],
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(result.hasIssues, isFalse);
    });

    test('detects missing image caption', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.image).copyWith(
            imagePath: 'images/photo.jpg',
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) =>
              i.kind == SlideQualityIssueKind.missingAltCaption &&
              i.field == 'imageCaption',
        ),
        isTrue,
      );
    });

    test('does not warn when image caption is present', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.image).copyWith(
            imagePath: 'images/photo.jpg',
            imageCaption: 'Teamfoto 2024',
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.where((i) => i.category == SlideQualityCategory.altText),
        isEmpty,
      );
    });

    test('detects low theme body contrast as deck-wide issue', () {
      final deck = Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(
          textColor: '#CCCCCC',
          slideBackgroundColor: '#FFFFFF',
        ),
        slides: [Slide.create(SlideType.bullets)],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.isDeckWide && i.kind == SlideQualityIssueKind.themeContrast,
        ),
        isTrue,
      );
    });

    test('detects dense bullet slide text', () {
      final longBullet = 'Lorem ipsum dolor sit amet, ' * 8;
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Overvol',
            bullets: List.generate(14, (_) => longBullet),
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.category == SlideQualityCategory.textDensity,
        ),
        isTrue,
      );
    });

    test('critical text density is reported as error', () {
      final longBullet = 'Woord ' * 60;
      final slide = Slide.create(SlideType.bullets).copyWith(
        title: 'Extreem ' * 20,
        subtitle: 'Ondertitel ' * 20,
        bullets: List.generate(30, (_) => longBullet),
      );
      expect(
        bulletsSlideFitScale(slide: slide, font: 'Arial'),
        lessThanOrEqualTo(kTextDensityCriticalScale + 0.001),
      );

      final result = analyzer.analyzeSlides(
        slides: [slide],
        theme: const ThemeProfile(),
        font: 'Arial',
      );
      expect(
        result.issues.any(
          (i) =>
              i.kind == SlideQualityIssueKind.textDensityCritical &&
              i.severity == MarkdownValidationSeverity.error,
        ),
        isTrue,
      );
    });

    test('detects chart without title or descriptive data', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.chart).copyWith(
            customMarkdown: const ChartSpec().toBlock(),
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.chartMissingDescription,
        ),
        isTrue,
      );
    });

    test('accepts chart with title', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.chart).copyWith(
            customMarkdown: const ChartSpec(title: 'Omzet').toBlock(),
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.where((i) => i.category == SlideQualityCategory.altText),
        isEmpty,
      );
    });

    test('detects video without descriptive text', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.video).copyWith(
            videoPath: 'media/demo.mp4',
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.mediaMissingDescription,
        ),
        isTrue,
      );
    });

    test('warns about contrast on title slide with background image', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.title).copyWith(
            title: 'Welkom',
            imagePath: 'images/bg.jpg',
            imageCaption: 'Achtergrond',
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.imageContrastUnverified,
        ),
        isTrue,
      );
    });

    test('skips skipped slides', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.image).copyWith(
            imagePath: 'images/hidden.jpg',
            skipped: true,
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(result.hasIssues, isFalse);
    });

    test('forSlide returns only matching slide issues', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets),
          Slide.create(SlideType.image).copyWith(
            imagePath: 'images/photo.jpg',
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(result.forSlide(0), isEmpty);
      expect(result.forSlide(1), isNotEmpty);
    });
  });
}
