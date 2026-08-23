import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../l10n/app_localizations.dart';
import '../../models/video_source.dart';
import '../../theme/app_theme.dart';
import '../../utils/atomic_file.dart';
import '../../utils/bundled_asset.dart';
import '../../utils/image_focal.dart';
import '../../utils/image_limits.dart';
import '../../utils/project_path.dart';
import '../../services/web_asset_store.dart';

/// The crop choices the author made: the (possibly changed) zoom and the
/// normalized focal point that decides which part of the picture stays in view.
/// Rotation (if any) is written back to the file by the dialog itself.
class ImageCropResult {
  final int imageSize;
  final double focalX;
  final double focalY;
  const ImageCropResult(this.imageSize, this.focalX, this.focalY);
}

/// A crop needs a picture we can decode locally to show and drag. Remote (URL)
/// images are excluded so the editor never fetches through the SSRF gate just to
/// crop; the caller hides the button for those.
bool imageIsCroppable(String imagePath) =>
    imagePath.isNotEmpty && !VideoSource.looksLikeUrl(imagePath);

/// Opens an interactive crop/reposition dialog for [imagePath] (resolved against
/// [projectPath]). The stage mirrors exactly how the slide renders the image in
/// its slot ([frameAspect] = slot width / height), so what the author drags into
/// place is what the slide shows.
///
/// [enableZoom] is true for the full-slide image and title background, where
/// [imageSize] is a real zoom (0 = fill/cover, 100 = whole image, up to
/// [maxZoom]). For the bullets panel and two-images slots it is false: there
/// [imageSize] is the column width, so the dialog only repositions the cover
/// crop and returns [imageSize] unchanged.
///
/// Returns the chosen values, or `null` when the author cancels.
Future<ImageCropResult?> showImageCropDialog(
  BuildContext context, {
  required String imagePath,
  String? projectPath,
  required double frameAspect,
  required int imageSize,
  required double focalX,
  required double focalY,
  bool enableZoom = false,
  int minZoom = 100,
  int maxZoom = 400,
  Color backgroundColor = Colors.black,
}) {
  return showDialog<ImageCropResult>(
    context: context,
    builder: (_) => _ImageCropDialog(
      imagePath: imagePath,
      projectPath: projectPath,
      frameAspect: frameAspect <= 0 ? 16 / 9 : frameAspect,
      imageSize: imageSize,
      focalX: focalX,
      focalY: focalY,
      enableZoom: enableZoom,
      minZoom: minZoom,
      maxZoom: maxZoom,
      backgroundColor: backgroundColor,
    ),
  );
}

