import 'dart:io';

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
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Kort', bullets: ['Eerste punt']),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(result.hasIssues, isFalse);
    });

    test('does not report missing image captions as quality issues', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.image).copyWith(imagePath: 'images/photo.jpg'),
          Slide.create(SlideType.twoImages).copyWith(
            imagePath: 'images/left.jpg',
            imagePath2: 'images/right.jpg',
          ),
          Slide.create(
            SlideType.bulletsImage,
          ).copyWith(bullets: ['Eerste punt'], imagePath: 'images/photo.jpg'),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.where(
          (i) => i.kind == SlideQualityIssueKind.missingAltCaption,
        ),
        isEmpty,
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

    test('detects many short bullets before text has to shrink', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Planning',
            bullets: List.generate(10, (i) => 'Punt ${i + 1}'),
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) =>
              i.kind == SlideQualityIssueKind.bulletCountHigh &&
              i.severity == MarkdownValidationSeverity.warning,
        ),
        isTrue,
      );
    });

    test('detects many rich-text markdown bullets', () {
      final markdown = List.generate(
        13,
        (i) =>
            '- Bullet ${i + 1} met toelichting die visueel over meerdere regels kan lopen',
      ).join('\n');
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Rich text',
            listStyle: ListStyle.richText,
            customMarkdown: markdown,
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.bulletCountHigh,
        ),
        isTrue,
      );
    });

    test('detects many free-markdown bullet items', () {
      final markdown = List.generate(
        13,
        (i) => '- Vrije markdown bullet ${i + 1}',
      ).join('\n');
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(title: 'Markdown', customMarkdown: markdown),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.bulletCountHigh,
        ),
        isTrue,
      );
    });

    test('detects many bullets on split bullets-image slides', () {
      final slide = Slide.create(SlideType.bulletsImage).copyWith(
        title: 'blah blah blah',
        imagePath: 'images/pasted.png',
        bullets: List.generate(
          13,
          (i) =>
              'Controleer op een SPECI: Kijk of er tussentijds een speciaal '
              'weerrapport is uitgegeven vanwege plotseling veranderde '
              'omstandigheden ${i + 1}.',
        ),
      );
      final deck = Deck(title: 'Demo', slides: [slide]);

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) =>
              i.kind == SlideQualityIssueKind.bulletCountHigh &&
              i.severity == MarkdownValidationSeverity.warning,
        ),
        isTrue,
      );
    });

    test('detects unicode and HTML bullet items in markdown', () {
      final unicodeMarkdown = List.generate(
        13,
        (i) => '• Unicode bullet ${i + 1}',
      ).join('\n');
      final htmlMarkdown = [
        '<ul>',
        for (var i = 1; i <= 13; i++) '<li>HTML bullet $i</li>',
        '</ul>',
      ].join('\n');
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(title: 'Unicode', customMarkdown: unicodeMarkdown),
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(title: 'HTML', customMarkdown: htmlMarkdown),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result
            .forSlide(0)
            .any((i) => i.kind == SlideQualityIssueKind.bulletCountHigh),
        isTrue,
      );
      expect(
        result
            .forSlide(1)
            .any((i) => i.kind == SlideQualityIssueKind.bulletCountHigh),
        isTrue,
      );
    });

    test('reports extreme bullet counts as error', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Alles op een slide',
            bullets: List.generate(16, (i) => 'Kort punt ${i + 1}'),
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) =>
              i.kind == SlideQualityIssueKind.bulletCountCritical &&
              i.severity == MarkdownValidationSeverity.error,
        ),
        isTrue,
      );
    });

    test('detects long bullet prose even when bullet count is modest', () {
      final proseBullet =
          'Deze bullet beschrijft meerdere details die beter in de toelichting '
          'of op een aparte slide passen';
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Context',
            bullets: List.generate(6, (_) => proseBullet),
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.bulletWordCountHigh,
        ),
        isTrue,
      );
      expect(
        result.issues.any(
          (i) =>
              i.kind == SlideQualityIssueKind.bulletAverageLengthHigh &&
              i.severity == MarkdownValidationSeverity.informational,
        ),
        isTrue,
      );
    });

    test('reports very long average bullet length as warning', () {
      const longBullet =
          'een twee drie vier vijf zes zeven acht negen tien elf twaalf '
          'dertien veertien vijftien zestien zeventien achttien negentien '
          'twintig eenentwintig tweeentwintig drieentwintig vierentwintig '
          'vijfentwintig';
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Uitgeschreven bullets',
            bullets: List.generate(3, (_) => longBullet),
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) =>
              i.kind == SlideQualityIssueKind.bulletAverageLengthHigh &&
              i.severity == MarkdownValidationSeverity.warning,
        ),
        isTrue,
      );
    });

    test('detects multi-sentence bullets and deep nesting', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Details',
            bullets: [
              'Eerste observatie. Tweede zin met extra context.',
              'Kort punt',
              '\t\tDiep genest punt',
              'Afronding',
            ],
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.bulletMultiSentence,
        ),
        isTrue,
      );
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.bulletNestingDeep,
        ),
        isTrue,
      );
    });

    test('detects strongly imbalanced two-column bullets', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.twoBullets).copyWith(
            title: 'Vergelijking',
            bullets: List.generate(8, (i) => 'Links ${i + 1}'),
            bullets2: ['Rechts 1', 'Rechts 2'],
          ),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.bulletColumnImbalance,
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
          Slide.create(
            SlideType.chart,
          ).copyWith(customMarkdown: const ChartSpec().toBlock()),
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
          Slide.create(
            SlideType.chart,
          ).copyWith(customMarkdown: const ChartSpec(title: 'Omzet').toBlock()),
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
          Slide.create(SlideType.video).copyWith(videoPath: 'media/demo.mp4'),
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

    test('does not warn about unverified image contrast on title slide', () {
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
        isFalse,
      );
    });

    test('skips skipped slides', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: 'images/hidden.jpg', skipped: true),
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
          Slide.create(SlideType.video).copyWith(videoPath: 'video/demo.mp4'),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(result.forSlide(0), isEmpty);
      expect(result.forSlide(1), isNotEmpty);
    });

    test('detects long quote text density', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.quote,
          ).copyWith(quote: 'Lang citaat. ' * 30, quoteAuthor: 'Auteur'),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.quoteDensityHigh,
        ),
        isTrue,
      );
    });

    test('detects low footer contrast when footer is enabled', () {
      final deck = Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(
          textColor: '#CCCCCC',
          slideBackgroundColor: '#FFFFFF',
          footerText: 'Pagina {page}',
        ),
        slides: [Slide.create(SlideType.bullets)],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.footerContrast,
        ),
        isTrue,
      );
    });

    test('detects missing image file on disk', () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
      addTearDown(() => dir.delete(recursive: true));

      final deck = Deck(
        title: 'Demo',
        projectPath: dir.path,
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: 'images/missing.jpg'),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.missingMediaFile,
        ),
        isTrue,
      );
    });

    test('detects low checklist contrast as deck-wide issue', () {
      final deck = Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(
          checklistUncheckedColor: '#EEEEEE',
          slideBackgroundColor: '#FFFFFF',
        ),
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(listStyle: ListStyle.checklist, bullets: ['☐ Taak']),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) =>
              i.isDeckWide && i.kind == SlideQualityIssueKind.checklistContrast,
        ),
        isTrue,
      );
    });

    test('detects low accent contrast as deck-wide issue', () {
      final deck = Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(
          accentColor: '#DDDDDD',
          slideBackgroundColor: '#FFFFFF',
        ),
        slides: [Slide.create(SlideType.bullets)],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) =>
              i.isDeckWide &&
              i.kind == SlideQualityIssueKind.themeContrast &&
              i.field == 'accentColor',
        ),
        isTrue,
      );
    });
  });
}
