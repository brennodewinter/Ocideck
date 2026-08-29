// Callout overlay: paints numbered markers on top of the image slot.
// Uses ImageViewportGeometry (§4.1) to map targets from image space to
// slot pixels, so the overlay stays aligned with the painted image
// regardless of cover/zoom/focal.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/image_callout.dart';
import '../../../models/slide.dart';
import '../../../models/settings.dart';
import '../../../services/image_viewport_geometry.dart';
import '../../../services/web_asset_store.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/bundled_asset.dart';
import '../../../utils/image_limits.dart';
import '../../../utils/project_path.dart';

/// Creates an [ImageProvider] from an image path, mirroring the resolution
/// logic in `_cropProvider` (image_crop_dialog.dart) without taking a
/// dependency on that private function.
ImageProvider? _calloutImageProvider(String imagePath, String? projectPath) {
  if (imagePath.isEmpty) return null;
  if (isBundledAssetPath(imagePath)) {
    return cappedBundledAssetImage(bundledAssetKey(imagePath));
  }
  if (WebAssetStore.isMemPath(imagePath)) {
    final bytes = WebAssetStore.bytesFor(imagePath);
    return bytes == null ? null : cappedMemoryImage(bytes);
  }
  final resolved = resolveSlideAssetPath(imagePath, projectPath);
  if (resolved == null) return null;
  return cappedFileImage(File(resolved));
}

/// Zoek de intrinsieke maat van [provider] op en geef hem door aan [onSize],
/// met een vlag die zegt of dat **synchroon** gebeurde.
///
/// Staat het beeld al in de imagecache, dan roept [ImageStream.addListener] de
/// listener meteen aan; dan is `synchronous` waar en mag de aanroeper de maat
/// direct zetten in plaats van via `setState`. Dat onderscheid draagt de
/// rasterexports: die laden de beelden voor en vangen dan één frame. Loopt de
/// maat altijd over een `setState`, dan komt de markering pas in het frame
/// dáárna — zichtbaar in de app, weg in de PDF, PPTX en ODP.
///
/// Levert `null` als de afbeelding niet te lezen is.
@visibleForTesting
void resolveIntrinsicSize(
  ImageProvider provider,
  void Function(Size? size, bool synchronous) onSize,
) {
  var synchronous = true;
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  void finish(Size? size) {
    stream.removeListener(listener);
    onSize(size, synchronous);
  }

  listener = ImageStreamListener((info, _) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    info.dispose();
    finish(size);
  }, onError: (_, _) => finish(null));
  stream.addListener(listener);
  synchronous = false;
}

/// A callout marker: a numbered pin drawn on the image overlay.
///
/// Styling is theme-derived plus a non-optional two-tone edge (§6): the pixels
/// under a mark are arbitrary, so a theme accent cannot be assumed to contrast
/// with them. De vulling is het thema-accent; daaromheen ligt een **witte**
/// ring en daaromheen een donkere. Twee tonen, en met opzet één lichte en één
/// donkere: een rand die altijd donker is helpt niet op een donkere
/// ondergrond. Met het uitgerolde profiel (accent `#003399`, rand `#111111`)
/// haalde de markering op zwart 1,5:1 voor de vulling en 1,16:1 voor de rand —
/// ver onder de 3,5 die deze app zelf als ondergrens hanteert. In grijswaarden
/// bleef er een zwevende letter over. De HTML-export deed het al zo; dit brengt
/// Flutter in lijn.
class _CalloutMarker extends StatelessWidget {
  final String reference;
  final double x;
  final double y;
  final double markerRadius;
  final Color accentColor;
  final Color edgeColor;
  final Color textColor;
  final String? description;
  final int targetOrdinal;
  final int targetCount;