ImageProvider? _cropProvider(String imagePath, String? projectPath) {
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

class _ImageCropDialog extends StatefulWidget {
  final String imagePath;
  final String? projectPath;
  final double frameAspect;
  final int imageSize;
  final double focalX;
  final double focalY;
  final bool enableZoom;
  final int minZoom;
  final int maxZoom;
  final Color backgroundColor;

  const _ImageCropDialog({
    required this.imagePath,
    required this.projectPath,
    required this.frameAspect,
    required this.imageSize,
    required this.focalX,
    required this.focalY,
    required this.enableZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.backgroundColor,
  });

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  late int _size;
  late double _fx;
  late double _fy;
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _intrinsic;
  int _rotationQuarterTurns = 0; // 0, 1, 2, 3 × 90°
  Uint8List? _originalBytes;
  double _scaleStart = 100; // zoom-niveau bij start van een pinch-gebaar

  // In the panel slots (enableZoom == false) the image always covers its
  // column, so treat it as cover regardless of what `imageSize` (the column
  // width) happens to be. For image/title, cover is the explicit 0 zoom.
  bool get _cover => widget.enableZoom ? _size == 0 : true;

  /// Kan draaien: geen bundled assets (die zijn read-only) en geen URL's.
  bool get _canRotate =>
      !isBundledAssetPath(widget.imagePath) &&
      !VideoSource.looksLikeUrl(widget.imagePath);

  @override
  void initState() {
    super.initState();
    _size = widget.imageSize;
    _fx = widget.focalX.clamp(0.0, 1.0);
    _fy = widget.focalY.clamp(0.0, 1.0);
    _provider = _cropProvider(widget.imagePath, widget.projectPath);
    _loadOriginalBytes();
    final provider = _provider;
    if (provider != null) {
      _listenToStream(provider);
    }
  }

  void _listenToStream(ImageProvider provider) {
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      info.dispose();
      if (mounted) setState(() => _intrinsic = size);
    }, onError: (_, _) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _loadOriginalBytes() {
    if (!_canRotate) return;
    if (WebAssetStore.isMemPath(widget.imagePath)) {
      _originalBytes = WebAssetStore.bytesFor(widget.imagePath);
    } else {
      final resolved = resolveSlideAssetPath(
        widget.imagePath,
        widget.projectPath,
      );
      if (resolved != null) {
        try {
          _originalBytes = File(resolved).readAsBytesSync();
        } on Object {
          _originalBytes = null;
        }
      }
    }
  }

  void _rotate(int quarterTurns) {
    final original = _originalBytes;
    if (original == null) return;
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + quarterTurns) % 4;
      if (_rotationQuarterTurns < 0) _rotationQuarterTurns += 4;
      // Decodeer, roteer, codeer opnieuw. Behoud het originele formaat.
      final decoded = img.decodeImage(original);
      if (decoded == null) return;
      final rotated = img.copyRotate(
        decoded,
        angle: _rotationQuarterTurns * 90.0,
      );
      final encoded =
          widget.imagePath.endsWith('.jpg') ||
              widget.imagePath.endsWith('.jpeg')
          ? img.encodeJpg(rotated)
          : widget.imagePath.endsWith('.gif')
          ? img.encodeGif(rotated)
          : img.encodePng(rotated);
      final bytes = Uint8List.fromList(encoded);
      // Ververs de preview met de geroteerde bytes.
      _stream?.removeListener(_listener!);
      _stream = null;
      _listener = null;
      _intrinsic = null;
      _provider = cappedMemoryImage(bytes);
      _listenToStream(_provider!);
    });
  }

  /// Schrijf de geroteerde afbeelding terug naar het bestand (of `mem:`-pad).
  /// Stille no-op als er niet is gedraaid of als schrijven niet kan. Synchroon
  /// zodat de dialoog direct kan sluiten — de afbeelding is klein en lokaal.
  void _writeRotatedBytes() {
    if (_rotationQuarterTurns == 0 || _originalBytes == null) return;
    final original = _originalBytes!;
    final decoded = img.decodeImage(original);
    if (decoded == null) return;
    final rotated = img.copyRotate(
      decoded,
      angle: _rotationQuarterTurns * 90.0,
    );
    final encoded =
        widget.imagePath.endsWith('.jpg') || widget.imagePath.endsWith('.jpeg')
        ? img.encodeJpg(rotated)
        : widget.imagePath.endsWith('.gif')
        ? img.encodeGif(rotated)
        : img.encodePng(rotated);
    final bytes = Uint8List.fromList(encoded);
    if (WebAssetStore.isMemPath(widget.imagePath)) {
      // Vervang de bytes op hetzelfde pad. De renderlaag leest de nieuwe bytes
      // via bytesFor() en krijgt een ander cacheKey-object, dus de Image-widget
      // re-resolve automatisch.
      WebAssetStore.replace(widget.imagePath, bytes);
      return;
    }
    final resolved = resolveSlideAssetPath(
      widget.imagePath,
      widget.projectPath,
    );
    if (resolved != null) {
      try {
        writeBytesAtomicSync(File(resolved), bytes);
      } on Object {
        // Een schrijffout mag de crop-keuze niet blokkeren.
      }
      // Bump de versie zodat de renderlaag een nieuwe CappedImage-cacheKey
      // gebruikt (path#N i.p.v. path#(N-1)). De Image-widget ziet een nieuwe
      // provider identiteit en re-resolve, in plaats van de verouderde
      // cache-entry te tonen. Werkt voor zowel cappedFileImage als
      // boundedFileImage (thumbnails).
      bumpImageVersion(resolved);
    }
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _reset() {
    setState(() {
      _fx = 0.5;
      _fy = 0.5;
      if (_rotationQuarterTurns != 0) {
        _rotationQuarterTurns = 0;
        // Reset naar originele afbeelding.
        _stream?.removeListener(_listener!);
        _stream = null;
        _listener = null;
        _intrinsic = null;
        _provider = _cropProvider(widget.imagePath, widget.projectPath);
        final provider = _provider;
        if (provider != null) _listenToStream(provider);
      }
    });
  }

  // Drag moves the picture with the finger: pulling it right reveals more of its
  // left edge, so the focal point shifts left. The overflow (how far the image
  // extends past the slot) sets the pixel-to-focal ratio, so the drag tracks the
  // image 1:1 and clamps at the edges.
  void _drag(Offset delta, double frameW, double frameH) {
    double overflowX;
    double overflowY;
    if (_cover) {
      final intrinsic = _intrinsic;
      final imageAspect = intrinsic == null
          ? widget.frameAspect
          : intrinsic.width / intrinsic.height;
      double shownW;
      double shownH;
      if (imageAspect >= widget.frameAspect) {
        shownH = frameH;
        shownW = frameH * imageAspect;
      } else {
        shownW = frameW;
        shownH = frameW / imageAspect;
      }
      overflowX = shownW - frameW;
      overflowY = shownH - frameH;
    } else {
      final scale = _size / 100.0;
      overflowX = frameW * (scale - 1);
      overflowY = frameH * (scale - 1);
    }
    setState(() {
      if (overflowX > 0.5) {
        _fx = (_fx - delta.dx / overflowX).clamp(0.0, 1.0);
      }
      if (overflowY > 0.5) {
        _fy = (_fy - delta.dy / overflowY).clamp(0.0, 1.0);
      }
    });
  }

  Widget _stageContent(double frameW, double frameH) {
    final provider = _provider;
    if (provider == null) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: AppTheme.slate400,
          size: 48,
        ),
      );
    }
    final align = focalAlignment(_fx, _fy);
    if (_cover) {
      return Image(
        image: provider,
        fit: BoxFit.cover,
        alignment: align,
        width: frameW,
        height: frameH,
        gaplessPlayback: true,
      );
    }
    final scale = _size / 100.0;
    return Align(
      alignment: align,
      child: SizedBox(
        width: frameW * scale,
        height: frameH * scale,
        child: Image(
          image: provider,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _stage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameW = constraints.maxWidth;
        final frameH = constraints.maxHeight;
        return MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Eén scale-recognizer die zowel slepen (1 vinger) als pinch-zoom
            // (2 vingers) afhandelt. onPanUpdate zou met onScaleUpdate botsen
            // en nooit vuren — vandaar dat _drag via focalPointDelta loopt.
            onScaleStart: (_) => _scaleStart = _size.toDouble(),
            onScaleUpdate: (s) {
              if (widget.enableZoom && s.scale != 1.0) {
                setState(() {
                  // Pinch past de zoom aan: van cover (0) naar inzoomen
                  // (minZoom..maxZoom). De slider volgt同步.
                  final next = (_scaleStart * s.scale).round();
                  _size = next.clamp(widget.minZoom, widget.maxZoom);
                });
              }
              if (s.focalPointDelta != Offset.zero) {
                _drag(s.focalPointDelta, frameW, frameH);
              }
            },
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: widget.backgroundColor),
                  _stageContent(frameW, frameH),
                  // Rule-of-thirds guides make it easy to line a subject up.
                  const IgnorePointer(child: _ThirdsOverlay()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        title: Text(l10n.d('Afbeelding aanpassen')),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.d(
                  'Sleep de afbeelding om te kiezen welk deel zichtbaar blijft.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate500),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 340,
                  minHeight: 160,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.slate300),
                  ),
                  child: AspectRatio(
                    aspectRatio: widget.frameAspect,
                    child: _stage(),
                  ),
                ),
              ),
              if (widget.enableZoom && !_cover) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.zoom_out, size: 18, color: AppTheme.slate500),
                    Expanded(
                      child: Slider(
                        value: _size.toDouble().clamp(
                          widget.minZoom.toDouble(),
                          widget.maxZoom.toDouble(),
                        ),
                        min: widget.minZoom.toDouble(),
                        max: widget.maxZoom.toDouble(),
                        divisions: (widget.maxZoom - widget.minZoom) ~/ 10,
                        label: '$_size%',
                        onChanged: (v) => setState(() => _size = v.round()),
                      ),
                    ),
                    Icon(Icons.zoom_in, size: 18, color: AppTheme.slate500),
                  ],
                ),
              ],
              if (_canRotate && _originalBytes != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _rotate(-1),
                      icon: const Icon(Icons.rotate_left, size: 20),
                      label: Text(l10n.d('Linksom')),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () => _rotate(1),
                      icon: const Icon(Icons.rotate_right, size: 20),
                      label: Text(l10n.d('Rechtsom')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _reset, child: Text(l10n.d('Herstel'))),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () {
              _writeRotatedBytes();
              Navigator.of(context).pop(ImageCropResult(_size, _fx, _fy));
            },
            child: Text(l10n.d('Klaar')),
          ),
        ],
      ),
    );
  }
}

class _ThirdsOverlay extends StatelessWidget {
  const _ThirdsOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ThirdsPainter());
  }
}

class _ThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
