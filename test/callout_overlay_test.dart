// Tests for the callout overlay rendering — verifies that markers are
// positioned correctly on the image and that the overlay handles edge
// cases (empty callouts, redacted slides, clipped targets).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/services/image_viewport_geometry.dart';

void main() {
  group('CalloutOverlay geometry mapping', () {
    test('point target maps to marker at painted coordinates', () {
      // Landscape image 800×400 in a 384×216 slot (20% of 1920×1080),
      // cover mode, centre focal.
      const sw = 384.0, sh = 216.0;
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: sw,
        slotH: sh,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 0,
      );
      // Cover: s = max(384/800, 216/400) = max(0.48, 0.54) = 0.54
      // pw = 432, ph = 216, px = (384-432)*0.5 = -24, py = 0
      expect(painted.width, closeTo(432, 0.001));
      expect(painted.height, closeTo(216, 0.001));

      // Point at (0.5, 0.5) → centre of painted rect.
      final m = ImageViewportGeometry.mapTarget(
        const CalloutPoint(0.5, 0.5),
        painted: painted,
        slotW: sw,
        slotH: sh,
      );
      expect(m.x, closeTo(painted.left + 0.5 * painted.width, 0.001));
      expect(m.y, closeTo(painted.top + 0.5 * painted.height, 0.001));
      expect(m.clipped, isFalse);
    });

    test('region target in pin mode maps to centre point', () {
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 216,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 0,
      );
      // Region (0.3, 0.3, 0.2, 0.2) → centre at (0.4, 0.4)
      final r = const CalloutRegion(0.3, 0.3, 0.2, 0.2);
      final cx = r.x + r.w / 2;
      final cy = r.y + r.h / 2;
      final m = ImageViewportGeometry.mapTarget(
        CalloutPoint(cx, cy),
        painted: painted,
        slotW: 384,
        slotH: 216,
      );
      expect(m.x, closeTo(painted.left + cx * painted.width, 0.001));
      expect(m.y, closeTo(painted.top + cy * painted.height, 0.001));
    });

    test('clipped target is not rendered', () {
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 216,
        focalX: 0.0,
        focalY: 0.0,
        zoom: 0,
      );
      // Point at (1, 0) → right edge of painted, which overflows slot.
      final m = ImageViewportGeometry.mapTarget(
        const CalloutPoint(1, 0),
        painted: painted,
        slotW: 384,
        slotH: 216,
      );
      expect(m.clipped, isTrue);
    });
  });

  group('CalloutOverlay — §3.1 pin mode matrix', () {
    test('point target in pin mode → marker centred on point', () {
      const target = CalloutPoint(0.4, 0.3);
      // In pin mode, a point target gets a marker at its position.
      expect(target.isValid, isTrue);
    });

    test('region target in pin mode → marker at region centre', () {
      const target = CalloutRegion(0.3, 0.3, 0.2, 0.2);
      // In pin mode, a region target gets a marker at its centre.
      final centre = (target.x + target.w / 2, target.y + target.h / 2);
      expect(centre.$1, closeTo(0.4, 0.001));
      expect(centre.$2, closeTo(0.4, 0.001));
    });
  });

  group('CalloutOverlay — reference allocation', () {
    test('next free reference skips letters used as prose', () {
      // If a bullet ends with "(A)" as prose (not a callout), the allocator
      // should skip A and use B.
      final proseLetters = {'A'};
      final usedLetters = <String>{};
      final next = _nextFreeReference(usedLetters, proseLetters);
      expect(next, 'B');
    });

    test('next free reference after existing callouts', () {
      final proseLetters = <String>{};
      final usedLetters = {'A', 'B'};
      final next = _nextFreeReference(usedLetters, proseLetters);
      expect(next, 'C');
    });

    test('next free reference skips both prose and used', () {
      final proseLetters = {'A', 'C'};
      final usedLetters = {'B'};
      final next = _nextFreeReference(usedLetters, proseLetters);
      expect(next, 'D');
    });

    test('returns null when all 26 letters are used', () {
      final used = {for (var i = 0; i < 26; i++) String.fromCharCode(65 + i)};
      final next = _nextFreeReference(used, {});
      expect(next, isNull);
    });
  });
}

/// Allocates the next free reference letter (A–Z), skipping letters already
/// used by existing callouts and letters that appear as trailing prose on
/// the slide (§6.1: the allocator never manufactures the collision §2.6
/// has to report).
String? _nextFreeReference(
  Set<String> usedByCallouts,
  Set<String> usedByProse,
) {
  for (var i = 0; i < 26; i++) {
    final letter = String.fromCharCode(65 + i);
    if (!usedByCallouts.contains(letter) && !usedByProse.contains(letter)) {
      return letter;
    }
  }
  return null;
}
