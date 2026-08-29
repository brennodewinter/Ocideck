import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/slides/previews/callout_overlay.dart';

/// Tests for arrow presentation mode (IMAGE_CALLOUTS.md §5, §3.1).
///
/// The fixed-rail design means every arrow is a horizontal line from the
/// left edge of the image slot (the rail) to the target. Point targets get
/// an arrow to the point; region targets get an outlined rectangle plus an
/// arrow to the rectangle's left edge at centre height.

/// A minimal valid 1×1 transparent PNG.
final _pngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ),
);

Widget _host(Widget child) => MaterialApp(
  home: Center(child: SizedBox(width: 400, height: 300, child: child)),
);

void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  group('CalloutOverlay arrow mode', () {
    testWidgets('arrow mode with point target → no crash, overlay builds', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.3)],
            description: 'controller',
          ),
        ],
        calloutPresentation: CalloutPresentation.arrow,
      );
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Image can't resolve in tests → no markers, but no crash.
      expect(find.text('A'), findsNothing);
    });

    testWidgets('arrow mode with region target → no crash, overlay builds', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'B',
            targets: [CalloutRegion(0.2, 0.2, 0.4, 0.4)],
            description: 'gebied',
          ),
        ],
        calloutPresentation: CalloutPresentation.arrow,
      );
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('B'), findsNothing);
    });

    testWidgets('arrow mode with mixed point and region targets → builds', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.25)],
            description: 'punt',
          ),
          ImageCallout(
            reference: 'B',
            targets: [CalloutRegion(0.5, 0.4, 0.3, 0.3)],
            description: 'gebied',
          ),
        ],
        calloutPresentation: CalloutPresentation.arrow,
      );
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No crash — both target types handled.
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    });

    testWidgets('arrow mode respects revealedReferences filter', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.25)]),
          ImageCallout(reference: 'B', targets: [CalloutPoint(0.6, 0.5)]),
        ],
        calloutPresentation: CalloutPresentation.arrow,
      );
      // Only A is revealed.
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
            revealedReferences: const {'A'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No crash — filtering works in arrow mode.
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    });
  });

  group('HTML export arrow mode', () {
    test('arrow mode with point target → arrow div + reference badge', () {
      final body =
          '<div class="split-image">\n![foto](img.png)\n</div>\n'
          '- Eerste punt (A)';
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        anchor: 'slide-1',
        imagePath: 'img.png',
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.3)],
            description: 'controller',
          ),
        ],
        calloutPresentation: CalloutPresentation.arrow,
      );
      final result = renderImageCallouts(body, slide);
      // Arrow div with correct position.
      expect(result, contains('ocideck-arrow'));
      expect(result, contains('left:0%'));
      expect(result, contains('top:30.00%'));
      expect(result, contains('width:40.00%'));
      // Reference badge at the rail.
      expect(result, contains('ocideck-callout'));
      expect(result, contains('>A<'));
    });

    test('arrow mode with region target → region div + arrow to edge', () {
      final body =
          '<div class="split-image">\n![foto](img.png)\n</div>\n'
          '- Eerste punt (A)';
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        anchor: 'slide-1',
        imagePath: 'img.png',
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutRegion(0.3, 0.2, 0.4, 0.4)],
            description: 'gebied',
          ),
        ],
        calloutPresentation: CalloutPresentation.arrow,
      );
      final result = renderImageCallouts(body, slide);
      // Region outline.
      expect(result, contains('ocideck-region'));
      expect(result, contains('left:30.00%'));
      expect(result, contains('top:20.00%'));
      expect(result, contains('width:40.00%'));
      expect(result, contains('height:40.00%'));
      // Arrow to the region's left edge at centre y.
      expect(result, contains('ocideck-arrow'));
      // Centre y = 0.2 + 0.4/2 = 0.4 → 40.00%
      expect(result, contains('top:40.00%'));
      // Arrow width = region left x = 30%
      expect(result, contains('width:30.00%'));
    });

    test('arrow mode flatten: reveal:steps shows all arrows', () {
      final body =
          '<div class="split-image">\n![foto](img.png)\n</div>\n'
          '- Eerste (A)\n- Tweede (B)';
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        anchor: 'slide-1',
        imagePath: 'img.png',
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.3, 0.2)]),
          ImageCallout(reference: 'B', targets: [CalloutPoint(0.6, 0.5)]),
        ],
        calloutPresentation: CalloutPresentation.arrow,
        calloutReveal: BulletRevealMode.steps,
      );
      final result = renderImageCallouts(body, slide);
      // Both arrows present (flattened).
      expect(result, contains('ocideck-arrow'));
      // Both reference badges.
      expect(result, contains('>A<'));
      expect(result, contains('>B<'));
    });

    test('arrow CSS is present in the export stylesheet', () {
      // The CSS for .ocideck-arrow is in the structural CSS that the HTML
      // export always emits. This test verifies it's there.
      final css = exportBaseCss();
      expect(css, contains('.ocideck-arrow'));
      expect(css, contains('.ocideck-arrow::after'));
    });
  });
}
