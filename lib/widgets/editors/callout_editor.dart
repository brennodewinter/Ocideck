// Callout editor section for the Bullets+image editor — IMAGE_CALLOUTS.md §6.
//
// Minimal viable editor: assign a reference letter to a bullet, place a
// point target by clicking on the image, edit the description, delete.
// Opens as a dialog showing the real image with click-to-place markers.

import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../models/slide.dart';
import '../../models/image_callout.dart';
import '../../services/callout_reference_allocator.dart';
import '../../services/web_asset_store.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/bundled_asset.dart';
import '../../utils/image_limits.dart';
import '../../utils/project_path.dart';

/// A dialog for editing image callouts on a bulletsImage slide.
///
/// Shows the image with existing callout markers overlaid. The author
/// selects a bullet, clicks on the image to place a target, and can
/// edit the description or delete the callout.
class CalloutEditorDialog extends StatefulWidget {
  final Slide slide;
  final String? projectPath;
  final ValueChanged<Slide> onUpdate;

  const CalloutEditorDialog({
    super.key,
    required this.slide,
    this.projectPath,
    required this.onUpdate,
  });

  @override
  State<CalloutEditorDialog> createState() => _CalloutEditorDialogState();
}

class _CalloutEditorDialogState extends State<CalloutEditorDialog> {
  late List<ImageCallout> _callouts;
  late CalloutPresentation _presentation;
  late BulletRevealMode _reveal;
  int? _selectedCalloutIndex;

  /// Region being dragged out — null when not dragging.
  _DragRegion? _dragRegion;

