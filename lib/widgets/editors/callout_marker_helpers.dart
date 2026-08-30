// Helper widgets and types for the callout editor — extracted to keep
// callout_editor.dart under the 1000-line ceiling. Pure widgets and value
// types, no State dependencies.

import 'package:material_ui/material_ui.dart';
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