  const _CalloutMarker({
    required this.reference,
    required this.x,
    required this.y,
    required this.markerRadius,
    required this.accentColor,
    required this.edgeColor,
    required this.textColor,
    this.description,
    this.targetOrdinal = 1,
    this.targetCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final label = targetCount > 1
        ? '$reference, ${description ?? ''}, target $targetOrdinal of $targetCount'
        : '$reference, ${description ?? ''}';

    return Positioned(
      left: x - markerRadius,
      top: y - markerRadius,
      child: Semantics(
        container: true,
        label: label,
        child: Container(
          width: markerRadius * 2,
          height: markerRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor,
            border: Border.all(color: Colors.white, width: markerRadius * 0.16),
            boxShadow: [
              // Een massieve ring buiten de witte: geen vervaging, geen
              // verschuiving. Dit is de donkere helft van de twee tonen.
              BoxShadow(color: edgeColor, spreadRadius: markerRadius * 0.12),
            ],
          ),
          alignment: Alignment.center,
          // De zichtbare letter is de koppelsleutel voor de ziende lezer en
          // wordt buiten de boom gehouden: hij staat al vooraan in [label], en
          // zonder deze uitsluiting kondigt een schermlezer hem twee keer aan
          // ("B, de inlaat" gevolgd door "B") — de naam is dan niet meer wat
          // §12.2 voorschrijft.
          child: ExcludeSemantics(
            child: Text(
              reference,
              style: TextStyle(
                color: textColor,
                fontSize: markerRadius * 1.1,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The callout overlay: a Stack of [_CalloutMarker]s positioned on top
/// of the image slot, aligned to the painted image rectangle via
/// [ImageViewportGeometry].
///
/// Intrinsic image dimensions are resolved asynchronously; the overlay
/// is empty until they are known, then rebuilds with the markers.
///
/// [mediaRedacted] is passed in from the parent (SlideLinkScope) so this
/// widget stays free of the slide_preview library dependency.
class CalloutOverlay extends StatefulWidget {
  final Slide slide;
  final String? projectPath;
  final ThemeProfile profile;
  final double slotWidth;
  final double slotHeight;
  final bool mediaRedacted;

  /// Welke callout-references zichtbaar zijn in de onthullings-stapmodus (§7).
  /// Null = alles tonen (statische export, editor, niet-stappende presentatie).
  /// Wanneer non-null, worden alleen callouts getekend wiens reference in deze
  /// set zit; de rest is afwezig uit de overlay (en dus uit de accessibility
  /// tree — §12.2).
  final Set<String>? revealedReferences;

  const CalloutOverlay({
    super.key,
    required this.slide,
    this.projectPath,
    required this.profile,
    required this.slotWidth,
    required this.slotHeight,
    this.mediaRedacted = false,
    this.revealedReferences,
  });

  @override
  State<CalloutOverlay> createState() => _CalloutOverlayState();
}

class _CalloutOverlayState extends State<CalloutOverlay> {
  Size? _intrinsic;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _resolveIntrinsic();
  }

  @override
  void didUpdateWidget(CalloutOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.imagePath != widget.slide.imagePath ||
        oldWidget.projectPath != widget.projectPath) {
      _intrinsic = null;
      _resolveIntrinsic();
    }
  }

  /// Zoek de intrinsieke beeldmaat op. Staat het beeld al in de imagecache, dan
  /// roept [ImageStream.addListener] de listener **synchroon** aan; die maat
  /// wordt dan direct gezet, zonder `setState`, zodat de éérste build de
  /// markeringen al tekent.
  ///
  /// Dat onderscheid is niet kosmetisch. De rasterizer (PDF, PPTX, ODP) laadt
  /// de dia-afbeeldingen voor en vangt daarna een frame zodra de boom niet meer
  /// hoeft te verven. Ging de maat altijd via een `setState`, dan was dat frame
  /// al gevangen vóór de overlay iets tekende — en dat is precies wat er
  /// gebeurde: elke markering ontbrak in élke rasterexport, terwijl de app ze
  /// wél toonde.
  void _resolveIntrinsic() {
    if (_resolving) return;
    final provider = _calloutImageProvider(
      widget.slide.imagePath,
      widget.projectPath,
    );
    if (provider == null) return;
    _resolving = true;
    resolveIntrinsicSize(provider, (size, synchronous) {
      _resolving = false;
      if (synchronous) {
        // Nog binnen initState/didUpdateWidget: setState mag hier niet, en
        // hoeft ook niet — de build die hierop volgt ziet de maat al.
        _intrinsic = size;
        return;
      }
      if (mounted) setState(() => _intrinsic = size);
    });
  }

  @override
  Widget build(BuildContext context) {
    final callouts = widget.slide.callouts;
    if (callouts.isEmpty || _intrinsic == null) return const SizedBox();

    // Redacted slides draw no overlay (§8).
    if (widget.mediaRedacted) return const SizedBox();

    final painted = ImageViewportGeometry.paintedRect(
      imageW: _intrinsic!.width,
      imageH: _intrinsic!.height,
      slotW: widget.slotWidth,
      slotH: widget.slotHeight,
      focalX: widget.slide.imageFocalX,
      focalY: widget.slide.imageFocalY,
      zoom: widget.slide.imageZoom,
    );

    final accent = AppTheme.parseHexColor(widget.profile.accentColor);
    // The edge is always dark — the marker sits on arbitrary pixels, so a
    // theme accent cannot be assumed to contrast with them (§6).
    final edge = AppTheme.redactionInk;
    final textCol = accent.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    // Evenredig met het slot, met een ondergrens. Zonder die grens verdwijnt
    // de markering op slidestrook-breedte (~121 pt slot → straal 2,7): de
    // strook toont dan een dia waarvan niet te zien is dát er verwijzingen op
    // staan. De letter is daar toch niet te lezen — een navigatiestrook is
    // geen leesoppervlak — maar de markering moet een markering blijven.
    final markerRadius = math.max(widget.slotWidth * 0.022, 5.0);

    // §3.1: `mode` is a style, not a promise of shape. In `region` mode a
    // region target is an outlined rect with outside dimming and the
    // reference in its top-left corner; a point target is still a pin — a
    // renderer may reduce geometry, never invent it.
    final regionMode =
        widget.slide.calloutPresentation == CalloutPresentation.region;
    final arrowMode =
        widget.slide.calloutPresentation == CalloutPresentation.arrow;

    final markers = <Widget>[]; // pins (point targets, or pin-mode regions)
    final regionWidgets = <Widget>[]; // outlines + corner badges
    final regions = <Rect>[]; // holes punched in the dimming layer
    final arrows = <_ArrowSpec>[]; // fixed-rail arrows (§5)

    for (final callout in callouts) {
      // Stapmodus-filter (§7): alleen callouts wiens reference onthuld is.
      if (widget.revealedReferences != null &&
          !widget.revealedReferences!.contains(callout.reference)) {
        continue;
      }
      for (var i = 0; i < callout.targets.length; i++) {
        final target = callout.targets[i];

        if (arrowMode) {
          _buildArrowTarget(
            callout: callout,
            target: target,
            targetIndex: i,
            painted: painted,
            arrows: arrows,
            regionWidgets: regionWidgets,
            accent: accent,
            edge: edge,
            textCol: textCol,
            markerRadius: markerRadius,
          );
          continue;
        }

        if (regionMode && target is CalloutRegion) {
          _buildRegionTarget(
            callout: callout,
            target: target,
            targetIndex: i,
            painted: painted,
            regions: regions,
            regionWidgets: regionWidgets,
            accent: accent,
            edge: edge,
            textCol: textCol,
            markerRadius: markerRadius,
          );
          continue;
        }

        // Pin mode, or a point target in any mode: marker at the point, or
        // at the region's centre (the rectangle itself is not drawn).
        _buildPinTarget(
          callout: callout,
          target: target,
          targetIndex: i,
          painted: painted,
          markers: markers,
          accent: accent,
          edge: edge,
          textCol: textCol,
          markerRadius: markerRadius,
        );
      }
    }

    if (markers.isEmpty && regionWidgets.isEmpty && arrows.isEmpty) {
      return const SizedBox();
    }

    return _assembleOverlay(
      regions: regions,
      regionWidgets: regionWidgets,
      markers: markers,
      arrows: arrows,
      accent: accent,
      edge: edge,
      markerRadius: markerRadius,
    );
  }

  /// Builds one arrow-mode target (§5): a horizontal arrow from the fixed
  /// rail (left edge) to the target. Point targets get an arrow to the
  /// point; region targets get an outlined rectangle plus an arrow to the
  /// rectangle's left edge at centre height (§3.1).
  void _buildArrowTarget({
    required ImageCallout callout,
    required CalloutTarget target,
    required int targetIndex,
    required GeoRect painted,
    required List<_ArrowSpec> arrows,
    required List<Widget> regionWidgets,
    required Color accent,
    required Color edge,
    required Color textCol,
    required double markerRadius,
  }) {
    if (target is CalloutPoint) {
      final mapped = ImageViewportGeometry.mapTarget(
        target,
        painted: painted,
        slotW: widget.slotWidth,
        slotH: widget.slotHeight,
      );
      if (mapped.clipped) return;
      arrows.add(
        _ArrowSpec(
          railY: mapped.y,
          endX: mapped.x,
          endY: mapped.y,
          reference: callout.reference,
          accent: accent,
          edge: edge,
          textCol: textCol,
          markerRadius: markerRadius,
          description: callout.description,
          targetOrdinal: targetIndex + 1,
          targetCount: callout.targets.length,
        ),
      );
    } else {
      final r = target as CalloutRegion;
      final mapped = ImageViewportGeometry.mapTarget(
        r,
        painted: painted,
        slotW: widget.slotWidth,
        slotH: widget.slotHeight,
      );
      if (mapped.clipped) return;
      // Region outline (same as region mode, but no dimming).
      regionWidgets.add(
        Positioned(
          left: mapped.x,
          top: mapped.y,
          width: mapped.w,
          height: mapped.h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: edge, width: markerRadius * 0.4),
            ),
          ),
        ),
      );
      // Arrow ends on the left edge of the rect at the centre y
      // (horizontal line from rail to rect left edge).
      final centerY = mapped.y + mapped.h / 2;
      arrows.add(
        _ArrowSpec(
          railY: centerY,
          endX: mapped.x,
          endY: centerY,
          reference: callout.reference,
          accent: accent,
          edge: edge,
          textCol: textCol,
          markerRadius: markerRadius,
          description: callout.description,
          targetOrdinal: targetIndex + 1,
          targetCount: callout.targets.length,
        ),
      );
      // Reference badge in the top-left corner of the region.
      regionWidgets.add(
        _CalloutMarker(
          reference: callout.reference,
          x: mapped.x + markerRadius,
          y: mapped.y + markerRadius,
          markerRadius: markerRadius,
          accentColor: accent,
          edgeColor: edge,
          textColor: textCol,
          description: callout.description,
          targetOrdinal: targetIndex + 1,
          targetCount: callout.targets.length,
        ),
      );
    }
  }

  /// Region-mode target (§3.1): outlined rectangle with outside dimming
  /// and the reference badge in its top-left corner.
  void _buildRegionTarget({
    required ImageCallout callout,
    required CalloutRegion target,
    required int targetIndex,
    required GeoRect painted,
    required List<Rect> regions,
    required List<Widget> regionWidgets,
    required Color accent,
    required Color edge,
    required Color textCol,
    required double markerRadius,
  }) {
    final mapped = ImageViewportGeometry.mapTarget(
      target,
      painted: painted,
      slotW: widget.slotWidth,
      slotH: widget.slotHeight,
    );
    if (mapped.clipped) return;
    regions.add(Rect.fromLTWH(mapped.x, mapped.y, mapped.w, mapped.h));
    regionWidgets.add(
      Positioned(
        left: mapped.x,
        top: mapped.y,
        width: mapped.w,
        height: mapped.h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: edge, width: markerRadius * 0.4),
          ),
        ),
      ),
    );
    regionWidgets.add(
      _CalloutMarker(
        reference: callout.reference,
        x: mapped.x + markerRadius,
        y: mapped.y + markerRadius,
        markerRadius: markerRadius,
        accentColor: accent,
        edgeColor: edge,
        textColor: textCol,
        description: callout.description,
        targetOrdinal: targetIndex + 1,
        targetCount: callout.targets.length,
      ),
    );
  }