  @override
  void initState() {
    super.initState();
    _callouts = List.of(widget.slide.callouts);
    _presentation = widget.slide.calloutPresentation;
    _reveal = widget.slide.calloutReveal;
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        callouts: _callouts,
        calloutPresentation: _presentation,
        calloutReveal: _reveal,
      ),
    );
  }

  /// Adds a callout to a bullet, assigning the next free reference letter.
  void _addCallout(int bulletIndex) {
    final bullets = widget.slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    if (bulletIndex < 0 || bulletIndex >= bullets.length) return;

    final proseLetters = trailingReferenceLetters(bullets);
    final usedLetters = calloutLetters(_callouts);
    final ref = nextFreeReference(usedLetters, proseLetters);
    if (ref == null) return; // §8: 26 references max.

    final firstTarget = _presentation == CalloutPresentation.region
        ? const CalloutRegion(0.3, 0.3, 0.4, 0.4)
        : const CalloutPoint(0.5, 0.5);
    setState(() {
      _callouts.add(
        ImageCallout(reference: ref, targets: [firstTarget], description: ''),
      );
      _selectedCalloutIndex = _callouts.length - 1;
    });
    _emit();
  }

  void _removeCallout(int index) {
    setState(() {
      _callouts.removeAt(index);
      if (_selectedCalloutIndex == index) {
        _selectedCalloutIndex = null;
      } else if (_selectedCalloutIndex != null &&
          _selectedCalloutIndex! > index) {
        _selectedCalloutIndex = _selectedCalloutIndex! - 1;
      }
    });
    _emit();
  }

  void _moveTarget(int calloutIndex, int targetIndex, double x, double y) {
    final clampedX = x.clamp(0.0, 1.0);
    final clampedY = y.clamp(0.0, 1.0);
    setState(() {
      final callout = _callouts[calloutIndex];
      final targets = List.of(callout.targets);
      final old = targets[targetIndex];
      if (old is CalloutRegion) {
        // Move region by top-left, clamping so it stays in-bounds.
        final w = old.w, h = old.h;
        targets[targetIndex] = CalloutRegion(
          clampedX.clamp(0.0, (1.0 - w).clamp(0.0, 1.0)),
          clampedY.clamp(0.0, (1.0 - h).clamp(0.0, 1.0)),
          w,
          h,
        );
      } else {
        targets[targetIndex] = CalloutPoint(clampedX, clampedY);
      }
      _callouts[calloutIndex] = ImageCallout(
        reference: callout.reference,
        targets: targets,
        description: callout.description,
      );
    });
    _emit();
  }

  /// Resizes a region target by adjusting its top-left corner and/or size.
  /// [handle] selects which corner is being dragged.
  void _resizeRegion(
    int calloutIndex,
    int targetIndex,
    _Handle handle,
    double x,
    double y,
  ) {
    final cx = x.clamp(0.0, 1.0);
    final cy = y.clamp(0.0, 1.0);
    setState(() {
      final callout = _callouts[calloutIndex];
      final targets = List.of(callout.targets);
      final r = targets[targetIndex] as CalloutRegion;
      double nx = r.x, ny = r.y, nw = r.w, nh = r.h;
      switch (handle) {
        case _Handle.topLeft:
          nx = cx.clamp(0.0, r.x + r.w - 0.02);
          ny = cy.clamp(0.0, r.y + r.h - 0.02);
          nw = r.x + r.w - nx;
          nh = r.y + r.h - ny;
        case _Handle.topRight:
          ny = cy.clamp(0.0, r.y + r.h - 0.02);
          nw = (cx - r.x).clamp(0.02, 1.0 - r.x);
          nh = r.y + r.h - ny;
        case _Handle.bottomLeft:
          nx = cx.clamp(0.0, r.x + r.w - 0.02);
          nw = r.x + r.w - nx;
          nh = (cy - r.y).clamp(0.02, 1.0 - r.y);
        case _Handle.bottomRight:
          nw = (cx - r.x).clamp(0.02, 1.0 - r.x);
          nh = (cy - r.y).clamp(0.02, 1.0 - r.y);
      }
      targets[targetIndex] = CalloutRegion(nx, ny, nw, nh);
      _callouts[calloutIndex] = ImageCallout(
        reference: callout.reference,
        targets: targets,
        description: callout.description,
      );
    });
    _emit();
  }

  void _addTarget(int calloutIndex) {
    setState(() {
      final callout = _callouts[calloutIndex];
      if (callout.targets.length >= 8) return; // §8: 8 targets max.
      final targets = List.of(callout.targets);
      targets.add(
        _presentation == CalloutPresentation.region
            ? const CalloutRegion(0.3, 0.3, 0.4, 0.4)
            : const CalloutPoint(0.5, 0.5),
      );
      _callouts[calloutIndex] = ImageCallout(
        reference: callout.reference,
        targets: targets,
        description: callout.description,
      );
    });
    _emit();
  }

  void _removeTarget(int calloutIndex, int targetIndex) {
    setState(() {
      final callout = _callouts[calloutIndex];
      if (callout.targets.length <= 1) {
        // Removing the last target removes the callout.
        _removeCallout(calloutIndex);
        return;
      }
      final targets = List.of(callout.targets);
      targets.removeAt(targetIndex);
      _callouts[calloutIndex] = ImageCallout(
        reference: callout.reference,
        targets: targets,
        description: callout.description,
      );
    });
    _emit();
  }

  void _setDescription(int calloutIndex, String desc) {
    setState(() {
      final callout = _callouts[calloutIndex];
      _callouts[calloutIndex] = ImageCallout(
        reference: callout.reference,
        targets: callout.targets,
        description: desc,
      );
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bullets = widget.slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();

    return AlertDialog(
      title: Text(l10n.d('Afbeeldingsverwijzingen')),
      content: SizedBox(
        width: 900,
        height: 600,
        child: Row(
          children: [
            // Left: bullet list with add/remove reference buttons.
            SizedBox(
              width: 300,
              child: ListView.builder(
                itemCount: bullets.length,
                itemBuilder: (context, i) {
                  final bullet = bullets[i];
                  final ref = _calloutLetterForBullet(bullet);
                  final isSelected =
                      _calloutForBullet(bullet) != null &&
                      _selectedCalloutIndex == _calloutIndexForBullet(bullet);
                  return ListTile(
                    selected: isSelected,
                    leading: ref != null
                        ? CircleAvatar(
                            radius: 14,
                            backgroundColor: AppTheme.accentFg,
                            child: Text(
                              ref,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : null,
                    title: Text(
                      bullet.replaceAll(RegExp(r'\s\([A-Z]\)$'), ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: ref != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: l10n.d('Reference verwijderen'),
                            onPressed: () {
                              final idx = _calloutIndexForBullet(bullet);
                              if (idx != null) _removeCallout(idx);
                            },
                          )
                        : TextButton(
                            onPressed: _callouts.length < 26
                                ? () => _addCallout(i)
                                : null,
                            child: Text(l10n.d('Toevoegen')),
                          ),
                    onTap: () {
                      final idx = _calloutIndexForBullet(bullet);
                      if (idx != null) {
                        setState(() => _selectedCalloutIndex = idx);
                      }
                    },
                  );
                },
              ),
            ),
            const VerticalDivider(),
            // Right: presentation toggle + image with markers + description.
            Expanded(
              child: Column(
                children: [
                  // §3.1: slide-level presentation mode selector.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<CalloutPresentation>(
                        segments: [
                          ButtonSegment(
                            value: CalloutPresentation.pin,
                            label: Text(l10n.d('Pins')),
                          ),
                          ButtonSegment(
                            value: CalloutPresentation.region,
                            label: Text(l10n.d('Gebieden')),
                          ),
                          ButtonSegment(
                            value: CalloutPresentation.arrow,
                            label: Text(l10n.d('Pijlen')),
                          ),
                        ],
                        selected: {_presentation},
                        onSelectionChanged: (s) {
                          setState(() => _presentation = s.first);
                          _emit();
                        },
                      ),
                    ),
                  ),
                  // §7: reveal mode — all (everything visible) or steps
                  // (one bullet + its targets per click during presentation).
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<BulletRevealMode>(
                        segments: [
                          ButtonSegment(
                            value: BulletRevealMode.all,
                            label: Text(l10n.d('Alles tonen')),
                          ),
                          ButtonSegment(
                            value: BulletRevealMode.steps,
                            label: Text(l10n.d('Stap-voor-stap')),
                          ),
                        ],
                        selected: {_reveal},
                        onSelectionChanged: (s) {
                          setState(() => _reveal = s.first);
                          _emit();
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: _selectedCalloutIndex != null
                        ? _buildImageWithMarkers(context)
                        : Center(
                            child: Text(
                              l10n.d(
                                'Selecteer een bullet om een reference te plaatsen.',
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }

  Widget _buildImageWithMarkers(BuildContext context) {
    final callout = _callouts[_selectedCalloutIndex!];
    final l10n = context.l10n;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotW = constraints.maxWidth;
              final slotH = constraints.maxHeight;
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Image background.
                  Container(
                    color: Colors.black,
                    child: Image(
                      image: _calloutImageProvider(
                        widget.slide.imagePath,
                        widget.projectPath,
                      )!,
                      fit: widget.slide.imageZoom == 0
                          ? BoxFit.cover
                          : BoxFit.contain,
                      alignment: Alignment(
                        (widget.slide.imageFocalX * 2) - 1,
                        (widget.slide.imageFocalY * 2) - 1,
                      ),
                    ),
                  ),
                  // Gesture layer: click-to-place (pin) or drag-out (region).
                  GestureDetector(
                    onPanStart: (details) {
                      if (_presentation != CalloutPresentation.region) return;
                      final x = details.localPosition.dx / slotW;
                      final y = details.localPosition.dy / slotH;
                      setState(() {
                        _dragRegion = _DragRegion(x, y, 0, 0);
                      });
                    },
                    onPanUpdate: (details) {
                      if (_dragRegion == null) return;
                      final x = details.localPosition.dx / slotW;
                      final y = details.localPosition.dy / slotH;
                      setState(() {
                        _dragRegion = _DragRegion.fromDrag(
                          _dragRegion!.startX,
                          _dragRegion!.startY,
                          x.clamp(0.0, 1.0),
                          y.clamp(0.0, 1.0),
                        );
                      });
                    },
                    onPanEnd: (_) {
                      final d = _dragRegion;
                      if (d != null && d.w >= 0.02 && d.h >= 0.02) {
                        // Commit the dragged region as the first target.
                        setState(() {
                          final callout = _callouts[_selectedCalloutIndex!];
                          final targets = List.of(callout.targets);
                          targets[0] = CalloutRegion(d.x, d.y, d.w, d.h);
                          _callouts[_selectedCalloutIndex!] = ImageCallout(
                            reference: callout.reference,
                            targets: targets,
                            description: callout.description,
                          );
                          _dragRegion = null;
                        });
                        _emit();
                      } else {
                        setState(() => _dragRegion = null);
                      }
                    },
                    onTapUp: (details) {
                      if (_presentation == CalloutPresentation.region) return;
                      final x = details.localPosition.dx / slotW;
                      final y = details.localPosition.dy / slotH;
                      _moveTarget(_selectedCalloutIndex!, 0, x, y);
                    },
                    child: Container(color: Colors.transparent),
                  ),
                  // Markers / regions / drag-preview.
                  ..._buildMarkers(callout, slotW, slotH),
                  if (_dragRegion != null)
                    _buildDragPreview(_dragRegion!, slotW, slotH),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Description editor.
        TextField(
          decoration: InputDecoration(
            labelText: l10n.d('Beschrijving (voor schermlezer)'),
            hintText: l10n.d('bv. "de controller board met display"'),
            isDense: true,
          ),
          maxLength: 200,
          controller: TextEditingController(text: callout.description)
            ..selection = TextSelection.fromPosition(
              TextPosition(offset: callout.description.length),
            ),
          onChanged: (v) => _setDescription(_selectedCalloutIndex!, v),
        ),
        // Target controls.
        Row(
          children: [
            Text(
              '${callout.targets.length} ${l10n.d('target(s)')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            if (callout.targets.length < 8)
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.d('Target toevoegen')),
                onPressed: () => _addTarget(_selectedCalloutIndex!),
              ),
            if (callout.targets.length > 1)
              TextButton.icon(
                icon: const Icon(Icons.remove, size: 16),
                label: Text(l10n.d('Target verwijderen')),
                onPressed: () => _removeTarget(
                  _selectedCalloutIndex!,
                  callout.targets.length - 1,
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildMarkers(ImageCallout callout, double slotW, double slotH) {
    final markerRadius = slotW * 0.025;
    final handleSize = slotW * 0.02;
    final widgets = <Widget>[];
    for (var i = 0; i < callout.targets.length; i++) {
      final target = callout.targets[i];
      if (target is CalloutRegion) {
        final rx = target.x * slotW;
        final ry = target.y * slotH;
        final rw = target.w * slotW;
        final rh = target.h * slotH;
        // Outline + move handle (drag inside the rect).
        widgets.add(
          Positioned(
            left: rx,
            top: ry,
            width: rw,
            height: rh,
            child: GestureDetector(
              onPanUpdate: (details) {
                final nx = (target.x + details.delta.dx / slotW).clamp(
                  0.0,
                  1.0,
                );
                final ny = (target.y + details.delta.dy / slotH).clamp(
                  0.0,
                  1.0,
                );
                _moveTarget(_selectedCalloutIndex!, i, nx, ny);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.accentFg, width: 2),
                ),
              ),
            ),
          ),
        );
        // Reference badge in top-left corner.
        widgets.add(
          Positioned(
            left: rx + 2,
            top: ry + 2,
            child: Container(
              width: markerRadius * 2,
              height: markerRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentFg,
                border: Border.all(
                  color: Colors.black,
                  width: markerRadius * 0.18,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                callout.reference,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: markerRadius,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
        // Four corner resize handles.
        for (final handle in _Handle.values) {
          final (hx, hy) = handle.offset(rx, ry, rw, rh);
          widgets.add(
            Positioned(
              left: hx - handleSize / 2,
              top: hy - handleSize / 2,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final nx = (hx + details.delta.dx) / slotW;
                  final ny = (hy + details.delta.dy) / slotH;
                  _resizeRegion(_selectedCalloutIndex!, i, handle, nx, ny);
                },
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: BoxDecoration(
                    color: AppTheme.accentFg,
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                ),
              ),
            ),
          );
        }
      } else {
        // Point target: numbered marker centred on the point.
        final p = target as CalloutPoint;
        widgets.add(
          Positioned(
            left: p.x * slotW - markerRadius,
            top: p.y * slotH - markerRadius,
            child: GestureDetector(
              onPanUpdate: (details) {
                final nx = (p.x + details.delta.dx / slotW).clamp(0.0, 1.0);
                final ny = (p.y + details.delta.dy / slotH).clamp(0.0, 1.0);
                _moveTarget(_selectedCalloutIndex!, i, nx, ny);
              },
              child: Container(
                width: markerRadius * 2,
                height: markerRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentFg,
                  border: Border.all(
                    color: Colors.black,
                    width: markerRadius * 0.18,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  callout.reference,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: markerRadius,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  /// Preview rectangle while dragging out a new region.
  Widget _buildDragPreview(_DragRegion d, double slotW, double slotH) {
    return Positioned(
      left: d.x * slotW,
      top: d.y * slotH,
      width: d.w * slotW,
      height: d.h * slotH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.accentFg, width: 2),
          color: AppTheme.accentFg.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  /// Finds the callout reference letter for a bullet, by matching the
  /// trailing `(A)` in the bullet text.
  String? _calloutLetterForBullet(String bullet) {
    final match = RegExp(r'\s\(([A-Z])\)$').firstMatch(bullet.trimRight());
    return match?.group(1);
  }

  /// Finds the callout for a bullet by its trailing reference letter.
  ImageCallout? _calloutForBullet(String bullet) {
    final letter = _calloutLetterForBullet(bullet);
    if (letter == null) return null;
    for (final c in _callouts) {
      if (c.reference == letter) return c;
    }
    return null;
  }

  int? _calloutIndexForBullet(String bullet) {
    final letter = _calloutLetterForBullet(bullet);
    if (letter == null) return null;
    for (var i = 0; i < _callouts.length; i++) {
      if (_callouts[i].reference == letter) return i;
    }
    return null;
  }
}

/// Creates an ImageProvider from an image path for the callout editor.
/// Mirrors the logic in _cropProvider (image_crop_dialog.dart).
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

/// Which corner of a region is being dragged.
enum _Handle { topLeft, topRight, bottomLeft, bottomRight }

extension _HandleOffset on _Handle {
  (double, double) offset(double rx, double ry, double rw, double rh) {
    return switch (this) {
      _Handle.topLeft => (rx, ry),
      _Handle.topRight => (rx + rw, ry),
      _Handle.bottomLeft => (rx, ry + rh),
      _Handle.bottomRight => (rx + rw, ry + rh),
    };
  }
}

/// In-progress region drag: stores the start point and current normalised rect.
class _DragRegion {
  final double startX, startY, x, y, w, h;
  _DragRegion(this.startX, this.startY, this.w, this.h)
    : x = startX,
      y = startY;

  _DragRegion.fromDrag(this.startX, this.startY, double endX, double endY)
    : x = startX < endX ? startX : endX,
      y = startY < endY ? startY : endY,
      w = (endX - startX).abs(),
      h = (endY - startY).abs();
}
