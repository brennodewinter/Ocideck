import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/question.dart';
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

  group('configurable contrast threshold', () {
    // #808080 on white is ~3.9:1 — below WCAG AA (4.5) but above 3.0, exactly
    // the band a user might accept by relaxing the threshold.
    const theme = ThemeProfile(
      textColor: '#808080',
      slideBackgroundColor: '#FFFFFF',
    );

    bool flagsBodyText(double minRatio) =>
        SlideQualityAnalyzer(minContrastRatio: minRatio)
            .analyzeSlides(
              slides: const [],
              theme: theme,
              font: theme.fontFamily,
            )
            .issues
            .any(
              (i) =>
                  i.category == SlideQualityCategory.contrast &&
                  i.field == 'textColor',
            );

    test('sanity: the pair is in the relaxable band', () {
      final ratio = hexContrastRatio('#808080', '#FFFFFF')!;
      expect(ratio, inInclusiveRange(3.0, 4.5));
    });

    test('default WCAG AA (4.5) flags the borderline body text', () {
      expect(flagsBodyText(4.5), isTrue);
    });

    test('a relaxed threshold (3.0) accepts it', () {
      expect(flagsBodyText(3.0), isFalse);
    });

    test('the analyzer defaults to WCAG AA', () {
      expect(const SlideQualityAnalyzer().minContrastRatio, kWcagAaNormalText);
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

    test('treats theme code text as large text (3:1 threshold)', () {
      // Het LibreKAT-huisstijlgroen (#2E7D64) op de donkere codeachtergrond
      // (#111827) haalt ~3.6:1 — voldoende voor grote tekst, en code op een
      // slide staat op displayformaat. Dus dit mag geen contrastwaarschuwing
      // opleveren.
      final deck = Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(
          codeTextColor: '#2E7D64',
          codeBackgroundColor: '#111827',
        ),
        slides: [Slide.create(SlideType.code)],
      );

      expect(
        analyzer
            .analyze(deck)
            .issues
            .where(
              (i) =>
                  i.kind == SlideQualityIssueKind.themeContrast &&
                  i.field == 'codeTextColor',
            ),
        isEmpty,
      );
    });

    test('still flags theme code below the large-text threshold', () {
      // Onder 3.0:1 blijft ook grote tekst onleesbaar: dit moet gemeld worden.
      final deck = Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(
          codeTextColor: '#4A4A4A',
          codeBackgroundColor: '#111827',
        ),
        slides: [Slide.create(SlideType.code)],
      );

      expect(
        analyzer
            .analyze(deck)
            .issues
            .any(
              (i) =>
                  i.kind == SlideQualityIssueKind.themeContrast &&
                  i.field == 'codeTextColor',
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

    test('allows up to 12 checklist items before warning', () {
      Deck deckWith(int count) => Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Checklist',
            listStyle: ListStyle.checklist,
            bullets: List.generate(count, (i) => '[ ] Taak ${i + 1}'),
          ),
        ],
      );

      bool hasBulletCountWarning(Deck deck) => analyzer
          .analyze(deck)
          .issues
          .any((i) => i.kind == SlideQualityIssueKind.bulletCountHigh);

      // 12 mag (zakelijke takenlijst); een tiende gewone bulletslide zou hier
      // al waarschuwen, maar een checklist heeft de ruimere drempel.
      expect(hasBulletCountWarning(deckWith(12)), isFalse);
      expect(hasBulletCountWarning(deckWith(13)), isTrue);
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

    // Een videoslide zonder titel is een legitieme keuze, en de video-editor
    // heeft geen bijschrift-/alt-tekstveld om de tip mee te stillen. Alleen
    // afbeeldingen en charts krijgen de beschrijvingsnudge nog.
    test('does not nudge a video without descriptive text', () {
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
        isFalse,
      );
    });

    test('still nudges a bare image without description', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.image).copyWith(imagePath: 'media/foto.jpg'),
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
      // Dia 0 draagt een titel, en dat is sinds #583 het verschil: een dia
      // zonder énige inhoud meldt zichzelf nu, en dan toetst deze test niet
      // meer of `forSlide` op index filtert maar of de lege-dia-regel bestaat.
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(title: 'Kop'),
          Slide.create(SlideType.image).copyWith(imagePath: 'media/foto.jpg'),
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
          ).copyWith(quote: 'Lang citaat. ' * 70, quoteAuthor: 'Auteur'),
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

    test('allows a quote up to 750 characters without a density warning', () {
      // 'Lang citaat. ' is 13 tekens; * 40 = 520 + auteur blijft onder 750.
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.quote,
          ).copyWith(quote: 'Lang citaat. ' * 40, quoteAuthor: 'Auteur'),
        ],
      );

      final result = analyzer.analyze(deck);
      expect(
        result.issues.any(
          (i) => i.kind == SlideQualityIssueKind.quoteDensityHigh,
        ),
        isFalse,
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

    // Bij een beeldparen-vraag is de afbeelding het antwoord zelf. Ontbreekt
    // ze, dan staat er in de zaal een lege tegel waar een antwoord hoort.
    test('detects a missing answer image on an image-pair question', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.question).copyWith(
            customMarkdown: const QuestionSpec(
              kind: QuestionKind.imagePair,
              prompt: 'Welke is echt?',
              answers: [
                QuestionAnswer(
                  image: '/elders/bestaat-niet.png',
                  correct: true,
                ),
                QuestionAnswer(image: '/elders/ook-niet.png'),
              ],
            ).toBlock(),
          ),
        ],
      );

      expect(
        analyzer
            .analyze(deck)
            .issues
            .where((i) => i.kind == SlideQualityIssueKind.missingMediaFile)
            .length,
        2,
      );
    });

    // Juist een deck dat nog niet is opgeslagen heeft de grootste kans op een
    // kapotte verwijzing — daar hangt de slide nog aan een pad elders op de
    // schijf. Tot voor kort zweeg de controle precies daar.
    test('detects a missing file in a deck that has no project path', () {
      final deck = Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: '/elders/bestaat-niet.png'),
        ],
      );

      expect(
        analyzer
            .analyze(deck)
            .issues
            .any((i) => i.kind == SlideQualityIssueKind.missingMediaFile),
        isTrue,
      );
    });

    test(
      'stays quiet about a file that does exist without a project',
      () async {
        final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/foto.png')..writeAsStringSync('x');

        final deck = Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.image).copyWith(imagePath: file.path),
          ],
        );

        expect(
          analyzer
              .analyze(deck)
              .issues
              .any((i) => i.kind == SlideQualityIssueKind.missingMediaFile),
          isFalse,
        );
      },
    );

    test('flags an image that lies outside the presentation folder', () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
      addTearDown(() => dir.delete(recursive: true));

      final deck = Deck(
        title: 'Demo',
        projectPath: dir.path,
        slides: [
          Slide.create(SlideType.image).copyWith(imagePath: '/elders/foto.png'),
        ],
      );

      final issues = analyzer.analyze(deck).issues;
      expect(
        issues.any((i) => i.kind == SlideQualityIssueKind.externalMediaFile),
        isTrue,
      );
      // Niet ook nog als "niet gevonden" melden: dat is dezelfde afbeelding,
      // en het externe pad is de bruikbare boodschap.
      expect(
        issues.any((i) => i.kind == SlideQualityIssueKind.missingMediaFile),
        isFalse,
      );
    });

    test('stays quiet about an image inside the presentation folder', () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
      addTearDown(() => dir.delete(recursive: true));
      Directory('${dir.path}/images').createSync();
      File('${dir.path}/images/foto.png').writeAsStringSync('x');

      final deck = Deck(
        title: 'Demo',
        projectPath: dir.path,
        slides: [
          Slide.create(SlideType.image).copyWith(imagePath: 'images/foto.png'),
        ],
      );

      expect(
        analyzer
            .analyze(deck)
            .issues
            .any((i) => i.kind == SlideQualityIssueKind.externalMediaFile),
        isFalse,
      );
    });

    // Een online bron is geen ontbrekend bestand: zonder URL-poort plakt de
    // resolver de URL achter de projectmap en meldt hem als "niet gevonden".
    test('does not report an online media URL as a missing file', () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
      addTearDown(() => dir.delete(recursive: true));

      for (final url in const [
        'https://www.youtube.com/watch?v=fZ5u46AjFCU',
        'https://vimeo.com/181000543',
        'https://eigenbureau.nl/img/video/ik-zal-je-leren-toxisch.mp4',
      ]) {
        final deck = Deck(
          title: 'Demo',
          projectPath: dir.path,
          slides: [
            Slide.create(
              SlideType.video,
            ).copyWith(videoPath: url, title: 'Met titel'),
          ],
        );

        expect(
          analyzer
              .analyze(deck)
              .issues
              .any((i) => i.kind == SlideQualityIssueKind.missingMediaFile),
          isFalse,
          reason: '$url is een online bron, geen ontbrekend bestand',
        );
      }
    });

    test('does not report an online image URL as a missing file', () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
      addTearDown(() => dir.delete(recursive: true));

      final deck = Deck(
        title: 'Demo',
        projectPath: dir.path,
        slides: [
          Slide.create(SlideType.image).copyWith(
            imagePath: 'https://eigenbureau.nl/img/foto.jpg',
            imageAltText: 'Een foto',
          ),
        ],
      );

      expect(
        analyzer
            .analyze(deck)
            .issues
            .any((i) => i.kind == SlideQualityIssueKind.missingMediaFile),
        isFalse,
      );
    });

    // Een afbeelding in de vrije tekst kan net zo goed ontbreken als eentje in
    // een afbeeldingsveld; de melding wijst met `customMarkdown` de plek aan.
    test('detects a missing image referenced from the free text', () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
      addTearDown(() => dir.delete(recursive: true));

      final deck = Deck(
        title: 'Demo',
        projectPath: dir.path,
        slides: [
          Slide.create(SlideType.freeMarkdown).copyWith(
            title: 'Verhaal',
            customMarkdown: 'Zie ![de foto](images/weg.png) hierboven.',
          ),
        ],
      );

      final issue = analyzer
          .analyze(deck)
          .issues
          .firstWhere((i) => i.kind == SlideQualityIssueKind.missingMediaFile);
      expect(issue.field, 'customMarkdown');
      expect(issue.args['path'], 'images/weg.png');
    });

    test(
      'reports a free-text image that lies outside the presentation',
      () async {
        final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
        addTearDown(() => dir.delete(recursive: true));

        final deck = Deck(
          title: 'Demo',
          projectPath: dir.path,
          slides: [
            Slide.create(SlideType.freeMarkdown).copyWith(
              title: 'Verhaal',
              customMarkdown: 'Zie ![de foto](/elders/foto.png) hierboven.',
            ),
          ],
        );

        expect(
          analyzer
              .analyze(deck)
              .issues
              .any((i) => i.kind == SlideQualityIssueKind.externalMediaFile),
          isTrue,
        );
      },
    );

    test('stays quiet about a free-text image that is really there', () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-quality-');
      addTearDown(() => dir.delete(recursive: true));
      Directory('${dir.path}/images').createSync();
      File('${dir.path}/images/er.png').writeAsStringSync('x');

      final deck = Deck(
        title: 'Demo',
        projectPath: dir.path,
        slides: [
          Slide.create(SlideType.freeMarkdown).copyWith(
            title: 'Verhaal',
            customMarkdown: 'Zie ![de foto](images/er.png) hierboven.',
          ),
        ],
      );

      expect(
        analyzer
            .analyze(deck)
            .issues
            .where(
              (i) =>
                  i.kind == SlideQualityIssueKind.missingMediaFile ||
                  i.kind == SlideQualityIssueKind.externalMediaFile,
            ),
        isEmpty,
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

    test('flags a question slide without a correct/wrong answer pair', () {
      final broken = Slide.create(SlideType.question).copyWith(
        customMarkdown: const QuestionSpec(
          prompt: 'Wat is het antwoord?',
          answers: [QuestionAnswer(text: 'Enige optie', correct: false)],
        ).toBlock(),
      );
      final playable = Slide.create(SlideType.question).copyWith(
        customMarkdown: const QuestionSpec(
          prompt: 'Wat is het antwoord?',
          answers: [
            QuestionAnswer(text: 'Goed', correct: true),
            QuestionAnswer(text: 'Fout', correct: false),
          ],
        ).toBlock(),
      );
      final deck = Deck(title: 'Quiz', slides: [broken, playable]);

      final issues = analyzer
          .analyze(deck)
          .issues
          .where((i) => i.kind == SlideQualityIssueKind.questionNotAnswerable)
          .toList();
      expect(issues, hasLength(1));
      expect(issues.single.slideIndex, 0);
      expect(issues.single.severity, MarkdownValidationSeverity.warning);
    });
  });

  // #583: een scorecard die je zojuist had toegevoegd zag er in de editor
  // ingevuld uit, rendeerde wit, kwam als "geen problemen" door de
  // kwaliteitscontrole en exporteerde een lege pagina. De controle gaat daarom
  // niet over dat ene type maar over de vorm.
  group('lege dia', () {
    List<SlideQualityIssue> leegheidVan(Slide slide) => analyzer
        .analyze(Deck(title: 'D', slides: [slide]))
        .issues
        .where((i) => i.kind == SlideQualityIssueKind.emptySlide)
        .toList();

    test('élk vers slidetype meldt zichzelf als leeg', () {
      // Uitputtend over het enum in plaats van over een handvol types: een
      // nieuw slidetype dat zijn beginstand meebrengt hoort hier vanzelf in te
      // vallen, en als het dat niet doet wil ik dat hier zien en niet bij een
      // gebruiker die voor de zaal staat.
      for (final type in SlideType.values) {
        expect(
          leegheidVan(Slide.create(type)),
          hasLength(1),
          reason: 'een verse $type draagt niets van de auteur',
        );
      }
    });

    test('één ingevuld veld is genoeg om de melding te laten vallen', () {
      expect(
        leegheidVan(Slide.create(SlideType.section).copyWith(title: 'Deel 2')),
        isEmpty,
      );
      expect(
        leegheidVan(
          Slide.create(SlideType.image).copyWith(imagePath: 'foto.png'),
        ),
        isEmpty,
      );
      expect(
        leegheidVan(
          Slide.create(
            SlideType.scorecard,
          ).copyWith(customMarkdown: '{"entries":[{"label":"Open"}]}'),
        ),
        isEmpty,
      );
    });

    test('een sprekersnotitie is geen inhoud', () {
      // De zaal ziet hem niet. Een dia met alleen een notitie is precies de
      // lege dia waar dit over gaat, en zou anders stilzwijgend passeren.
      expect(
        leegheidVan(
          Slide.create(SlideType.bullets).copyWith(notes: 'niet vergeten'),
        ),
        hasLength(1),
      );
    });

    test('het is een waarschuwing, geen fout', () {
      // Een dia die je nog moet vullen is geen vergissing: tijdens het
      // schrijven mag de melding meelopen zonder de export te blokkeren.
      expect(
        leegheidVan(Slide.create(SlideType.scorecard)).single.severity,
        MarkdownValidationSeverity.warning,
      );
    });
  });

  group('memoizedFitScale (per-slide fit cache)', () {
    // Pins the Expando cache the analyzer uses to avoid re-measuring unchanged
    // slides on every deck edit. The behavioural contract — a hit skips
    // recompute, and a change in either keyed input invalidates it — is not
    // observable through analyze() in a headless test (text measurement is
    // font-independent there), so it is pinned directly on the helper.
    test('a hit returns the cached scale without recomputing', () {
      final slide = Slide.create(SlideType.bullets);
      var calls = 0;
      double run() => memoizedFitScale(slide, 'Roboto', () {
        calls++;
        return 1.5;
      });
      expect(run(), 1.5);
      expect(run(), 1.5);
      expect(calls, 1, reason: 'second call must hit the cache');
    });

    test('a different font for the same slide recomputes', () {
      final slide = Slide.create(SlideType.bullets);
      var calls = 0;
      double run(String font) => memoizedFitScale(slide, font, () {
        calls++;
        return calls.toDouble();
      });
      expect(run('Roboto'), 1);
      expect(run('Roboto'), 1, reason: 'same font hits');
      expect(run('Inter'), 2, reason: 'font change must miss and recompute');
      expect(calls, 2);
    });

    test('a different slide identity recomputes', () {
      final a = Slide.create(SlideType.bullets);
      final b = Slide.create(SlideType.bullets);
      var calls = 0;
      double run(Slide s) => memoizedFitScale(s, 'Roboto', () {
        calls++;
        return calls.toDouble();
      });
      run(a);
      run(b);
      run(a); // a is still cached from the first call
      expect(calls, 2, reason: 'distinct slide objects are distinct keys');
    });
  });

  group('image alt-text nudge (AI_ASSIST §6.2)', () {
    bool nudges(Slide slide) => analyzer
        .analyze(Deck(title: 'D', slides: [slide]))
        .issues
        .any((i) => i.kind == SlideQualityIssueKind.mediaMissingDescription);

    test('a bare image with no description is flagged', () {
      expect(
        nudges(Slide.create(SlideType.image).copyWith(imagePath: 'x.png')),
        isTrue,
      );
    });

    test('alt-text clears the flag', () {
      expect(
        nudges(
          Slide.create(SlideType.image).copyWith(
            imagePath: 'x.png',
            imageAltText: 'Duidelijke omschrijving',
          ),
        ),
        isFalse,
      );
    });

    test('a caption also clears the flag', () {
      expect(
        nudges(
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: 'x.png', imageCaption: '© Fotograaf'),
        ),
        isFalse,
      );
    });

    test('an image slide without an image is not flagged', () {
      expect(nudges(Slide.create(SlideType.image)), isFalse);
    });
  });
}