  /// Pin target (§3.1): marker at the point, or at the region's centre.
  void _buildPinTarget({
    required ImageCallout callout,
    required CalloutTarget target,
    required int targetIndex,
    required GeoRect painted,
    required List<Widget> markers,
    required Color accent,
    required Color edge,
    required Color textCol,
    required double markerRadius,
  }) {
    final (ux, uy) = target is CalloutPoint
        ? (target.x, target.y)
        : (() {
            final r = target as CalloutRegion;
            return (r.x + r.w / 2, r.y + r.h / 2);
          })();
    final mapped = ImageViewportGeometry.mapTarget(
      CalloutPoint(ux, uy),
      painted: painted,
      slotW: widget.slotWidth,
      slotH: widget.slotHeight,
    );
    if (mapped.clipped) return;
    markers.add(
      _CalloutMarker(
        reference: callout.reference,
        x: mapped.x,
        y: mapped.y,
        markerRadius: markerRadius,
        accentColor: accent,
        edgeColor: edge,
        textColor: textCol,
        description: callout.description,
        targetOrdinal: targetIndex + 1,
        targetCount: callout.targets.length,
      ),
    );
  }

  /// Assembles the final overlay Stack from all rendered layers.
  Widget _assembleOverlay({
    required List<Rect> regions,
    required List<Widget> regionWidgets,
    required List<Widget> markers,
    required List<_ArrowSpec> arrows,
    required Color accent,
    required Color edge,
    required double markerRadius,
  }) {
    final children = <Widget>[];
    if (regions.isNotEmpty) {
      children.add(
        Positioned.fill(
          child: CustomPaint(
            painter: _RegionDimPainter(
              regions,
              AppTheme.redactionInk.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }
    children.addAll(regionWidgets);
    children.addAll(markers);
    if (arrows.isNotEmpty) {
      children.add(
        Positioned.fill(
          child: CustomPaint(
            painter: _ArrowPainter(
              arrows,
              accent: accent,
              edge: edge,
              strokeWidth: markerRadius * 0.3,
            ),
          ),
        ),
      );
      for (final a in arrows) {
        children.add(
          _CalloutMarker(
            reference: a.reference,
            x: a.markerRadius,
            y: a.railY,
            markerRadius: a.markerRadius,
            accentColor: a.accent,
            edgeColor: a.edge,
            textColor: a.textCol,
            description: a.description,
            targetOrdinal: a.targetOrdinal,
            targetCount: a.targetCount,
          ),
        );
      }
    }
    return IgnorePointer(child: Stack(children: children));
  }
}

/// Paints the region-mode dimming: fills the slot with a semi-transparent
/// dark layer and cuts a hole for each region rect, so the area outside
/// every region is darkened exactly once — no stacking across overlapping
/// regions (§3.1).
class _RegionDimPainter extends CustomPainter {
  final List<Rect> regions;
  final Color dim;

  const _RegionDimPainter(this.regions, this.dim);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Path()..addRect(Offset.zero & size);
    var holes = Path();
    for (final r in regions) {
      holes = Path.combine(PathOperation.union, holes, Path()..addRect(r));
    }
    canvas.drawPath(
      Path.combine(PathOperation.difference, fill, holes),
      Paint()..color = dim,
    );
  }

  @override
  bool shouldRepaint(_RegionDimPainter old) {
    if (dim != old.dim) return true;
    if (regions.length != old.regions.length) return true;
    for (var i = 0; i < regions.length; i++) {
      if (regions[i] != old.regions[i]) return true;
    }
    return false;
  }
}

/// Specification for one fixed-rail arrow (§5): a horizontal line from the
/// rail at (0, railY) to (endX, endY), with an arrowhead at the target end.
class _ArrowSpec {
  final double railY;
  final double endX;
  final double endY;
  final String reference;
  final Color accent;
  final Color edge;
  final Color textCol;
  final double markerRadius;
  final String? description;
  final int targetOrdinal;
  final int targetCount;

  const _ArrowSpec({
    required this.railY,
    required this.endX,
    required this.endY,
    required this.reference,
    required this.accent,
    required this.edge,
    required this.textCol,
    required this.markerRadius,
    this.description,
    required this.targetOrdinal,
    required this.targetCount,
  });
}

/// Paints fixed-rail arrows: horizontal lines from the left edge of the
/// image slot to each target, with arrowheads. The two-tone edge (§6) is
/// applied as a stroke around the line so it contrasts with arbitrary
/// image pixels.
class _ArrowPainter extends CustomPainter {
  final List<_ArrowSpec> arrows;
  final Color accent;
  final Color edge;
  final double strokeWidth;

  const _ArrowPainter(
    this.arrows, {
    required this.accent,
    required this.edge,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final headLen = strokeWidth * 3;
    final headWidth = strokeWidth * 2.5;
    for (final a in arrows) {
      // Start point: just right of the rail badge so the line doesn't
      // overlap the circle.
      final start = Offset(a.markerRadius * 1.8, a.railY);
      final end = Offset(a.endX, a.endY);
      // Edge stroke (two-tone contrast, §6).
      final edgePaint = Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, edgePaint);
      // Accent stroke on top.
      final accentPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, accentPaint);
      // Arrowhead: a filled triangle pointing right.
      final headPath = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - headLen, end.dy - headWidth)
        ..lineTo(end.dx - headLen, end.dy + headWidth)
        ..close();
      canvas.drawPath(
        headPath,
        Paint()
          ..color = edge
          ..style = PaintingStyle.fill,
      );
      // Slightly smaller accent triangle on top.
      final innerHead = Path()
        ..moveTo(end.dx - strokeWidth * 0.3, end.dy)
        ..lineTo(end.dx - headLen + strokeWidth * 0.5, end.dy - headWidth * 0.7)
        ..lineTo(end.dx - headLen + strokeWidth * 0.5, end.dy + headWidth * 0.7)
        ..close();
      canvas.drawPath(innerHead, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      arrows.length != old.arrows.length ||
      accent != old.accent ||
      edge != old.edge ||
      strokeWidth != old.strokeWidth;
}
