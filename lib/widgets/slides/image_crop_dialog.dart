import 'dart:async';
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
import '../../utils/log.dart';
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
/// [imageSize] is `imageZoom` for every caller (0 = fill/cover, 100 = whole
/// image, up to [maxZoom]); the full-bleed slides use it with the same
/// semantics.
///
/// Returns the chosen values, or `null` when the author cancels.
/// Waaróm de laatste rotatie niet op schijf landde — `null` zolang het goed
/// ging.
///
/// `_writeRotatedBytes` slikt een schrijffout bewust in: een volle schijf of
/// een alleen-lezen map mag de bijsnijdkeuze niet blokkeren. Maar daardoor was
/// "draaien doet niets" op Windows twee releases lang onzichtbaar — óók in CI,
/// want de toets zag alleen pixels die niet klopten en `logWarning` schrijft
/// naar de VM-servicestroom, niet naar de testuitvoer. Zonder dit veld is de
/// enige manier om de oorzaak te leren: gokken en een uur op de spiegel wachten.
///
/// Draagt alleen de fout of een korte reden, nooit een pad of bestandsinhoud.
@visibleForTesting
Object? lastRotationWriteFailure;

Future<ImageCropResult?> showImageCropDialog(
  BuildContext context, {
  required String imagePath,
  String? projectPath,
  required double frameAspect,
  required int imageSize,
  required double focalX,
  required double focalY,
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

  // imageSize 0 means "fill/cover" — the image covers the slot with no zoom.
  // Any other value is a zoom percentage, so the image is shown at that scale.
  bool get _cover => _size == 0;

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
    _loadOriginalBytes();
    _provider = _voorvertoning();
    final provider = _provider;
    if (provider != null) {
      _listenToStream(provider);
    }
  }

  /// De provider voor de voorvertoning.
  ///
  /// **Uit het geheugen zodra we de bytes toch al hebben, en dat is geen
  /// optimalisatie.** `FileImage` laat de engine het bestand openen met
  /// `ui.ImmutableBuffer.fromFilePath`, en die maakt er op Windows een
  /// geheugenafbeelding van. Zolang die leeft, weigert Windows het bestand te
  /// vervangen of te verwijderen — en dit venster toont nu juist het bestand dat
  /// het straks gaat overschrijven. Daar liep het draaien op stuk: `rename`
  /// mislukte, de terugval mocht het doel niet verwijderen (errno 32), en de
  /// schrijffout werd ingeslikt zodat de gebruiker een preview zag draaien en
  /// een bestand hield dat onveranderd bleef.
  ///
  /// De bytes staan er al voor het roteren, dus dezelfde bytes voeden de
  /// voorvertoning. Eén leesbeurt in plaats van twee, en geen afbeelding op een
  /// bestand dat we willen herschrijven. Lukt het lezen niet (of gaat het om een
  /// bundled asset of een `mem:`-pad), dan blijft de oude route staan.
  ImageProvider? _voorvertoning() {
    final bytes = _originalBytes;
    if (bytes != null && !isBundledAssetPath(widget.imagePath)) {
      return cappedMemoryImage(bytes);
    }
    return _cropProvider(widget.imagePath, widget.projectPath);
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
  ///
  /// Elke uitgang die niets schrijft zet [lastRotationWriteFailure]; zie daar
  /// waarom dat nodig was.
  void _writeRotatedBytes() {
    lastRotationWriteFailure = null;
    if (_rotationQuarterTurns == 0 || _originalBytes == null) {
      if (_rotationQuarterTurns != 0) {
        lastRotationWriteFailure =
            'de oorspronkelijke bytes zijn nooit geladen';
      }
      return;
    }
    final original = _originalBytes!;
    final decoded = img.decodeImage(original);
    if (decoded == null) {
      lastRotationWriteFailure = 'de afbeelding was niet te decoderen';
      return;
    }
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
    if (resolved == null) {
      lastRotationWriteFailure = 'het pad viel buiten de projectmap';
      return;
    }
    // Laat ons eigen beeld los vóór we schrijven. De voorvertoning heeft dit
    // bestand net gedecodeerd, en op Windows blijft een net gelezen bestand nog
    // even vastgehouden (errno 32, "used by another process"). Daar strandde de
    // rotatie: `rename` mag daar niet over een bestaand bestand, de terugval
    // wil het doel dan verwijderen, en verwijderen mag niet zolang iemand het
    // openhoudt — en die iemand waren wij. De dialoog gaat toch dicht, en na
    // afloop verhoogt `bumpImageVersion` de cachesleutel, dus de renderlaag
    // haalt het beeld zo meteen opnieuw op.
    _releasePreview();
    try {
      writeBytesAtomicSyncRetrying(File(resolved), bytes);
    } on Object catch (e) {
      // Een schrijffout mag de crop-keuze niet blokkeren — maar hij mag ook
      // niet spoorloos zijn.
      lastRotationWriteFailure = e;
      logWarning('image crop: rotatie niet weggeschreven', e);
    }
    // Bump de versie zodat de renderlaag een nieuwe CappedImage-cacheKey
    // gebruikt (path#N i.p.v. path#(N-1)). De Image-widget ziet een nieuwe
    // provider identiteit en re-resolve, in plaats van de verouderde
    // cache-entry te tonen. Werkt voor zowel cappedFileImage als
    // boundedFileImage (thumbnails).
    bumpImageVersion(resolved);
  }

  /// Geeft de voorvertoning en haar plek in de beeldcache op.
  ///
  /// `evict()` levert een Future, maar voor een [FileImage] is de sleutel een
  /// `SynchronousFuture` — het opruimen gebeurt dus meteen, en daarom hoeft
  /// deze methode niet async te zijn. Dat is hier geen detail: zou de dialoog
  /// op een echte Future moeten wachten, dan sluit hij pas ná de schijf-IO, en
  /// dat is precies wat het oorspronkelijke ontwerp bewust vermeed.
  void _releasePreview() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
    unawaited(_provider?.evict() ?? Future<bool>.value(false));
    _provider = null;
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
        _provider = _voorvertoning();
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
    return OverflowBox(
      minWidth: frameW * scale,
      maxWidth: frameW * scale,
      minHeight: frameH * scale,
      maxHeight: frameH * scale,
      alignment: align,
      child: Image(image: provider, fit: BoxFit.contain, gaplessPlayback: true),
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
              if (s.scale != 1.0) {
                setState(() {
                  // Pinch past de zoom aan: van cover (0) naar inzoomen
                  // (minZoom..maxZoom). De slider volgt mee.
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
              if (!_cover) ...[
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
