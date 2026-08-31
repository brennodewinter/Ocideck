// Helper widgets and types for the callout editor — extracted to keep
// callout_editor.dart under the 1000-line ceiling. Pure widgets and value
// types, no State dependencies.

import 'package:material_ui/material_ui.dart';
import '../../models/image_callout.dart';
import '../../services/image_viewport_geometry.dart';
import '../../theme/app_theme.dart';

/// #1853: een waarschuwingsbadge aan de rand van het slot voor een doel
/// dat buiten beeld valt. De badge toont de reference-letter, geklemd aan
/// de dichtstbijzijnde rand.
Widget buildClippedBadge(
  String reference,
  MappedTarget mapped,
  double slotW,
  double slotH,
) {
  final markerRadius = slotW * 0.025;
  final x = mapped.x.clamp(markerRadius, slotW - markerRadius);
  final y = mapped.y.clamp(markerRadius, slotH - markerRadius);
  return Positioned(
    left: x - markerRadius,
    top: y - markerRadius,
    child: Container(
      width: markerRadius * 2,
      height: markerRadius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.warningFg,
        border: Border.all(color: Colors.black, width: markerRadius * 0.18),
      ),
      alignment: Alignment.center,
      child: Text(
        reference,
        style: TextStyle(
          color: Colors.black,
          fontSize: markerRadius,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Preview rectangle while dragging out a new region.
Widget buildDragPreview(
  DragRegion d,
  double slotW,
  double slotH,
  GeoRect? painted,
) {
  final rx = painted == null ? d.x * slotW : painted.left + d.x * painted.width;
  final ry = painted == null ? d.y * slotH : painted.top + d.y * painted.height;
  final rw = painted == null ? d.w * slotW : d.w * painted.width;
  final rh = painted == null ? d.h * slotH : d.h * painted.height;
  return Positioned(
    left: rx,
    top: ry,
    width: rw,
    height: rh,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.accentFg, width: 2),
        color: AppTheme.accentFg.withValues(alpha: 0.2),
      ),
    ),
  );
}

/// #1854: statische markeringen voor een niet-geselecteerde callout — een
/// gedimde badge met de reference-letter per doel, regio's krijgen een
/// gedimde omlijning. [onTap] selecteert de callout in de editor.
List<Widget> buildStaticCalloutMarkers(
  ImageCallout callout,
  double slotW,
  double slotH,
  GeoRect? painted, {
  VoidCallback? onTap,
}) {
  final r = slotW * 0.022;
  final ws = <Widget>[];
  for (final t in callout.targets) {
    if (!t.isValid) continue;
    final m = painted == null
        ? null
        : ImageViewportGeometry.mapTarget(
            t,
            painted: painted,
            slotW: slotW,
            slotH: slotH,
          );
    if (m != null && m.clipped) continue;
    double cx, cy;
    if (t is CalloutRegion) {
      final rx = painted == null ? t.x * slotW : m!.x;
      final ry = painted == null ? t.y * slotH : m!.y;
      final rw = painted == null ? t.w * slotW : m!.w;
      final rh = painted == null ? t.h * slotH : m!.h;
      ws.add(
        Positioned(
          left: rx,
          top: ry,
          width: rw,
          height: rh,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: AppTheme.accentFg.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
          ),
        ),
      );
      cx = rx + r;
      cy = ry + r;
    } else {
      final p = t as CalloutPoint;
      cx = painted == null ? p.x * slotW : m!.x;
      cy = painted == null ? p.y * slotH : m!.y;
    }
    ws.add(
      Positioned(
        left: cx - r,
        top: cy - r,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentFg.withValues(alpha: 0.7),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: r * 0.18,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              callout.reference,
              style: TextStyle(
                color: Colors.white,
                fontSize: r,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
  return ws;
}

/// Which corner of a region is being dragged.
enum Handle { topLeft, topRight, bottomLeft, bottomRight }

extension HandleOffset on Handle {
  (double, double) offset(double rx, double ry, double rw, double rh) {
    return switch (this) {
      Handle.topLeft => (rx, ry),
      Handle.topRight => (rx + rw, ry),
      Handle.bottomLeft => (rx, ry + rh),
      Handle.bottomRight => (rx + rw, ry + rh),
    };
  }
}

/// In-progress region drag: stores the start point and current normalised rect.
class DragRegion {
  final double startX, startY, x, y, w, h;
  DragRegion(this.startX, this.startY, this.w, this.h) : x = startX, y = startY;

  DragRegion.fromDrag(this.startX, this.startY, double endX, double endY)
    : x = startX < endX ? startX : endX,
      y = startY < endY ? startY : endY,
      w = (endX - startX).abs(),
      h = (endY - startY).abs();
}
