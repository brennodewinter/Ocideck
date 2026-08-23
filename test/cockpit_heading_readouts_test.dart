import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Regressie voor issue #1110: de uitleesregels (ACT/TGT/marker) van het
/// kompas-instrument liepen buiten de wijzerplaat — links botsten ze op de
/// kompasroos, rechts staken ze voorbij de bezel het buurinstrument in.
///
/// De twee visuele stijlen hebben een andere vorm en dus een andere oplossing,
/// en de eerste poging faalde juist in de authentieke stand omdat een ronde
/// bezel de cel vult: daar ís geen vrije rechterkolom. Deze test toetst per
/// stijl de geometrie zoals `_heading` die tekent — puur rekenwerk, dus
/// deterministisch ondanks de blokjesfonts van de widget-testomgeving:
/// * **klassiek** — een rechterkolom naast de roos, binnen de rechthoekige kaart;
/// * **authentiek** — een uitleesvenster binnen de ronde face-cirkel.
/// In beide gevallen wordt ook de breedste string (een lange gelokaliseerde
/// markerregel) nagelopen: die moet met een ellipsis binnen de plaat blijven.
void main() {
  // Representatieve paint-afmetingen van één instrument; het vierkant is de
  // ongunstige rand (de roos/bezel vult dan het meest van de breedte).
  const sizes = <Size>[
    Size(309, 241), // 3 kolommen op een 16:9-dia
    Size(464, 261), // 2 kolommen op een 16:9-dia
    Size(240, 240), // bijna vierkant
    Size(360, 180), // sterk liggend
  ];

  const longMarker = 'Kursabweichungen im Steigflug über dem Fjord';

  double measure(String text, double fontSize, double maxWidth, TextAlign a) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      textAlign: a,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return painter.width;
  }

  group('klassiek', () {
    for (final size in sizes) {
      final dial = cockpitHeadingDial(size, authentic: false);
      final r = cockpitHeadingReadouts(
        size,
        dial.center,
        dial.radius,
        authentic: false,
      );
      final roseRight = dial.center.dx + dial.radius;
      final rightEdge = r.actualCenter.dx; // rechts uitgelijnd
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      test('$label: rechterkolom, binnen de kaart, vrij van de roos', () {
        expect(r.anchorRight, isTrue);
        expect(r.window, isNull);
        expect(rightEdge, lessThanOrEqualTo(size.width * 0.98));
        expect(r.maxWidth, greaterThanOrEqualTo(size.width * 0.14));
        expect(
          rightEdge - r.maxWidth,
          greaterThanOrEqualTo(roseRight),
          reason: 'de kolom mag niet over de roos vallen',
        );
      });

      test('$label: lange marker blijft rechts binnen de kolom', () {
        final wdt = measure(
          longMarker,
          size.width * 0.032,
          r.maxWidth,
          TextAlign.right,
        );
        expect(wdt, lessThanOrEqualTo(r.maxWidth + 0.5));
        expect(rightEdge - wdt, greaterThanOrEqualTo(roseRight - 0.5));
        expect(rightEdge, lessThanOrEqualTo(size.width));
      });
    }
  });

  group('authentiek', () {
    for (final size in sizes) {
      final dial = cockpitHeadingDial(size, authentic: true);
      final r = cockpitHeadingReadouts(
        size,
        dial.center,
        dial.radius,
        authentic: true,
      );
      // De face-cirkel die `_authenticFrame` tekent, waar het venster in moet
      // vallen.
      final faceCenter = Offset(size.width / 2, size.height / 2);
      final faceR = size.shortestSide * kCockpitAuthenticFaceFactor;
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      double cornerDist(double dx, double dy) =>
          (Offset(dx, dy) - faceCenter).distance;

      test('$label: uitleesvenster valt binnen de face-cirkel', () {
        expect(r.anchorRight, isFalse);
        final win = r.window;
        expect(win, isNotNull);
        win!;
        // Alle vier de hoeken binnen de face — anders loopt het venster over de
        // bezel (de fout die de eerste poging in deze stand overhield).
        for (final corner in [
          cornerDist(win.left, win.top),
          cornerDist(win.right, win.top),
          cornerDist(win.left, win.bottom),
          cornerDist(win.right, win.bottom),
        ]) {
          expect(
            corner,
            lessThanOrEqualTo(faceR),
            reason: 'venster steekt buiten de wijzerplaat',
          );
        }
        expect(r.maxWidth, greaterThan(0));
        expect(r.maxWidth, lessThanOrEqualTo(win.width));
      });

      test('$label: de drie regels staan gecentreerd binnen het venster', () {
        final win = r.window!;
        for (final p in [r.actualCenter, r.targetCenter, r.markerCenter]) {
          expect(p.dx, faceCenter.dx);
          expect(p.dy, greaterThanOrEqualTo(win.top));
          expect(p.dy, lessThanOrEqualTo(win.bottom));
        }
        expect(r.actualCenter.dy, lessThan(r.targetCenter.dy));
        expect(r.targetCenter.dy, lessThan(r.markerCenter.dy));
      });

      test('$label: lange marker ellipst binnen het venster en de face', () {
        final wdt = measure(
          longMarker,
          size.shortestSide * 0.047,
          r.maxWidth,
          TextAlign.center,
        );
        expect(wdt, lessThanOrEqualTo(r.maxWidth + 0.5));
        final left = r.markerCenter.dx - wdt / 2;
        final right = r.markerCenter.dx + wdt / 2;
        expect(left, greaterThanOrEqualTo(r.window!.left - 0.5));
        expect(right, lessThanOrEqualTo(r.window!.right + 0.5));
        // En dus binnen de face-cirkel (het venster valt daar al binnen).
        expect(cornerDist(left, r.markerCenter.dy), lessThanOrEqualTo(faceR));
        expect(cornerDist(right, r.markerCenter.dy), lessThanOrEqualTo(faceR));
      });
    }
  });
}
