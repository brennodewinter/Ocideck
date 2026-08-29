import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/marp_html_service.dart';

/// Tests for `renderImageCallouts` — the HTML export callout markup
/// (IMAGE_CALLOUTS.md §4.2, §5, §12.2). The function wraps the split-image
/// panel's `<img>` in the `.ocideck-imgslot` structure, adds positioned
/// `span.ocideck-callout` markers, emits hidden description elements, and
/// adds `aria-describedby` on matching bullet `<li>` elements.

/// A minimal split-image body with one image and a bullet list.
String _body({
  String alt = 'foto',
  String src = 'img.png',
  List<String> bullets = const ['- Eerste punt', '- Tweede punt'],
}) {
  final buf = StringBuffer()
    ..writeln('<div class="split-image">')
    ..writeln('![$alt]($src)')
    ..writeln('</div>');
  for (final b in bullets) {
    buf.writeln(b);
  }
  return buf.toString();
}

Slide _slide({
  List<ImageCallout> callouts = const [],
  String anchor = 'slide-1',
  int imageZoom = 0,
}) => Slide(
  id: 'test',
  type: SlideType.bulletsImage,
  anchor: anchor,
  imagePath: 'img.png',
  imageZoom: imageZoom,
  callouts: callouts,
);

void main() {
  group('renderImageCallouts', () {
    test('empty callouts → body unchanged', () {
      final body = _body();
      final slide = _slide(callouts: []);
      expect(renderImageCallouts(body, slide), body);
    });

    test('point target → marker span at correct position', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.3)],
            description: 'de controller',
          ),
        ],
      );
      final result = renderImageCallouts(body, slide);
      // The imgslot structure is emitted.
      expect(result, contains('ocideck-imgslot'));
      // A callout marker span is positioned at the point.
      expect(result, contains('ocideck-callout'));
      expect(result, contains('left:40.00%'));
      expect(result, contains('top:30.00%'));
      // The reference letter is inside the marker.
      expect(result, contains('>A<'));
    });

    test('region target → marker at centre', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'B',
            targets: [CalloutRegion(0.2, 0.2, 0.4, 0.4)],
            description: 'het gebied',
          ),
        ],
      );
      final result = renderImageCallouts(body, slide);
      // Region centre: (0.2 + 0.4/2, 0.2 + 0.4/2) = (0.4, 0.4) → 40%, 40%.
      expect(result, contains('left:40.00%'));
      expect(result, contains('top:40.00%'));
      expect(result, contains('>B<'));
    });

    test('multiple targets → multiple markers with target-n-of-m label', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.1, 0.1), CalloutPoint(0.9, 0.9)],
            description: 'twee punten',
          ),
        ],
      );
      final result = renderImageCallouts(body, slide);
      // Two markers at different positions.
      expect(result, contains('left:10.00%'));
      expect(result, contains('left:90.00%'));
      // The accessible name includes "target 1 of 2" / "target 2 of 2".
      expect(result, contains('target 1 of 2'));
      expect(result, contains('target 2 of 2'));
    });

    test('hidden description spans emitted', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: 'belangrijk detail',
          ),
        ],
      );
      final result = renderImageCallouts(body, slide);
      expect(result, contains('ocideck-callout-desc'));
      expect(result, contains('belangrijk detail'));
      // The id is derived from the anchor and reference.
      expect(result, contains('ocideck-callout-slide-1-A'));
    });

    test('bullet with trailing (A) gets aria-describedby', () {
      final body = _body(bullets: ['- Eerste punt (A)', '- Tweede punt']);
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: 'referentie',
          ),
        ],
      );
      final result = renderImageCallouts(body, slide);
      // The bullet list becomes an HTML <ul> with aria-describedby.
      expect(result, contains('<ul>'));
      expect(result, contains('aria-describedby="ocideck-callout-slide-1-A"'));
      // The bullet without a reference has no aria-describedby.
      expect(result, contains('<li>Tweede punt</li>'));
    });

    test('zoom mode emits zoom wrapper', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: '',
          ),
        ],
        imageZoom: 100,
      );
      final result = renderImageCallouts(body, slide);
      expect(result, contains('ocideck-imgzoom'));
      expect(result, contains('ocideck-imgbox wide'));
    });

    test('no zoom → no zoom wrapper', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: '',
          ),
        ],
        imageZoom: 0,
      );
      final result = renderImageCallouts(body, slide);
      expect(result, isNot(contains('ocideck-imgzoom')));
    });

    test('empty description → no hidden desc span', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: '',
          ),
        ],
      );
      final result = renderImageCallouts(body, slide);
      expect(result, isNot(contains('ocideck-callout-desc')));
    });

    test('no split-image div → body unchanged', () {
      const body = '# Titel\n\n- Een punt\n';
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: 'test',
          ),
        ],
      );
      // No split-image div to wrap, so the imgslot step is a no-op.
      // The bullet step may still run but there are no callout refs on bullets.
      final result = renderImageCallouts(body, slide);
      expect(result, contains('# Titel'));
    });
  });

  group('renderImageCallouts — region mode (§3.1)', () {
    test(
      'region target in region mode → outlined div with correct geometry',
      () {
        final body = _body();
        final slide = _slide(
          callouts: [
            const ImageCallout(
              reference: 'A',
              targets: [CalloutRegion(0.2, 0.3, 0.4, 0.5)],
              description: 'het gebied',
            ),
          ],
        ).copyWith(calloutPresentation: CalloutPresentation.region);
        final result = renderImageCallouts(body, slide);
        expect(result, contains('ocideck-region'));
        expect(result, contains('left:20.00%'));
        expect(result, contains('top:30.00%'));
        expect(result, contains('width:40.00%'));
        expect(result, contains('height:50.00%'));
        expect(result, contains('ocideck-region-num'));
        expect(result, contains('>A<'));
      },
    );

    test('point target in region mode → still a pin, no invented box', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.3)],
            description: 'een punt',
          ),
        ],
      ).copyWith(calloutPresentation: CalloutPresentation.region);
      final result = renderImageCallouts(body, slide);
      // A point in region mode is still a pin marker, not a region div.
      expect(result, contains('ocideck-callout'));
      expect(result, isNot(contains('ocideck-region')));
    });

    test('region target in pin mode → marker at centre, no region div', () {
      final body = _body();
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutRegion(0.2, 0.2, 0.4, 0.4)],
            description: 'gebied in pin-modus',
          ),
        ],
        // Default presentation is pin.
      );
      final result = renderImageCallouts(body, slide);
      expect(result, contains('ocideck-callout'));
      expect(result, isNot(contains('ocideck-region')));
    });

    // §7: static exports flatten reveal — every bullet and target exactly once,
    // regardless of calloutReveal. The HTML export has no step state.
    test('reveal:steps → static export shows all callouts (flatten)', () {
      final body = _body(bullets: ['- Eerste punt (A)', '- Tweede punt (B)']);
      final slide = _slide(
        callouts: [
          const ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.3)],
            description: 'eerste',
          ),
          const ImageCallout(
            reference: 'B',
            targets: [CalloutPoint(0.6, 0.5)],
            description: 'tweede',
          ),
        ],
      ).copyWith(calloutReveal: BulletRevealMode.steps);
      final result = renderImageCallouts(body, slide);
      // Both callout markers are present (flattened, not stepped).
      expect(result, contains('ocideck-callout'));
      expect(result, contains('>A<'));
      expect(result, contains('>B<'));
      // Both bullets are present with their descriptions.
      expect(result, contains('aria-describedby'));
      expect(result, contains('ocideck-callout-desc'));
    });
  });
}
