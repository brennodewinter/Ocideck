import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_layout_metrics.dart'
    show kTextDensityWarningScale;
import 'package:ocideck/services/split_run.dart';

/// Pure run-logica: welke slides vormen samen een gesplitste reeks, en wanneer
/// trekt één pagina de rest onnodig omlaag. Geen layout, geen thema.
void main() {
  Slide bullets(List<String> items, {bool continuesSplit = false}) =>
      Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: items, continuesSplit: continuesSplit);

  group('splitRunRange', () {
    test('een losse slide is zijn eigen run', () {
      final slides = [
        bullets(['a']),
        bullets(['b']),
      ];
      expect(splitRunRange(slides, 0), (0, 0));
      expect(splitRunRange(slides, 1), (1, 1));
    });

    test('de vlag hecht een pagina aan zijn voorganger', () {
      final slides = [
        bullets(['a']),
        bullets(['b'], continuesSplit: true),
        bullets(['c'], continuesSplit: true),
        bullets(['d']),
      ];
      // Elke pagina van de reeks vindt dezelfde grenzen.
      expect(splitRunRange(slides, 0), (0, 2));
      expect(splitRunRange(slides, 1), (0, 2));
      expect(splitRunRange(slides, 2), (0, 2));
      expect(splitRunRange(slides, 3), (3, 3));
    });

    test('een ander slidetype breekt de reeks', () {
      final slides = [
        bullets(['a']),
        Slide.create(
          SlideType.bulletsImage,
        ).copyWith(bullets: ['b'], continuesSplit: true),
      ];
      expect(splitRunRange(slides, 0), (0, 0));
    });

    test('een niet-splitsbaar type zit nooit in een run', () {
      final slides = [
        bullets(['a']),
        Slide.create(SlideType.chart).copyWith(continuesSplit: true),
      ];
      expect(splitRunRange(slides, 1), (1, 1));
    });

    test('een index buiten de lijst valt terug op zichzelf', () {
      expect(splitRunRange(const [], 0), (0, 0));
      expect(
        splitRunRange([
          bullets(const ['a']),
        ], 7),
        (7, 7),
      );
    });
  });

  group('splitRunDrag', () {
    ({int offender, List<int> dragged})? drag(List<double> scales) =>
        splitRunDrag(scales, warningScale: kTextDensityWarningScale);

    test('een run van één pagina meldt niets', () {
      expect(drag([0.2]), isNull);
    });

    test('pagina\'s van vergelijkbare grootte zijn een echte splitsing', () {
      // Precies waar de gedeelde schaal voor bedoeld is: niet melden.
      expect(drag([0.30, 0.34, 0.31]), isNull);
    });

    test('een run die ruim past heeft geen probleem', () {
      // Wel een groot verschil, maar iedereen rendert comfortabel.
      expect(drag([0.95, 2.4]), isNull);
    });

    test('één overvolle pagina die de rest meetrekt wordt gemeld', () {
      final result = drag([0.85, 0.20]);
      expect(result, isNotNull);
      expect(result!.offender, 1);
      expect(result.dragged, [0]);
    });

    test('alle meegetrokken pagina\'s worden gemeld, de dader niet', () {
      final result = drag([0.85, 0.20, 0.90, 0.25]);
      expect(result!.offender, 1);
      // 0.25 blijft onder 2× de gedeelde 0.20 — die pagina is echt vol.
      expect(result.dragged, [0, 2]);
    });

    test('de drempel ligt op precies twee keer de gedeelde schaal', () {
      expect(drag([0.40, 0.20])!.dragged, [0]); // exact 2× telt mee
      expect(drag([0.39, 0.20]), isNull); // net eronder niet
    });
  });
}
