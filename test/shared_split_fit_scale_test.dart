import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  // Layout measurement uses TextPainter, so the binding must be up.
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = ThemeProfile();
  final font = profile.fontFamily;

  Slide bullets(List<String> items, {bool continuesSplit = false}) =>
      Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: items, continuesSplit: continuesSplit);

  Slide bulletsImage(List<String> items, {bool continuesSplit = false}) =>
      Slide.create(SlideType.bulletsImage).copyWith(
        bullets: items,
        imagePath: 'foto.png',
        continuesSplit: continuesSplit,
      );

  group('sharedSplitFitScale', () {
    test('a standalone slide (no continuation neighbour) shares nothing', () {
      final slides = [
        bullets(['a', 'b', 'c']),
        bullets(['x', 'y']), // not flagged → not part of a run
      ];
      expect(sharedSplitFitScale(slides, 0, profile, font), isNull);
      expect(sharedSplitFitScale(slides, 1, profile, font), isNull);
    });

    test('a two-page run shares the fuller page\'s (smaller) scale', () {
      final full = List.generate(14, (i) => 'Een wat langere bullet nummer $i');
      final sparse = ['Kort', 'Ook kort'];
      final slides = [
        bullets(full), // page 1 — the fullest, drives the size
        bullets(sparse, continuesSplit: true), // page 2 — continuation
      ];

      final shared = sharedSplitFitScale(slides, 0, profile, font);
      final sharedFromSecond = sharedSplitFitScale(slides, 1, profile, font);

      // Both pages resolve to the same shared scale...
      expect(shared, isNotNull);
      expect(sharedFromSecond, shared);

      // ...which is the minimum of the two pages' own fit scales (no logo, so
      // the reserve is zero and the member scale is just the natural fit).
      final fullScale = bulletsSlideFitScale(slide: bullets(full), font: font);
      final sparseScale = bulletsSlideFitScale(
        slide: bullets(sparse),
        font: font,
      );
      expect(sparseScale, greaterThan(fullScale)); // sparse would grow larger
      expect(shared, closeTo(fullScale, 1e-9)); // shared clamps to the fuller
    });

    test('a run of three continuation pages all share one scale', () {
      final slides = [
        bullets(List.generate(12, (i) => 'Regel $i')),
        bullets(['a', 'b'], continuesSplit: true),
        bullets(['c'], continuesSplit: true),
      ];
      final s0 = sharedSplitFitScale(slides, 0, profile, font);
      final s1 = sharedSplitFitScale(slides, 1, profile, font);
      final s2 = sharedSplitFitScale(slides, 2, profile, font);
      expect(s0, isNotNull);
      expect(s1, s0);
      expect(s2, s0);
    });

    test('a bullets+image run shares the fuller page\'s scale', () {
      // Beide helften van een gesplitste bulletsImage-slide houden de afbeelding
      // en vormen dus een echte gedeelde-schaal-run.
      final full = List.generate(10, (i) => 'Een wat langere bullet nummer $i');
      final sparse = ['Kort', 'Ook kort'];
      final slides = [
        bulletsImage(full),
        bulletsImage(sparse, continuesSplit: true),
      ];

      final shared = sharedSplitFitScale(slides, 0, profile, font);
      expect(shared, isNotNull);
      expect(sharedSplitFitScale(slides, 1, profile, font), shared);

      final fullScale = bulletsImageSlideFitScale(
        slide: bulletsImage(full),
        font: font,
      );
      final sparseScale = bulletsImageSlideFitScale(
        slide: bulletsImage(sparse),
        font: font,
      );
      expect(sparseScale, greaterThan(fullScale));
      expect(shared, closeTo(fullScale, 1e-9));
    });

    test(
      'a continuation whose type differs from its predecessor shares nothing',
      () {
        // Wisselt de gebruiker de vervolgpagina naar een gewone bulletslide (geen
        // afbeelding), dan verschillen de types en vormen ze geen gedeelde run.
        final slides = [
          bulletsImage(['a', 'b']),
          bullets(['c', 'd'], continuesSplit: true),
        ];
        expect(sharedSplitFitScale(slides, 1, profile, font), isNull);
      },
    );
  });
}
