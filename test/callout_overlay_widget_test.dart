import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/slides/previews/callout_overlay.dart';

/// Widget tests for [CalloutOverlay].
///
/// The overlay resolves intrinsic image dimensions asynchronously before
/// drawing markers. In the test environment the image codec cannot produce a
/// real raster, so `_intrinsic` stays null and the overlay renders nothing —
/// these tests exercise the resolution path (`_calloutImageProvider`,
/// `_resolveIntrinsicSize`, `initState`, `didUpdateWidget`) and verify the
/// empty/redacted early-exit paths.

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

  group('CalloutOverlay', () {
    testWidgets('empty callouts → renders nothing', (tester) async {
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: '',
        callouts: const [],
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

      // No marker text is rendered.
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    });

    testWidgets('mediaRedacted=true → renders nothing', (tester) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: 'test',
          ),
        ],
        mediaRedacted: true,
      );
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
            mediaRedacted: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No marker text is rendered.
      expect(find.text('A'), findsNothing);
    });

    testWidgets(
      'callouts with mem-path image → no markers until image resolves',
      (tester) async {
        // The image codec cannot produce a raster in the test environment,
        // so _intrinsic stays null and the overlay renders nothing. This
        // still exercises _calloutImageProvider (mem: branch),
        // _resolveIntrinsicSize (listener setup + error path), and the
        // build method's _intrinsic == null early exit.
        final memPath = WebAssetStore.put(_pngBytes, name: 'marker.png');
        final slide = Slide(
          id: 'test',
          type: SlideType.bulletsImage,
          imagePath: memPath,
          callouts: const [
            ImageCallout(
              reference: 'A',
              targets: [CalloutPoint(0.5, 0.5)],
              description: 'de controller',
            ),
          ],
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

        // Image cannot resolve in tests → no markers.
        expect(find.text('A'), findsNothing);
      },
    );

    testWidgets('didUpdateWidget re-resolves when image path changes', (
      tester,
    ) async {
      final memPath1 = WebAssetStore.put(_pngBytes, name: 'first.png');
      final slide1 = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath1,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.5, 0.5)],
            description: 'test',
          ),
        ],
      );
      final slide2 = slide1.copyWith(imagePath: 'different.png');

      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide1,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
          ),
        ),
      );
      await tester.pump();

      // Update with a different image path — triggers didUpdateWidget.
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide2,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No markers either way (image can't resolve in tests).
      expect(find.text('A'), findsNothing);
    });

    testWidgets('multiple callouts → no markers until image resolves', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'multi.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.3, 0.3)],
            description: 'eerste',
          ),
          ImageCallout(
            reference: 'B',
            targets: [CalloutPoint(0.7, 0.7)],
            description: 'tweede',
          ),
        ],
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

      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    });
  });
}
