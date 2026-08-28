// The one geometry contract for image callouts — IMAGE_CALLOUTS.md §4.1.
//
// Flutter-free: takes intrinsic image size, slot size, zoom and focal point,
// returns the painted image rectangle and mapped target geometry. Flutter,
// LaTeX and the editor's hit-testing call it. The CSS surface is checked
// against it via the shared vector table (§4.2).
//
// Every surface clamps zoom to 0..400 identically (§4.3). Cover (ze == 0)
// and zoom (ze > 0) are two different operations that do not commute:
// cover moves the picture by the focal point; zoom moves the box and centres
// the picture inside it.

import '../models/image_callout.dart';

/// A minimal rectangle — no Flutter dependency.
class GeoRect {
  final double left, top, width, height;
  const GeoRect(this.left, this.top, this.width, this.height);
  double get right => left + width;
  double get bottom => top + height;
  @override
  String toString() => 'GeoRect($left, $top, $width, $height)';
}

/// A mapped target in slot pixels, with clipping status.
class MappedTarget {
  final CalloutTarget source;

  /// Top-left in slot pixels.
  final double x, y;

  /// Width and height for a region; zero for a point.
  final double w, h;

  /// True when the mapped target leaves the slot `0..slotW × 0..slotH`.
  final bool clipped;

  const MappedTarget._({
    required this.source,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.clipped,
  });

  bool get isPoint => source is CalloutPoint;
  bool get isRegion => source is CalloutRegion;
}

/// The painted image rectangle plus mapped targets.
class ImageGeometryResult {
  /// The painted image rectangle in slot pixels.
  final GeoRect paintedRect;

  /// Mapped targets in slot coordinates, one per input target.
  final List<MappedTarget> targets;

  const ImageGeometryResult({required this.paintedRect, required this.targets});
}

/// The shared geometry contract (§4.1).
///
/// [compute] takes intrinsic image size, slot size, zoom and focal point and
/// returns the painted image rectangle plus mapped targets. The formula is
/// exactly §4.1 — see the design doc for the two asymmetries that are easy to
/// get wrong.
class ImageViewportGeometry {
  const ImageViewportGeometry();

  /// Clamp zoom to 0..400 (§4.3: every surface clamps identically).
  static int clampZoom(int z) => z.clamp(0, 400);

  /// Compute the painted image rectangle for the given inputs.
  ///
  /// Returns `px, py, pw, ph` in slot pixels.
  static GeoRect paintedRect({
    required double imageW,
    required double imageH,
    required double slotW,
    required double slotH,
    required double focalX,
    required double focalY,
    required int zoom,
  }) {
    final ze = clampZoom(zoom);
    final fx = focalX.clamp(0.0, 1.0);
    final fy = focalY.clamp(0.0, 1.0);

    if (ze == 0) {
      // Cover: scale to fill, focal moves the picture.
      final s = _max(slotW / imageW, slotH / imageH);
      final pw = imageW * s;
      final ph = imageH * s;
      final px = (slotW - pw) * fx;
      final py = (slotH - ph) * fy;
      return GeoRect(px, py, pw, ph);
    }

    // Zoom: a box of ze% of the slot, image contained in it.
    final k = ze / 100.0;
    final bw = slotW * k;
    final bh = slotH * k;
    final bx = (slotW - bw) * fx;
    final by = (slotH - bh) * fy;
    final s = _min(bw / imageW, bh / imageH);
    final pw = imageW * s;
    final ph = imageH * s;
    final px = bx + (bw - pw) / 2;
    final py = by + (bh - ph) / 2;
    return GeoRect(px, py, pw, ph);
  }

  /// Map a single target from image space (0..1) to slot pixels.
  static MappedTarget mapTarget(
    CalloutTarget target, {
    required GeoRect painted,
    required double slotW,
    required double slotH,
  }) {
    final px = painted.left;
    final py = painted.top;
    final pw = painted.width;
    final ph = painted.height;

    if (target is CalloutPoint) {
      final mx = px + target.x * pw;
      final my = py + target.y * ph;
      return MappedTarget._(
        source: target,
        x: mx,
        y: my,
        w: 0,
        h: 0,
        clipped: mx < 0 || my < 0 || mx > slotW || my > slotH,
      );
    }

    final r = target as CalloutRegion;
    final mx = px + r.x * pw;
    final my = py + r.y * ph;
    final mw = r.w * pw;
    final mh = r.h * ph;
    return MappedTarget._(
      source: target,
      x: mx,
      y: my,
      w: mw,
      h: mh,
      clipped: mx < 0 || my < 0 || mx + mw > slotW || my + mh > slotH,
    );
  }

  /// Full computation: painted rect + all mapped targets.
  static ImageGeometryResult compute({
    required double imageW,
    required double imageH,
    required double slotW,
    required double slotH,
    required double focalX,
    required double focalY,
    required int zoom,
    required List<CalloutTarget> targets,
  }) {
    final painted = paintedRect(
      imageW: imageW,
      imageH: imageH,
      slotW: slotW,
      slotH: slotH,
      focalX: focalX,
      focalY: focalY,
      zoom: zoom,
    );
    final mapped = targets
        .map((t) => mapTarget(t, painted: painted, slotW: slotW, slotH: slotH))
        .toList();
    return ImageGeometryResult(paintedRect: painted, targets: mapped);
  }

  /// Whether the zoom branch produces a wide or tall contain direction.
  ///
  /// Used by the CSS generator to pick `.ocideck-imgbox.wide` vs `.tall`
  /// (§4.2: letting CSS pick the contain direction is wrong by up to 2144 px).
  static bool isWideContain({
    required double imageW,
    required double imageH,
    required double slotW,
    required double slotH,
    required int zoom,
  }) {
    final ze = clampZoom(zoom);
    if (ze == 0) {
      return imageW / imageH >= slotW / slotH;
    }
    final k = ze / 100.0;
    final bw = slotW * k;
    final bh = slotH * k;
    return imageW / imageH >= bw / bh;
  }
}

double _max(double a, double b) => a > b ? a : b;
double _min(double a, double b) => a < b ? a : b;
