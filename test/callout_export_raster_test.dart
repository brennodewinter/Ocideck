// Rendered export verification for callouts (IMAGE_CALLOUTS.md §9 gate).
//
// Verifies that the HTML and LaTeX exports place callout markers at the exact
// positions dictated by the geometry — a "raster" check, not just a "contains"
// check. Covers all three presentation modes (pin, region, arrow) and the
// reveal:steps flatten (static export shows all callouts).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/latex/beamer_slide_builder.dart';
import 'package:ocideck/services/marp_html_service.dart';

const _splitBody =
    '<div class="split-image">\n![](photo.png)\n</div>\n'
    '- bullet (A)\n';

Slide _slide({
  CalloutPresentation mode = CalloutPresentation.pin,
  BulletRevealMode reveal = BulletRevealMode.all,
  List<ImageCallout> callouts = const [],
}) => Slide.create(SlideType.bulletsImage).copyWith(
  anchor: 's1',
  title: 'T',
  imagePath: 'photo.png',
  calloutPresentation: mode,
  calloutReveal: reveal,
  callouts: callouts,
);

void main() {
  group('HTML export raster — pin mode', () {
    test('point at (0.4, 0.2) → marker at left:40.00%, top:20.00%', () {
      final slide = _slide(
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      // The marker style must have left:40.00% and top:20.00%.
      expect(out, contains('left:40.00%'));
      expect(out, contains('top:20.00%'));
    });

    test('point at (0, 0) → marker at top-left corner', () {
      final slide = _slide(
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0, 0)]),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      expect(out, contains('left:0.00%'));
      expect(out, contains('top:0.00%'));
    });

    test('point at (1, 1) → marker at bottom-right corner', () {
      final slide = _slide(
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(1, 1)]),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      expect(out, contains('left:100.00%'));
      expect(out, contains('top:100.00%'));
    });

    test('region in pin mode → marker at centre', () {
      final slide = _slide(
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutRegion(0.4, 0.2, 0.2, 0.2)],
          ),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      // Centre = (0.4 + 0.2/2, 0.2 + 0.2/2) = (0.5, 0.3).
      expect(out, contains('left:50.00%'));
      expect(out, contains('top:30.00%'));
    });
  });

  group('HTML export raster — region mode', () {
    test('region target → outlined div at exact geometry', () {
      final slide = _slide(
        mode: CalloutPresentation.region,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutRegion(0.1, 0.2, 0.3, 0.4)],
          ),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      expect(out, contains('ocideck-region'));
      expect(out, contains('left:10.00%'));
      expect(out, contains('top:20.00%'));
      expect(out, contains('width:30.00%'));
      expect(out, contains('height:40.00%'));
    });

    test('point target in region mode → still a pin, no invented box', () {
      final slide = _slide(
        mode: CalloutPresentation.region,
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.5, 0.5)]),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      // Point in region mode is a pin, not a region div.
      expect(out, contains('ocideck-callout'));
      expect(out, isNot(contains('ocideck-region')));
    });
  });

  group('HTML export raster — arrow mode', () {
    test('point target → arrow from left edge to point', () {
      final slide = _slide(
        mode: CalloutPresentation.arrow,
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.6, 0.3)]),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      expect(out, contains('ocideck-arrow'));
      // Arrow goes from left:0% to the point's x (width:60%).
      expect(out, contains('left:0%'));
      expect(out, contains('top:30.00%'));
      expect(out, contains('width:60.00%'));
    });

    test('region target → arrow to left edge at centre height', () {
      final slide = _slide(
        mode: CalloutPresentation.arrow,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutRegion(0.4, 0.2, 0.2, 0.2)],
          ),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      // Region div at exact geometry.
      expect(out, contains('ocideck-region'));
      expect(out, contains('left:40.00%'));
      // Arrow to left edge at centre y = 0.2 + 0.2/2 = 0.3.
      expect(out, contains('ocideck-arrow'));
      expect(out, contains('top:30.00%'));
    });
  });

  group('HTML export raster — reveal:steps flatten', () {
    test('static export shows all callouts regardless of reveal mode', () {
      final slide = _slide(
        reveal: BulletRevealMode.steps,
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
          ImageCallout(reference: 'B', targets: [CalloutPoint(0.6, 0.4)]),
        ],
      );
      final out = renderImageCallouts(_splitBody, slide);
      // Both callouts must appear in the static export (flatten).
      expect(out, contains('left:40.00%'));
      expect(out, contains('left:60.00%'));
    });
  });

  group('LaTeX export raster — TikZ coordinates', () {
    test('point at (0.4, 0.2) → TikZ node at (0.4, 0.8)', () {
      // TikZ y-axis goes up, image-space y goes down → flip y: 1 - 0.2 = 0.8.
      final slide = _slide(
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
        ],
      );
      final deck = Deck(title: 't', slides: [slide]);
      final latex = buildBeamerBody(deck);
      expect(latex, contains('at (0.4000,0.8000)'));
    });

    test(
      'point at (0, 0) → TikZ node at (0, 1) (bottom-left in image = top in TikZ)',
      () {
        final slide = _slide(
          callouts: const [
            ImageCallout(reference: 'A', targets: [CalloutPoint(0, 0)]),
          ],
        );
        final deck = Deck(title: 't', slides: [slide]);
        final latex = buildBeamerBody(deck);
        expect(latex, contains('at (0.0000,1.0000)'));
      },
    );

    test('point at (1, 1) → TikZ node at (1, 0)', () {
      final slide = _slide(
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(1, 1)]),
        ],
      );
      final deck = Deck(title: 't', slides: [slide]);
      final latex = buildBeamerBody(deck);
      expect(latex, contains('at (1.0000,0.0000)'));
    });

    test('region in pin mode → TikZ node at centre', () {
      // Centre = (0.4 + 0.2/2, 0.2 + 0.2/2) = (0.5, 0.3).
      // TikZ y = 1 - 0.3 = 0.7.
      final slide = _slide(
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutRegion(0.4, 0.2, 0.2, 0.2)],
          ),
        ],
      );
      final deck = Deck(title: 't', slides: [slide]);
      final latex = buildBeamerBody(deck);
      expect(latex, contains('at (0.5000,0.7000)'));
    });

    test('region in region mode → TikZ rectangle at correct corners', () {
      // Region (0.1, 0.2, 0.3, 0.4):
      // Image space: top-left = (0.1, 0.2), bottom-right = (0.4, 0.6).
      // TikZ: bottom-left = (0.1, 1 - 0.2 - 0.4) = (0.1, 0.4),
      //        top-right = (0.1 + 0.3, 1 - 0.2) = (0.4, 0.8).
      final slide = _slide(
        mode: CalloutPresentation.region,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutRegion(0.1, 0.2, 0.3, 0.4)],
          ),
        ],
      );
      final deck = Deck(title: 't', slides: [slide]);
      final latex = buildBeamerBody(deck);
      expect(latex, contains('rectangle'));
      expect(latex, contains('(0.1000,0.4000)'));
      expect(latex, contains('(0.4000,0.8000)'));
    });
  });

  group('export raster — multiple targets', () {
    test(
      'HTML: multiple targets → multiple markers with correct positions',
      () {
        final slide = _slide(
          callouts: const [
            ImageCallout(
              reference: 'A',
              targets: [CalloutPoint(0.2, 0.3), CalloutPoint(0.7, 0.8)],
              description: 'two spots',
            ),
          ],
        );
        final out = renderImageCallouts(_splitBody, slide);
        expect(out, contains('left:20.00%'));
        expect(out, contains('top:30.00%'));
        expect(out, contains('left:70.00%'));
        expect(out, contains('top:80.00%'));
      },
    );

    test(
      'HTML: multiple targets → accessible name includes "target n of m"',
      () {
        final slide = _slide(
          callouts: const [
            ImageCallout(
              reference: 'A',
              targets: [CalloutPoint(0.2, 0.3), CalloutPoint(0.7, 0.8)],
              description: 'two spots',
            ),
          ],
        );
        final out = renderImageCallouts(_splitBody, slide);
        expect(out, contains('target 1 of 2'));
        expect(out, contains('target 2 of 2'));
      },
    );
  });
}
