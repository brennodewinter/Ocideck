// Callout editor section for the Bullets+image editor — IMAGE_CALLOUTS.md §6.
//
// Minimal viable editor: assign a reference letter to a bullet, place a
// point target by clicking on the image, edit the description, delete.
// Opens as a dialog showing the real image with click-to-place markers.

import 'package:material_ui/material_ui.dart';
import '../../models/slide.dart';
import '../../models/image_callout.dart';
import '../../services/callout_reference_allocator.dart';
import '../../services/image_viewport_geometry.dart';
import '../../services/web_asset_store.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/bundled_asset.dart';
import '../../utils/image_dimensions.dart';
import '../../utils/project_path.dart';
import '../../widgets/editors/callout_marker_helpers.dart';
import '../../widgets/slides/previews/callout_overlay.dart'
    show calloutImageProvider, resolveIntrinsicSize;

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

  /// De opsommingsregels zoals ze *nu* zijn, inclusief de `(A)` die deze
  /// dialoog erin schrijft.
  ///
  /// Niet `widget.slide.bullets` lezen: de dialoog wordt geopend met de dia van
  /// dát moment en daarna niet opnieuw opgebouwd. Elke bewerking rekende dus
  /// vanaf de begintoestand, en de tweede verwijzing overschreef de letter van
  /// de eerste — die raakte los van haar callout en was in de dialoog niet meer
  /// te bereiken, want de koppeling loopt via precies die letter. Hier is de
  /// stand van de dialoog de waarheid, net als bij [_callouts]; de dia buiten
  /// krijgt hem via [_emit].
  late List<String> _bullets;
  late CalloutPresentation _presentation;
  late BulletRevealMode _reveal;
  int? _selectedCalloutIndex;

  /// Region being dragged out — null when not dragging.
  DragRegion? _dragRegion;

  /// Intrinsieke beeldmaat — nodig om doelen door de geometriecontract te
  /// mappen in plaats van ze blind in slot-ruimte te plaatsen (#1853). Zonder
  /// dit staat een marker op de verkeerde plek: de editor rendert cover, maar
  /// plaatst markers alsof het beeld de slot precies vult.
  Size? _intrinsic;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _callouts = List.of(widget.slide.callouts);
    _bullets = List.of(widget.slide.bullets);
    _presentation = widget.slide.calloutPresentation;
    _reveal = widget.slide.calloutReveal;
    _resolveIntrinsic();
  }

  @override
  void didUpdateWidget(CalloutEditorDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.imagePath != widget.slide.imagePath ||
        oldWidget.projectPath != widget.projectPath) {
      _intrinsic = null;
      _resolveIntrinsic();
    }
  }

  void _resolveIntrinsic() {
    if (_resolving) return;
    final path = widget.slide.imagePath;
    // #1853: lees de intrinsieke maat uit de header waar mogelijk —
    // synchroon, zonder op de image-decode-pipeline te wachten. Voor
    // `mem:`-paden staan de bytes direct in de WebAssetStore; voor
    // bestanden op schijf leest readImageDimensions de header. Alleen
    // `asset:`-paden (gebundelde logo's) vallen terug op de provider.
    if (WebAssetStore.isMemPath(path)) {
      final bytes = WebAssetStore.bytesFor(path);
      if (bytes != null) {
        final dims = imageDimensionsFromBytes(bytes);
        if (dims != null) {
          _intrinsic = Size(dims.width.toDouble(), dims.height.toDouble());
          return;
        }
      }
      return;
    }
    if (!isBundledAssetPath(path)) {
      final resolved = resolveSlideAssetPath(path, widget.projectPath);
      if (resolved == null) return;
      final dims = readImageDimensions(resolved);
      if (dims != null) {
        _intrinsic = Size(dims.width.toDouble(), dims.height.toDouble());
      }
      return;
    }
    // asset: — gebundeld, valt terug op de image provider.
    final provider = calloutImageProvider(path, widget.projectPath);
    if (provider == null) return;
    _resolving = true;
    resolveIntrinsicSize(provider, (size, synchronous) {
      _resolving = false;
      if (synchronous) {
        _intrinsic = size;
        return;
      }
      if (mounted) setState(() => _intrinsic = size);
    });
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        callouts: _callouts,
        calloutPresentation: _presentation,
        calloutReveal: _reveal,
        bullets: _bullets,
      ),
    );
  }

  /// De zichtbare `(A)` aan het eind van de bullet is de koppelsleutel én de
  /// terugval (§2.1): de ziende lezer leest hem af, de editor koppelt de
  /// callout eraan, en een oudere lezer die het front-matter-blok niet kent
  /// houdt er tenminste nog iets aan over. De editor schreef hem niet, en
  /// daardoor hoorde een in de interface gemaakte callout bij géén enkele
  /// bullet: na opslaan en heropenen was hij weg.
  ///
  /// [filteredIndex] telt in de lijst zónder lege regels — die lijst toont de
  /// dialoog — dus hij wordt hier terugvertaald naar de index in
  /// `slide.bullets`. [reference] `null` haalt de verwijzing er juist af.
  void _setReference(int filteredIndex, String? reference) {
    var seen = -1;
    for (var i = 0; i < _bullets.length; i++) {
      if (_bullets[i].trimLeft().isEmpty) continue;
      seen++;
      if (seen != filteredIndex) continue;
      final stripped = _bullets[i].replaceFirst(RegExp(r'\s\([A-Z]\)\s*$'), '');
      _bullets[i] = reference == null ? stripped : '$stripped ($reference)';
      return;
    }
  }

  /// De index in de lijst zónder lege regels van de bullet die [reference]
  /// draagt, of `null` als geen bullet hem draagt.
  int? _filteredIndexForReference(String reference) {
    var seen = -1;
    for (final bullet in _bullets) {
      if (bullet.trimLeft().isEmpty) continue;
      seen++;
      if (_calloutLetterForBullet(bullet) == reference) return seen;
    }
    return null;
  }

  /// Adds a callout to a bullet, assigning the next free reference letter.
  void _addCallout(int bulletIndex) {
    final bullets = _bullets.where((b) => b.trimLeft().isNotEmpty).toList();
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
      _setReference(bulletIndex, ref);
    });
    _emit();
  }

  void _removeCallout(int index) {
    final reference = _callouts[index].reference;
    final bulletIndex = _filteredIndexForReference(reference);
    setState(() {
      _callouts.removeAt(index);
      if (_selectedCalloutIndex == index) {
        _selectedCalloutIndex = null;
      } else if (_selectedCalloutIndex != null &&
          _selectedCalloutIndex! > index) {
        _selectedCalloutIndex = _selectedCalloutIndex! - 1;
      }
    });
    // De letter gaat mee weg: laat je hem staan, dan verwijst de zin naar
    // niets en leest een volgende opening hem als een callout die niet bestaat.
    if (bulletIndex != null) setState(() => _setReference(bulletIndex, null));
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
    Handle handle,
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
        case Handle.topLeft:
          nx = cx.clamp(0.0, r.x + r.w - 0.02);
          ny = cy.clamp(0.0, r.y + r.h - 0.02);
          nw = r.x + r.w - nx;
          nh = r.y + r.h - ny;
        case Handle.topRight:
          ny = cy.clamp(0.0, r.y + r.h - 0.02);
          nw = (cx - r.x).clamp(0.02, 1.0 - r.x);
          nh = r.y + r.h - ny;
        case Handle.bottomLeft:
          nx = cx.clamp(0.0, r.x + r.w - 0.02);
          nw = r.x + r.w - nx;
          nh = (cy - r.y).clamp(0.02, 1.0 - r.y);
        case Handle.bottomRight:
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
    final bullets = _bullets.where((b) => b.trimLeft().isNotEmpty).toList();

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
    final intrinsic = _intrinsic;
    final clippedRefs = _computeClippedRefs(intrinsic);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => _buildImageStack(
              callout,
              intrinsic,
              constraints.maxWidth,
              constraints.maxHeight,
            ),
          ),
        ),
        if (clippedRefs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              '${clippedRefs.map((r) => '($r)').join(', ')} '
              '${l10n.d('valt buiten beeld — pas de focal, zoom of doelpositie aan.')}',
              style: TextStyle(color: AppTheme.warningFg, fontSize: 12),
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

  Widget _buildImageStack(
    ImageCallout callout,
    Size? intrinsic,
    double slotW,
    double slotH,
  ) {
    final painted = intrinsic == null
        ? null
        : ImageViewportGeometry.paintedRect(
            imageW: intrinsic.width,
            imageH: intrinsic.height,
            slotW: slotW,
            slotH: slotH,
            focalX: widget.slide.imageFocalX,
            focalY: widget.slide.imageFocalY,
            zoom: widget.slide.imageZoom,
          );
    double toImgX(double sx) =>
        painted == null ? sx / slotW : (sx - painted.left) / painted.width;
    double toImgY(double sy) =>
        painted == null ? sy / slotH : (sy - painted.top) / painted.height;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Colors.black,
          child: Image(
            image: calloutImageProvider(
              widget.slide.imagePath,
              widget.projectPath,
            )!,
            fit: widget.slide.imageZoom == 0 ? BoxFit.cover : BoxFit.contain,
            alignment: Alignment(
              (widget.slide.imageFocalX * 2) - 1,
              (widget.slide.imageFocalY * 2) - 1,
            ),
          ),
        ),
        _buildGestureLayer(toImgX, toImgY),
        ..._buildMarkers(callout, slotW, slotH, painted),
        if (_dragRegion != null)
          buildDragPreview(_dragRegion!, slotW, slotH, painted),
      ],
    );
  }

  Widget _buildGestureLayer(
    double Function(double) toImgX,
    double Function(double) toImgY,
  ) {
    return GestureDetector(
      onPanStart: (details) {
        if (_presentation != CalloutPresentation.region) return;
        final x = toImgX(details.localPosition.dx);
        final y = toImgY(details.localPosition.dy);
        setState(() {
          _dragRegion = DragRegion(x, y, 0, 0);
        });
      },
      onPanUpdate: (details) {
        if (_dragRegion == null) return;
        final x = toImgX(details.localPosition.dx);
        final y = toImgY(details.localPosition.dy);
        setState(() {
          _dragRegion = DragRegion.fromDrag(
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
        final x = toImgX(details.localPosition.dx);
        final y = toImgY(details.localPosition.dy);
        _moveTarget(_selectedCalloutIndex!, 0, x, y);
      },
      child: Container(color: Colors.transparent),
    );
  }

  /// #1853: bereken welke callout-references buiten beeld vallen. De clipping
  /// hangt af van de aspectratio, niet van de absolute slotmaat, dus een
  /// representatieve slot is voldoende.
  Set<String> _computeClippedRefs(Size? intrinsic) {
    if (intrinsic == null) return {};
    final imgFraction =
        (widget.slide.imageSize > 0 ? widget.slide.imageSize / 100.0 : 0.40)
            .clamp(0.1, 0.70);
    final repW = imgFraction * 16;
    final repH = 9.0;
    final repainted = ImageViewportGeometry.paintedRect(
      imageW: intrinsic.width,
      imageH: intrinsic.height,
      slotW: repW,
      slotH: repH,
      focalX: widget.slide.imageFocalX,
      focalY: widget.slide.imageFocalY,
      zoom: widget.slide.imageZoom,
    );
    final clipped = <String>{};
    for (final c in _callouts) {
      for (final t in c.targets) {
        if (!t.isValid) continue;
        final m = ImageViewportGeometry.mapTarget(
          t,
          painted: repainted,
          slotW: repW,
          slotH: repH,
        );
        if (m.clipped) {
          clipped.add(c.reference);
          break;
        }
      }
    }
    return clipped;
  }

  List<Widget> _buildMarkers(
    ImageCallout callout,
    double slotW,
    double slotH,
    GeoRect? painted,
  ) {
    final markerRadius = slotW * 0.025;
    final handleSize = slotW * 0.02;
    final widgets = <Widget>[];
    final dxFactor = painted?.width ?? slotW;
    final dyFactor = painted?.height ?? slotH;
    for (var i = 0; i < callout.targets.length; i++) {
      final target = callout.targets[i];
      final mapped = painted == null
          ? null
          : ImageViewportGeometry.mapTarget(
              target,
              painted: painted,
              slotW: slotW,
              slotH: slotH,
            );
      if (mapped != null && mapped.clipped) {
        widgets.add(buildClippedBadge(callout.reference, mapped, slotW, slotH));
        continue;
      }
      if (target is CalloutRegion) {
        widgets.addAll(
          _buildRegionMarker(
            callout,
            i,
            target,
            mapped,
            painted,
            slotW,
            slotH,
            markerRadius,
            handleSize,
            dxFactor,
            dyFactor,
          ),
        );
      } else {
        widgets.add(
          _buildPointMarker(
            callout,
            i,
            target as CalloutPoint,
            mapped,
            painted,
            slotW,
            markerRadius,
            dxFactor,
            dyFactor,
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _buildRegionMarker(
    ImageCallout callout,
    int i,
    CalloutRegion target,
    MappedTarget? mapped,
    GeoRect? painted,
    double slotW,
    double slotH,
    double markerRadius,
    double handleSize,
    double dxFactor,
    double dyFactor,
  ) {
    final rx = painted == null ? target.x * slotW : mapped!.x;
    final ry = painted == null ? target.y * slotH : mapped!.y;
    final rw = painted == null ? target.w * slotW : mapped!.w;
    final rh = painted == null ? target.h * slotH : mapped!.h;
    final widgets = <Widget>[];
    // Outline + move handle (drag inside the rect).
    widgets.add(
      Positioned(
        left: rx,
        top: ry,
        width: rw,
        height: rh,
        child: GestureDetector(
          onPanUpdate: (details) {
            final nx = (target.x + details.delta.dx / dxFactor).clamp(0.0, 1.0);
            final ny = (target.y + details.delta.dy / dyFactor).clamp(0.0, 1.0);
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
            border: Border.all(color: Colors.black, width: markerRadius * 0.18),
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
    for (final handle in Handle.values) {
      final (hx, hy) = handle.offset(rx, ry, rw, rh);
      widgets.add(
        Positioned(
          left: hx - handleSize / 2,
          top: hy - handleSize / 2,
          child: GestureDetector(
            onPanUpdate: (details) {
              final nx = painted == null
                  ? (hx + details.delta.dx) / slotW
                  : (hx + details.delta.dx - painted.left) / painted.width;
              final ny = painted == null
                  ? (hy + details.delta.dy) / slotH
                  : (hy + details.delta.dy - painted.top) / painted.height;
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
    return widgets;
  }

  Widget _buildPointMarker(
    ImageCallout callout,
    int i,
    CalloutPoint p,
    MappedTarget? mapped,
    GeoRect? painted,
    double slotW,
    double markerRadius,
    double dxFactor,
    double dyFactor,
  ) {
    final mx = painted == null ? p.x * slotW : mapped!.x;
    final my = painted == null ? p.y * slotW : mapped!.y;
    return Positioned(
      left: mx - markerRadius,
      top: my - markerRadius,
      child: GestureDetector(
        onPanUpdate: (details) {
          final nx = (p.x + details.delta.dx / dxFactor).clamp(0.0, 1.0);
          final ny = (p.y + details.delta.dy / dyFactor).clamp(0.0, 1.0);
          _moveTarget(_selectedCalloutIndex!, i, nx, ny);
        },
        child: Container(
          width: markerRadius * 2,
          height: markerRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accentFg,
            border: Border.all(color: Colors.black, width: markerRadius * 0.18),
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
