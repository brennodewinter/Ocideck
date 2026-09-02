import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/services/cockpit_layout.dart';

/// De cockpit-dia zette de waarde-uitlezing als één ongebonden regel
/// "getal+eenheid" ín de wijzerplaat, op de hoogte van de schaalcijfers en de
/// bandeinden; een lange eenheid liep dwars door de schaal. Deze test toetst de
/// rekenkern van het herontwerp (docs/design/COCKPIT_LAYOUT.md): het venster
/// ligt buiten de bezel, het label onder de groep, en de zes meters van de
/// aanleiding passen zonder ellipsis — puur rekenwerk, dus deterministisch.
void main() {
  // De dia uit de aanleiding: zes meters, lange eenheden, een lang label.
  const deck = [
    CockpitMeterSpec(
      label: 'Inspanning',
      unit: '% van maximale hartslag',
      min: 50,
      max: 100,
      greenFrom: 60,
      greenTo: 75,
      redFrom: 85,
      value: 70,
    ),
    CockpitMeterSpec(
      type: CockpitMeterType.thermometer,
      label: 'Koolhydraten',
      unit: 'g per uur',
      min: 0,
      max: 120,
      greenFrom: 60,
      greenTo: 90,
      redFrom: 110,
      value: 70,
    ),
    CockpitMeterSpec(
      type: CockpitMeterType.voltmeter,
      label: 'Vocht',
      unit: 'ml per uur',
      min: 0,
      max: 1000,
      greenFrom: 400,
      greenTo: 750,
      redFrom: 900,
      value: 550,
    ),
    CockpitMeterSpec(
      type: CockpitMeterType.altimeter,
      label: 'Natrium',
      unit: 'mg per uur',
      min: 0,
      max: 1500,
      greenFrom: 300,
      greenTo: 800,
      redFrom: 1200,
      value: 500,
    ),
    CockpitMeterSpec(
      type: CockpitMeterType.climbDescent,
      label: 'Tempo ten opzichte van plan',
      unit: '%',
      min: -20,
      max: 20,
      neutralFrom: -5,
      neutralTo: 5,
      value: 3,
    ),
    CockpitMeterSpec(
      type: CockpitMeterType.horizon,
      label: 'Houding',
      pitch: 4,
      bank: 0,
    ),
  ];

  // Het raster van een 1920×1080-dia met titel en logo-vrije zone.
  const rasterW = 1746.0;
  const rasterH = 789.0;

  group('raster', () {
    test('kolomregel: geen leeg vak bij drie en vijf meters', () {
      expect([1, 2, 3, 4, 5, 6].map(cockpitColumns), [1, 2, 3, 2, 3, 3]);
    });

    test('een onvolledige laatste rij staat gecentreerd', () {
      final plan = CockpitGridPlan.compute(
        count: 5,
        width: rasterW,
        height: rasterH,
      );
      expect(plan.cells, hasLength(5));
      final top = plan.cells.take(3).toList();
      final bottom = plan.cells.skip(3).toList();
      final topCenter = (top.first.x + top.last.right) / 2;
      final bottomCenter = (bottom.first.x + bottom.last.right) / 2;
      expect(bottomCenter, closeTo(topCenter, 0.01));
      expect(bottom.first.x, greaterThan(top.first.x));
    });

    test('cellen zijn even groot en vullen het raster', () {
      final plan = CockpitGridPlan.compute(
        count: 6,
        width: rasterW,
        height: rasterH,
      );
      expect(plan.columns, 3);
      expect(plan.rows, 2);
      for (final c in plan.cells) {
        expect(c.w, closeTo(plan.cellWidth, 0.01));
        expect(c.h, closeTo(plan.cellHeight, 0.01));
        expect(c.right, lessThanOrEqualTo(rasterW + 0.01));
        expect(c.bottom, lessThanOrEqualTo(rasterH + 0.01));
      }
    });
  });

  group('celindeling', () {
    // Per aantal meters de cel op de 16:9-dia.
    CockpitCellPlan planFor(int count, {int digits = 4}) {
      final grid = CockpitGridPlan.compute(
        count: count,
        width: rasterW,
        height: rasterH,
      );
      return CockpitCellPlan.compute(
        width: grid.cellWidth,
        height: grid.cellHeight,
        longestDigits: digits,
      );
    }

    test('breed naast, smal eronder', () {
      expect(planFor(1).mode, CockpitCellMode.wide);
      expect(planFor(2).mode, CockpitCellMode.stacked);
      expect(planFor(3).mode, CockpitCellMode.stacked);
      expect(planFor(4).mode, CockpitCellMode.wide);
      expect(planFor(5).mode, CockpitCellMode.wide);
      expect(planFor(6).mode, CockpitCellMode.wide);
    });

    for (final count in [1, 2, 3, 4, 5, 6]) {
      test('$count meters: venster raakt de bezel niet en blijft in de cel', () {
        final p = planFor(count);
        final win = p.window;
        // Alle vier de hoeken van het venster buiten de bezelcirkel.
        for (final (dx, dy) in [
          (win.x, win.y),
          (win.right, win.y),
          (win.x, win.bottom),
          (win.right, win.bottom),
        ]) {
          final ddx = dx - p.dialCenterX;
          final ddy = dy - p.dialCenterY;
          final dist = (ddx * ddx + ddy * ddy);
          expect(
            dist,
            greaterThanOrEqualTo(p.bezelRadius * p.bezelRadius),
            reason: 'vensterhoek ($dx, $dy) ligt op de bezel',
          );
        }
        expect(win.x, greaterThanOrEqualTo(0));
        expect(win.right, lessThanOrEqualTo(p.width + 0.01));
        expect(win.bottom, lessThanOrEqualTo(p.instrumentBand.bottom + 0.01));
        // De bezel zelf blijft binnen de instrumentband.
        expect(p.dialCenterX - p.bezelRadius, greaterThanOrEqualTo(-0.01));
        expect(
          p.dialCenterY + p.bezelRadius,
          lessThanOrEqualTo(p.instrumentBand.bottom + 0.01),
        );
        // Het label onder de groep, binnen de cel.
        expect(p.labelBox.y, greaterThanOrEqualTo(p.instrumentBand.bottom - 0.01));
        expect(p.labelBox.bottom, lessThanOrEqualTo(p.height + 0.01));
      });
    }

    test('zes meters op 1080p: de maten uit het ontwerp', () {
      final p = planFor(6);
      expect(p.bezelRadius * 2, closeTo(300, 6));
      expect(p.numberSize, closeTo(82, 3));
      expect(p.labelSize, closeTo(32, 1));
      expect(p.scaleSize, closeTo(21, 1));
      expect(p.window.w, closeTo(205, 5));
    });

    test('één getalmaat per dia, uit het langste getal', () {
      expect(cockpitLongestDigits(deck), 4); // "1000", "1500"
      expect(
        cockpitLongestDigits(const [
          CockpitMeterSpec(min: 0, max: 99999, value: 12345.5),
        ]),
        7,
      );
      // Een groter getal → kleiner lettertype, nooit een ellipsis.
      expect(planFor(6, digits: 7).numberSize, lessThan(planFor(6).numberSize));
    });
  });

  group('tekstbudget', () {
    final grid = CockpitGridPlan.compute(
      count: 6,
      width: rasterW,
      height: rasterH,
    );
    final plan = CockpitCellPlan.compute(
      width: grid.cellWidth,
      height: grid.cellHeight,
      longestDigits: cockpitLongestDigits(deck),
    );
    List<CockpitReadoutLine> lines(CockpitMeterSpec m) => cockpitReadoutLines(
      m,
      plan,
      attitudeTemplate: 'P {pitch}  B {bank}',
      actualTemplate: 'ACT {value}°',
      targetTemplate: 'TGT {heading}°',
    );

    test('de zes meters passen zonder ellipsis en zonder krimp', () {
      for (final m in deck) {
        final label = plan.fitLabel(m.label);
        expect(label.ellipsized, isFalse, reason: m.label);
        expect(label.size, plan.labelSize, reason: m.label);
        expect(label.lines, hasLength(1), reason: m.label);
        for (final l in lines(m)) {
          expect(l.text.endsWith('…'), isFalse, reason: '${m.label}: ${l.text}');
          expect(
            l.estimatedWidth,
            lessThanOrEqualTo(plan.windowTextWidth + 0.01),
            reason: '${m.label}: "${l.text}" past niet in het venster',
          );
        }
        expect(
          cockpitReadoutHeight(lines(m)),
          lessThanOrEqualTo(plan.window.h),
          reason: '${m.label}: stapel hoger dan het venster',
        );
      }
    });

    test('een lange eenheid wikkelt naar twee regels op volle grootte', () {
      final l = lines(deck[0]);
      expect(l.map((x) => x.text), ['70', '% van maximale', 'hartslag']);
      // Gewikkeld op de grootste maat die schoon past, niet op de vloer.
      expect(l[1].size, greaterThan(plan.unitFloor));
      expect(l[1].size, greaterThan(plan.unitSize * 0.9));
    });

    test('een korte eenheid staat inline achter het getal', () {
      final l = lines(deck[4]);
      expect(l, hasLength(1));
      expect(l.single.text, '+3');
      expect(l.single.inlineUnit, '%');
      expect(cockpitUnitInline('/10'), isTrue);
      expect(cockpitUnitInline('km/u'), isFalse);
      expect(cockpitUnitInline('g per uur'), isFalse);
    });

    test('de horizon toont pitch en bank als twee regels in inkt', () {
      final l = lines(deck[5]);
      expect(l.map((x) => x.text), ['P 4', 'B 0']);
      expect(l.every((x) => x.strong), isTrue);
      expect(splitCockpitAttitude('Pitch 4 Bank 0'), ['Pitch 4 Bank 0']);
    });

    test('het kompas zet ACT, TGT en een begrensde markerregel in het venster', () {
      const longMarker = 'Kursabweichungen im Steigflug über dem Fjord';
      final l = lines(
        const CockpitMeterSpec(
          type: CockpitMeterType.heading,
          label: 'Course',
          value: 187,
          heading: 90,
          markerLabel: longMarker,
        ),
      );
      expect(l.first.text, 'ACT 187°');
      expect(l[1].text, 'TGT 090°');
      final marker = l.skip(2).map((x) => x.text).toList();
      expect(marker, hasLength(2));
      expect(marker.last, endsWith('…'));
      for (final line in l) {
        expect(line.estimatedWidth, lessThanOrEqualTo(plan.windowTextWidth + 0.01));
      }
    });

    test('de cascade: passen, krimpen, wikkelen, dan pas ellipsis', () {
      final fits = fitCockpitText(
        'Tempo ten opzichte van plan',
        width: 505,
        size: 32,
        floor: 21,
        maxLines: 2,
      );
      expect(fits.lines, ['Tempo ten opzichte van plan']);
      expect(fits.size, 32);
      final shrunk = fitCockpitText(
        'Natriumaanvullingssnelheid',
        width: 320,
        size: 32,
        floor: 21,
        maxLines: 2,
      );
      expect(shrunk.lines, hasLength(1));
      expect(shrunk.size, lessThan(32));
      expect(shrunk.size, greaterThanOrEqualTo(21));
      final wrapped = fitCockpitText(
        'Hoogte boven zeeniveau bij aankomst',
        width: 300,
        size: 32,
        floor: 21,
        maxLines: 2,
      );
      expect(wrapped.lines, hasLength(2));
      expect(wrapped.ellipsized, isFalse);
      // Eerst wikkelen op maat, dan pas krimpen: twee regels op 32.
      final unit = fitCockpitText(
        '% van maximale hartslag',
        width: 189,
        size: 26,
        floor: 21,
        maxLines: 2,
        wrapFirst: true,
      );
      expect(unit.lines, ['% van maximale', 'hartslag']);
      expect(unit.size, greaterThan(23));
      final cut = fitCockpitText(
        'Een label dat werkelijk veel te lang is voor welke cel dan ook',
        width: 200,
        size: 32,
        floor: 21,
        maxLines: 2,
      );
      expect(cut.lines, hasLength(2));
      expect(cut.ellipsized, isTrue);
      expect(wrapCockpitWords('Kohlenhydratzufuhr', 6, 3), [
        'Kohlen',
        'hydrat',
        'zufuhr',
      ]);
      expect(wrapCockpitWords('Kohlenhydratzufuhr', 6, 2), [
        'Kohlen',
        'hydra…',
      ]);
    });

    test('getallen: geen overbodige decimalen, plus bij klimmen', () {
      expect(cockpitFormatNumber(70), '70');
      expect(cockpitFormatNumber(8.4), '8.4');
      expect(cockpitValueText(deck[4]), '+3');
      expect(
        cockpitValueText(
          const CockpitMeterSpec(
            type: CockpitMeterType.climbDescent,
            min: -20,
            max: 20,
            value: -8,
          ),
        ),
        '-8',
      );
    });
  });
}
