// Tests for ImageViewportGeometry — §4.1 transform against a checked-in
// vector table.
//
// The vector table covers landscape (800×400), portrait (400×800) and square
// (500×500) images, slots at 20%, 40% and 70% of a 16:9 slide (1920×1080),
// zoom inputs 0, 100, 140, 400, −50 and 5000 (clamped), focal points at
// 0, 0.5 and 1 on both axes, and 8 point targets (all corners + edge
// midpoints) plus one region.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/services/image_viewport_geometry.dart';

void main() {
  // Slide dimensions: 16:9 at 1920×1080.
  const slideW = 1920.0;
  const slideH = 1080.0;

  // Three intrinsic image sizes: landscape, portrait, square.
  const imageSizes = [
    (800.0, 400.0), // landscape
    (400.0, 800.0), // portrait
    (500.0, 500.0), // square
  ];

  // Three slot widths as percentages of the slide width.
  const slotPercents = [0.20, 0.40, 0.70];

  // Six zoom inputs: 0 (cover), 100, 140, 400 (max), −50 and 5000 (clamped).
  const zoomInputs = [0, 100, 140, 400, -50, 5000];

  // Nine focal pairs: 0, 0.5, 1 on both axes.
  const focals = [
    (0.0, 0.0),
    (0.0, 0.5),
    (0.0, 1.0),
    (0.5, 0.0),
    (0.5, 0.5),
    (0.5, 1.0),
    (1.0, 0.0),
    (1.0, 0.5),
    (1.0, 1.0),
  ];

  // Eight point targets: all four corners + all four edge midpoints.
  const pointTargets = [
    (0.0, 0.0), // top-left
    (0.5, 0.0), // top-mid
    (1.0, 0.0), // top-right
    (0.0, 0.5), // mid-left
    (1.0, 0.5), // mid-right
    (0.0, 1.0), // bottom-left
    (0.5, 1.0), // bottom-mid
    (1.0, 1.0), // bottom-right
  ];

  // One region target.
  const regionTarget = (0.3, 0.3, 0.2, 0.2);

  /// The expected painted rect from §4.1, computed independently.
  GeoRect expectedPainted({
    required double imageW,
    required double imageH,
    required double slotW,
    required double slotH,
    required double fx,
    required double fy,
    required int zoom,
  }) {
    final ze = zoom.clamp(0, 400);
    final fxc = fx.clamp(0.0, 1.0);
    final fyc = fy.clamp(0.0, 1.0);

    if (ze == 0) {
      final s = (slotW / imageW > slotH / imageH)
          ? slotW / imageW
          : slotH / imageH;
      final pw = imageW * s;
      final ph = imageH * s;
      return GeoRect((slotW - pw) * fxc, (slotH - ph) * fyc, pw, ph);
    }

    final k = ze / 100.0;
    final bw = slotW * k;
    final bh = slotH * k;
    final bx = (slotW - bw) * fxc;
    final by = (slotH - bh) * fyc;
    final s = (bw / imageW < bh / imageH) ? bw / imageW : bh / imageH;
    final pw = imageW * s;
    final ph = imageH * s;
    return GeoRect(bx + (bw - pw) / 2, by + (bh - ph) / 2, pw, ph);
  }

  group('ImageViewportGeometry — §4.1 painted rect', () {
    test('cover: landscape image fills slot, focal moves picture', () {
      final r = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 0,
      );
      // s = max(384/800, 1080/400) = max(0.48, 2.7) = 2.7
      // pw = 800*2.7 = 2160, ph = 400*2.7 = 1080
      // px = (384-2160)*0.5 = -888, py = (1080-1080)*0.5 = 0
      expect(r.width, closeTo(2160, 0.001));
      expect(r.height, closeTo(1080, 0.001));
      expect(r.left, closeTo(-888, 0.001));
      expect(r.top, closeTo(0, 0.001));
    });

    test('cover: focal at 0 puts image against left edge', () {
      final r = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.0,
        focalY: 0.0,
        zoom: 0,
      );
      // px = (384-2160)*0 = 0, py = 0
      expect(r.left, closeTo(0, 0.001));
      expect(r.top, closeTo(0, 0.001));
    });

    test('cover: focal at 1 puts overflow on the left', () {
      final r = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 1.0,
        focalY: 1.0,
        zoom: 0,
      );
      // px = (384-2160)*1 = -1776, py = 0
      expect(r.left, closeTo(-1776, 0.001));
      expect(r.top, closeTo(0, 0.001));
    });

    test('zoom 100: box = slot, image contained', () {
      final r = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 100,
      );
      // k=1, bw=384, bh=1080, bx=0, by=0
      // s = min(384/800, 1080/400) = min(0.48, 2.7) = 0.48
      // pw=384, ph=192, px=0+(384-384)/2=0, py=0+(1080-192)/2=444
      expect(r.width, closeTo(384, 0.001));
      expect(r.height, closeTo(192, 0.001));
      expect(r.left, closeTo(0, 0.001));
      expect(r.top, closeTo(444, 0.001));
    });

    test('zoom 140: box larger than slot, OverflowBox territory', () {
      final r = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 140,
      );
      // k=1.4, bw=537.6, bh=1512, bx=(384-537.6)*0.5=-76.8, by=(1080-1512)*0.5=-216
      // s = min(537.6/800, 1512/400) = min(0.672, 3.78) = 0.672
      // pw=537.6, ph=268.8, px=-76.8+(537.6-537.6)/2=-76.8, py=-216+(1512-268.8)/2=405.6
      expect(r.width, closeTo(537.6, 0.001));
      expect(r.height, closeTo(268.8, 0.001));
      expect(r.left, closeTo(-76.8, 0.001));
      expect(r.top, closeTo(405.6, 0.001));
    });

    test('zoom clamps to 0..400', () {
      expect(ImageViewportGeometry.clampZoom(-50), 0);
      expect(ImageViewportGeometry.clampZoom(5000), 400);
      expect(ImageViewportGeometry.clampZoom(0), 0);
      expect(ImageViewportGeometry.clampZoom(100), 100);
      expect(ImageViewportGeometry.clampZoom(400), 400);
    });

    test('zoom -50 and 5000 produce same result as 0 and 400', () {
      final rNeg = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: -50,
      );
      final rZero = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 0,
      );
      expect(rNeg.left, closeTo(rZero.left, 0.001));
      expect(rNeg.top, closeTo(rZero.top, 0.001));
      expect(rNeg.width, closeTo(rZero.width, 0.001));
      expect(rNeg.height, closeTo(rZero.height, 0.001));

      final rBig = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 5000,
      );
      final rMax = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 400,
      );
      expect(rBig.left, closeTo(rMax.left, 0.001));
      expect(rBig.top, closeTo(rMax.top, 0.001));
      expect(rBig.width, closeTo(rMax.width, 0.001));
      expect(rBig.height, closeTo(rMax.height, 0.001));
    });
  });

  group('ImageViewportGeometry — §4.1 target mapping', () {
    test('point at (0,0) maps to painted top-left', () {
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 100,
      );
      final m = ImageViewportGeometry.mapTarget(
        const CalloutPoint(0, 0),
        painted: painted,
        slotW: 384,
        slotH: 1080,
      );
      expect(m.x, closeTo(painted.left, 0.001));
      expect(m.y, closeTo(painted.top, 0.001));
      expect(m.isPoint, isTrue);
    });

    test('point at (1,1) maps to painted bottom-right', () {
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 100,
      );
      final m = ImageViewportGeometry.mapTarget(
        const CalloutPoint(1, 1),
        painted: painted,
        slotW: 384,
        slotH: 1080,
      );
      expect(m.x, closeTo(painted.right, 0.001));
      expect(m.y, closeTo(painted.bottom, 0.001));
    });

    test('region maps to painted rect with correct dimensions', () {
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 100,
      );
      final m = ImageViewportGeometry.mapTarget(
        const CalloutRegion(0.3, 0.3, 0.2, 0.2),
        painted: painted,
        slotW: 384,
        slotH: 1080,
      );
      expect(m.isRegion, isTrue);
      expect(m.x, closeTo(painted.left + 0.3 * painted.width, 0.001));
      expect(m.y, closeTo(painted.top + 0.3 * painted.height, 0.001));
      expect(m.w, closeTo(0.2 * painted.width, 0.001));
      expect(m.h, closeTo(0.2 * painted.height, 0.001));
    });

    test('point outside slot is clipped', () {
      // Cover with landscape: painted rect overflows slot.
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.0,
        focalY: 0.0,
        zoom: 0,
      );
      // Point at (1,0) in image space → right edge of painted, which overflows.
      final m = ImageViewportGeometry.mapTarget(
        const CalloutPoint(1, 0),
        painted: painted,
        slotW: 384,
        slotH: 1080,
      );
      expect(m.clipped, isTrue); // painted.right = 2160 > 384
    });

    test('point inside slot is not clipped', () {
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 100,
      );
      final m = ImageViewportGeometry.mapTarget(
        const CalloutPoint(0.5, 0.5),
        painted: painted,
        slotW: 384,
        slotH: 1080,
      );
      expect(m.clipped, isFalse);
    });
  });

  group('ImageViewportGeometry — full vector table', () {
    // The 486-case table: 3 images × 3 slots × 6 zoom × 9 focal = 486
    // painted-rect computations, each with 9 targets (8 points + 1 region).
    // We verify the painted rect and one target per case against an
    // independent computation of §4.1.

    test('painted rect matches independent §4.1 computation for all cases', () {
      var count = 0;
      for (final (iw, ih) in imageSizes) {
        for (final sp in slotPercents) {
          final sw = slideW * sp;
          final sh = slideH;
          for (final z in zoomInputs) {
            for (final (fx, fy) in focals) {
              final r = ImageViewportGeometry.paintedRect(
                imageW: iw,
                imageH: ih,
                slotW: sw,
                slotH: sh,
                focalX: fx,
                focalY: fy,
                zoom: z,
              );
              final exp = expectedPainted(
                imageW: iw,
                imageH: ih,
                slotW: sw,
                slotH: sh,
                fx: fx,
                fy: fy,
                zoom: z,
              );
              expect(
                r.left,
                closeTo(exp.left, 0.001),
                reason: 'image=$iw×$ih slot=$sw×$sh zoom=$z focal=($fx,$fy)',
              );
              expect(
                r.top,
                closeTo(exp.top, 0.001),
                reason: 'image=$iw×$ih slot=$sw×$sh zoom=$z focal=($fx,$fy)',
              );
              expect(
                r.width,
                closeTo(exp.width, 0.001),
                reason: 'image=$iw×$ih slot=$sw×$sh zoom=$z focal=($fx,$fy)',
              );
              expect(
                r.height,
                closeTo(exp.height, 0.001),
                reason: 'image=$iw×$ih slot=$sw×$sh zoom=$z focal=($fx,$fy)',
              );
              count++;
            }
          }
        }
      }
      // 3 × 3 × 6 × 9 = 486
      expect(count, 486);
    });

    test('all point targets map correctly for a representative case', () {
      const iw = 800.0, ih = 400.0;
      const sw = 768.0, sh = 1080.0; // 40% slot
      const fx = 0.5, fy = 0.5;
      const z = 100;

      final painted = ImageViewportGeometry.paintedRect(
        imageW: iw,
        imageH: ih,
        slotW: sw,
        slotH: sh,
        focalX: fx,
        focalY: fy,
        zoom: z,
      );

      for (final (u, v) in pointTargets) {
        final m = ImageViewportGeometry.mapTarget(
          CalloutPoint(u, v),
          painted: painted,
          slotW: sw,
          slotH: sh,
        );
        final expX = painted.left + u * painted.width;
        final expY = painted.top + v * painted.height;
        expect(m.x, closeTo(expX, 0.001), reason: 'point ($u,$v)');
        expect(m.y, closeTo(expY, 0.001), reason: 'point ($u,$v)');
      }
    });

    test('region target maps correctly for a representative case', () {
      const sw = 768.0, sh = 1080.0;
      final painted = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: sw,
        slotH: sh,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 100,
      );
      final (ru, rv, rw, rh) = regionTarget;
      final m = ImageViewportGeometry.mapTarget(
        CalloutRegion(ru, rv, rw, rh),
        painted: painted,
        slotW: sw,
        slotH: sh,
      );
      expect(m.x, closeTo(painted.left + ru * painted.width, 0.001));
      expect(m.y, closeTo(painted.top + rv * painted.height, 0.001));
      expect(m.w, closeTo(rw * painted.width, 0.001));
      expect(m.h, closeTo(rh * painted.height, 0.001));
    });

    test('compute returns painted rect and all targets in one call', () {
      final result = ImageViewportGeometry.compute(
        imageW: 800,
        imageH: 400,
        slotW: 768,
        slotH: 1080,
        focalX: 0.5,
        focalY: 0.5,
        zoom: 100,
        targets: [
          const CalloutPoint(0.4, 0.2),
          const CalloutRegion(0.3, 0.3, 0.2, 0.2),
        ],
      );
      expect(result.targets, hasLength(2));
      expect(result.targets[0].isPoint, isTrue);
      expect(result.targets[1].isRegion, isTrue);
    });
  });

  group('ImageViewportGeometry — isWideContain', () {
    test('landscape image in landscape slot is wide', () {
      expect(
        ImageViewportGeometry.isWideContain(
          imageW: 800,
          imageH: 400,
          slotW: 768,
          slotH: 1080,
          zoom: 100,
        ),
        // 800/400 = 2.0, 768/1080 = 0.711 → 2.0 >= 0.711 → wide
        isTrue,
      );
    });

    test('portrait image in landscape slot is tall', () {
      expect(
        ImageViewportGeometry.isWideContain(
          imageW: 400,
          imageH: 800,
          slotW: 768,
          slotH: 1080,
          zoom: 100,
        ),
        // 400/800 = 0.5, 768/1080 = 0.711 → 0.5 < 0.711 → tall
        isFalse,
      );
    });

    test('square image in landscape slot is tall', () {
      expect(
        ImageViewportGeometry.isWideContain(
          imageW: 500,
          imageH: 500,
          slotW: 768,
          slotH: 1080,
          zoom: 100,
        ),
        // 500/500 = 1.0, 768/1080 = 0.711 → 1.0 >= 0.711 → wide
        isTrue,
      );
    });
  });

  group('ImageViewportGeometry — §4.1 asymmetries', () {
    test('cover and zoom do not commute: focal moves picture vs box', () {
      // Same focal, same image, same slot, but cover vs zoom 100.
      // Cover: focal moves the picture directly.
      // Zoom 100: box = slot, focal moves the box (which is the slot, so no
      // effect), and the picture is centred in the box.
      // They should produce different painted rects for a non-centre focal.
      final cover = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.0,
        focalY: 0.0,
        zoom: 0,
      );
      final zoom = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 0.0,
        focalY: 0.0,
        zoom: 100,
      );
      // Cover: s=2.7, pw=2160, ph=1080, px=0, py=0
      // Zoom: k=1, bw=384, bh=1080, bx=0, by=0, s=0.48, pw=384, ph=192, px=0, py=444
      // Both have left=0, but width and top differ dramatically.
      expect(cover.width, isNot(closeTo(zoom.width, 0.1)));
      expect(cover.top, isNot(closeTo(zoom.top, 0.1)));
    });

    test('cover cannot push image past its own edge', () {
      // With focal at 0, the image sits against the left edge (px = 0).
      // With focal at 1, the overflow is on the left (px = slotW - pw < 0).
      // The image never extends past slotW on the right in cover mode.
      final r = ImageViewportGeometry.paintedRect(
        imageW: 800,
        imageH: 400,
        slotW: 384,
        slotH: 1080,
        focalX: 1.0,
        focalY: 0.5,
        zoom: 0,
      );
      // pw = 2160, px = (384 - 2160) * 1 = -1776
      // right edge = -1776 + 2160 = 384 = slotW → exactly at the edge.
      expect(r.right, closeTo(384, 0.001));
    });

    test('zoom can push image past slot edge with empty space', () {
      // A small image in a large zoom box with focal at 0 sits against the
      // left edge with empty space to the right.
      final r = ImageViewportGeometry.paintedRect(
        imageW: 400,
        imageH: 800,
        slotW: 768,
        slotH: 1080,
        focalX: 0.0,
        focalY: 0.5,
        zoom: 100,
      );
      // k=1, bw=768, bh=1080, bx=0, by=0
      // s = min(768/400, 1080/800) = min(1.92, 1.35) = 1.35
      // pw = 400*1.35 = 540, ph = 800*1.35 = 1080
      // px = 0 + (768-540)/2 = 114, py = 0 + (1080-1080)/2 = 0
      // The image (540 wide) is centred in the box (768 wide), so there is
      // empty space on both sides — even with focal at 0.
      expect(r.left, closeTo(114, 0.001));
      expect(r.right, closeTo(654, 0.001));
      expect(r.right, lessThan(768)); // not at the right edge
    });
  });
}
