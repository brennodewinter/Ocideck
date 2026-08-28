// Callout overlay: paints numbered markers on top of the image slot.
// Uses ImageViewportGeometry (§4.1) to map targets from image space to
// slot pixels, so the overlay stays aligned with the painted image
// regardless of cover/zoom/focal.

import 'dart:async';
import 'dart:io';

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

/// Resolves the intrinsic dimensions of an image at [imagePath].
/// Returns null if the image cannot be resolved.
Future<Size?> _resolveIntrinsicSize(
  String imagePath,
  String? projectPath,
) async {
  final provider = _calloutImageProvider(imagePath, projectPath);
  if (provider == null) return null;
  final completer = Completer<Size?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      info.dispose();
      if (!completer.isCompleted) completer.complete(size);
    },
    onError: (error, _) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  stream.addListener(listener);
  final result = await completer.future;
  stream.removeListener(listener);
  return result;
}

/// A callout marker: a numbered pin drawn on the image overlay.
///
/// Styling is theme-derived plus a non-optional two-tone edge (§6):
/// the pixels under a mark are arbitrary, so a theme accent cannot be
/// assumed to contrast with them. The edge is always dark, the fill is
/// the theme accent, and the text is white-on-accent or dark-on-light.
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
            border: Border.all(color: edgeColor, width: markerRadius * 0.18),
          ),
          alignment: Alignment.center,
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

  const CalloutOverlay({
    super.key,
    required this.slide,
    this.projectPath,
    required this.profile,
    required this.slotWidth,
    required this.slotHeight,
    this.mediaRedacted = false,
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

  void _resolveIntrinsic() {
    if (_resolving) return;
    _resolving = true;
    _resolveIntrinsicSize(widget.slide.imagePath, widget.projectPath).then((
      size,
    ) {
      if (mounted) setState(() => _intrinsic = size);
      _resolving = false;
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
    final markerRadius = widget.slotWidth * 0.022;

    final markers = <Widget>[];
    for (final callout in callouts) {
      for (var i = 0; i < callout.targets.length; i++) {
        final target = callout.targets[i];
        // §3.1 pin mode: point → marker centred on point;
        // region → marker at region centre.
        double ux, uy;
        if (target is CalloutPoint) {
          ux = target.x;
          uy = target.y;
        } else {
          final r = target as CalloutRegion;
          ux = r.x + r.w / 2;
          uy = r.y + r.h / 2;
        }
        final mapped = ImageViewportGeometry.mapTarget(
          CalloutPoint(ux, uy),
          painted: painted,
          slotW: widget.slotWidth,
          slotH: widget.slotHeight,
        );
        // Skip clipped markers — they're outside the visible slot.
        if (mapped.clipped) continue;
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
            targetOrdinal: i + 1,
            targetCount: callout.targets.length,
          ),
        );
      }
    }

    if (markers.isEmpty) return const SizedBox();
    return IgnorePointer(child: Stack(children: markers));
  }
}
