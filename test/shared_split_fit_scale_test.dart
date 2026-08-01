import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';
import 'package:ocideck/services/split_run.dart';

void main() {
  // Layout measurement uses TextPainter, so the binding must be up.
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = ThemeProfile(fontFamily: 'Roboto');
  final font = profile.fontFamily;

  setUpAll(() async {
    for (final (family, path) in const [
      ('Roboto', 'assets/fonts/Roboto-Variable.ttf'),
      ('EB Garamond', 'assets/fonts/EBGaramond-Variable.ttf'),
    ]) {
      final bytes = File(path).readAsBytesSync();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    }
  });

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

    test('caches each deck, theme and font revision', () {
      final full = List.generate(
        14,
        (i) => 'Een wat langere bullet nummer $i voor een zichtbare meting',
      );
      final slides = [
        bullets(full),
        bullets(['vervolg'], continuesSplit: true),
      ];
      final otherProfile = profile.copyWith(
        name: 'Andere stijl',
        logoPath: 'logo.png',
        logoSize: 384,
      );

      final first = splitRunLayoutIndex(slides, profile, font);
      expect(splitRunLayoutIndex(slides, profile, font), same(first));

      final themed = splitRunLayoutIndex(slides, otherProfile, font);
      expect(themed, isNot(same(first)));
      expect(
        themed.fitScaleFor(0),
        isNot(first.fitScaleFor(0)),
        reason: 'de grotere logostrook verkleint de beschikbare teksthoogte',
      );
      expect(
        splitRunLayoutIndex(slides, profile, font),
        same(first),
        reason: 'terugkeren naar een bekende themarevisie is een cachehit',
      );

      final otherFont = splitRunLayoutIndex(slides, profile, 'EB Garamond');
      expect(otherFont, isNot(same(first)));
      expect(
        otherFont.fitScaleFor(0),
        isNot(first.fitScaleFor(0)),
        reason: 'de geladen fonts hebben aantoonbaar andere tekstmaten',
      );
      expect(
        splitRunLayoutIndex(slides, profile, font),
        same(first),
        reason: 'terugkeren naar een bekende fontrevisie is een cachehit',
      );
    });

    test('a new deck revision refreshes content and run boundaries', () {
      final full = List.generate(14, (i) => 'Een lange bullet nummer $i');
      final slides = [
        bullets(full),
        bullets(['kort'], continuesSplit: true),
      ];
      final first = splitRunLayoutIndex(slides, profile, font);
      final firstScale = first.fitScaleFor(0);

      final changedContent = [
        bullets(['kort']),
        bullets(['ook kort'], continuesSplit: true),
      ];
      final contentIndex = splitRunLayoutIndex(changedContent, profile, font);
      expect(contentIndex, isNot(same(first)));
      expect(contentIndex.fitScaleFor(0), isNot(firstScale));

      final changedBoundary = [
        slides[0],
        slides[1].copyWith(continuesSplit: false),
      ];
      final boundaryIndex = splitRunLayoutIndex(changedBoundary, profile, font);
      expect(boundaryIndex, isNot(same(first)));
      expect(boundaryIndex.rangeFor(0), (0, 0));
      expect(boundaryIndex.fitScaleFor(0), isNull);
    });

    test('explicit invalidation covers in-place presenter content changes', () {
      final slides = [
        bullets(List.generate(12, (i) => 'Lange regel $i')),
        bullets(['kort'], continuesSplit: true),
      ];
      final before = splitRunLayoutIndex(slides, profile, font);

      slides[0] = bullets(['nu kort']);
      invalidateSplitRunLayout(slides);
      final after = splitRunLayoutIndex(slides, profile, font);

      expect(after, isNot(same(before)));
      expect(after.fitScaleFor(0), isNot(before.fitScaleFor(0)));
    });

    test('explicit invalidation covers an in-place run-boundary change', () {
      final slides = [
        bullets(['eerste']),
        bullets(['vervolg'], continuesSplit: true),
      ];
      final before = splitRunLayoutIndex(slides, profile, font);
      expect(before.rangeFor(0), (0, 1));
      expect(before.fitScaleFor(0), isNotNull);

      slides[1] = slides[1].copyWith(continuesSplit: false);
      invalidateSplitRunLayout(slides);
      final after = splitRunLayoutIndex(slides, profile, font);

      expect(after, isNot(same(before)));
      expect(after.rangeFor(0), (0, 0));
      expect(after.fitScaleFor(0), isNull);
    });

    test('computes boundaries separately for each type and list style', () {
      final slides = [
        bullets(['a']),
        bullets(['a'], continuesSplit: true),
        bullets([
          'b',
        ]).copyWith(listStyle: ListStyle.numbered, continuesSplit: true),
        bullets([
          'b',
        ]).copyWith(listStyle: ListStyle.numbered, continuesSplit: true),
        Slide.create(SlideType.title),
      ];
      var measurements = 0;

      final index = buildSplitRunLayoutIndex(
        slides,
        profile,
        font,
        measureMember: (_, _, _) {
          measurements++;
          return 1 - measurements / 1000;
        },
      );

      expect(index.rangeFor(0), (0, 1));
      expect(index.rangeFor(1), (0, 1));
      expect(index.rangeFor(2), (2, 3));
      expect(index.rangeFor(3), (2, 3));
      expect(index.rangeFor(4), (4, 4));
      expect(measurements, 4, reason: 'losse en ongeschikte slides meten niet');
    });

    test('measures a 150-page run once, independent of index lookups', () {
      final slides = [
        bullets(['pagina 0']),
        for (var i = 1; i < 150; i++)
          bullets(['pagina $i'], continuesSplit: true),
      ];
      var measurements = 0;

      final index = buildSplitRunLayoutIndex(
        slides,
        profile,
        font,
        measureMember: (_, _, _) {
          measurements++;
          return 1 - measurements / 1000;
        },
      );

      expect(index.rangeFor(0), (0, 149));
      expect(index.rangeFor(149), (0, 149));
      expect(measurements, 150, reason: 'één meting per runlid, dus lineair');
      for (var i = 0; i < slides.length; i++) {
        index.fitScaleFor(i);
      }
      expect(
        measurements,
        150,
        reason: 'alle oppervlakken lezen alleen de index',
      );
    });
  });
}
