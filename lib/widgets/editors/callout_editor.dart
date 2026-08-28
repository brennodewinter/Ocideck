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
  int? _selectedCalloutIndex;

  @override
  void initState() {
    super.initState();
    _callouts = List.of(widget.slide.callouts);
  }

  void _emit() {
    widget.onUpdate(widget.slide.copyWith(callouts: _callouts));
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

    setState(() {
      _callouts.add(
        ImageCallout(
          reference: ref,
          targets: [const CalloutPoint(0.5, 0.5)],
          description: '',
        ),
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
      targets[targetIndex] = CalloutPoint(clampedX, clampedY);
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
      targets.add(const CalloutPoint(0.5, 0.5));
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
            // Right: image with markers + description editor.
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
                  // Clickable overlay for placing markers.
                  GestureDetector(
                    onTapUp: (details) {
                      final x = details.localPosition.dx / slotW;
                      final y = details.localPosition.dy / slotH;
                      // Move the first target to the clicked position.
                      _moveTarget(_selectedCalloutIndex!, 0, x, y);
                    },
                    child: Container(color: Colors.transparent),
                  ),
                  // Markers.
                  ..._buildMarkers(callout, slotW, slotH),
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
    final markers = <Widget>[];
    for (var i = 0; i < callout.targets.length; i++) {
      final target = callout.targets[i];
      double ux, uy;
      if (target is CalloutPoint) {
        ux = target.x;
        uy = target.y;
      } else {
        final r = target as CalloutRegion;
        ux = r.x + r.w / 2;
        uy = r.y + r.h / 2;
      }
      markers.add(
        Positioned(
          left: ux * slotW - markerRadius,
          top: uy * slotH - markerRadius,
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
    }
    return markers;
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
