import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/image_callout.dart';
import '../../models/video_source.dart';
import '../../services/image_viewport_geometry.dart';
import '../../theme/app_theme.dart';
import '../../utils/atomic_file.dart';
import '../../utils/bundled_asset.dart';
import '../../utils/image_dimensions.dart';
import '../../utils/image_focal.dart';
import '../../utils/image_limits.dart';
import '../../utils/log.dart';
import '../../utils/project_path.dart';
import '../../services/web_asset_store.dart';
import '../../widgets/editors/callout_marker_helpers.dart';

/// The crop choices the author made: the (possibly changed) zoom and the
/// normalized focal point that decides which part of the picture stays in view.
///
/// [rotatedImagePath] is the *new* asset the dialog wrote when the author turned
/// the picture, and `null` when they did not. The caller puts it on the slide in
/// place of the old path.
///
/// **Why a new file and not the old one** (IMAGE_ROTATION.md, option A). Rotating
/// used to overwrite the source, which meant an unrecoverable edit to a file the
/// user owns — and one image can back several slides and several decks, so a turn
/// in this deck silently turned it in the others too. The crop and the zoom next
/// to it never touched the file; only rotation did, and nothing in the dialog
/// said so. A derived copy keeps rotation a decision of *this* slide while
/// leaving every other reference, and the original, exactly as they were.
class ImageCropResult {
  final int imageSize;
  final double focalX;
  final double focalY;

  /// The path the slide should carry now, or `null` when nothing was rotated.
  final String? rotatedImagePath;

  const ImageCropResult(
    this.imageSize,
    this.focalX,
    this.focalY, {
    this.rotatedImagePath,
  });
}

/// The `.r90` / `.r180` / `.r270` marker a rotated copy carries in its name.
///
/// It is part of the name rather than a sidecar because it has to survive every
/// route a deck travels — the package, the git plane, a plain file copy — and a
/// name is the only carrier all of those keep. It also makes the derivation
/// legible: someone looking at `images/` sees that `foto.r90.jpg` came from
/// `foto.jpg` without needing OciDeck to tell them.
final RegExp _rotationSuffix = RegExp(r'\.r(90|180|270)$');

/// Split [stem] into its base name and the rotation already baked into it.
///
/// `foto` → `('foto', 0)` · `foto.r90` → `('foto', 90)`.
({String base, int degrees}) splitRotationSuffix(String stem) {
  final match = _rotationSuffix.firstMatch(stem);
  if (match == null) return (base: stem, degrees: 0);
  return (
    base: stem.substring(0, match.start),
    degrees: int.parse(match.group(1)!),
  );
}

/// The file name a copy rotated [quarterTurns] further than [currentName] gets.
///
/// The angle **accumulates onto the one already in the name** instead of nesting
/// a second suffix, so turning `foto.r90.jpg` another quarter gives
/// `foto.r180.jpg` and never `foto.r90.r90.jpg`. A deck therefore holds at most
/// three derived copies of a picture rather than a chain that grows with every
/// visit to the dialog.
///
/// Returns `null` when the rotation cancels out — a quarter turn back from
/// `foto.r90.jpg` is `foto.jpg`, which already exists, so the caller points the
/// slide at it again instead of writing a fourth identical file.
String? rotatedCopyName(String currentName, int quarterTurns) {
  final ext = p.extension(currentName);
  final split = splitRotationSuffix(p.basenameWithoutExtension(currentName));
  final total = (split.degrees + quarterTurns * 90) % 360;
  if (total == 0) return null;
  return '${split.base}.r$total$ext';
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
/// `_writeRotatedCopy` slikt een schrijffout bewust in: een volle schijf of
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
  Color? backgroundColor,
  List<ImageCallout>? callouts,
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
      callouts: callouts ?? const [],
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
  final Color? backgroundColor;
  final List<ImageCallout> callouts;

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
    this.callouts = const [],
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
    // #1854: probeer de intrinsieke maat synchroon te lezen uit de header,
    // zodat callout-markeringen direct meeliften — de stream-listener vuurt
    // in een testomgeving niet altijd binnen de eerste pump.
    final bytes = _originalBytes;
    if (bytes != null) {
      final dims = imageDimensionsFromBytes(bytes);
      if (dims != null) {
        _intrinsic = Size(dims.width.toDouble(), dims.height.toDouble());
      }
    }
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
  /// Schrijf de gedraaide afbeelding als een NIEUWE asset en geef het pad terug
  /// dat de dia voortaan moet dragen. `null` als er niets te schrijven viel.
  ///
  /// **Het origineel blijft staan** (IMAGE_ROTATION.md, optie A). Tot 2026-08-30
  /// overschreef deze methode het bronbestand: geen undo, geen kopie, en omdat
  /// één afbeelding meer dia's en meer decks kan voeden, draaide een kwartslag
  /// hier de foto ook in decks die de auteur niet openhad. De kopie landt naast
  /// de bron — dat is de `images/`-map van het deck, of de stagingmap van een
  /// nog niet opgeslagen deck, want een dia mag alleen naar binnen de
  /// projectmap wijzen. Zo reist ze mee in het pakket en het git-vlak als elke
  /// andere deck-asset, zonder een OciDeck-artefact in de fotomap van de
  /// gebruiker achter te laten.
  ///
  /// Synchroon, zodat de dialoog direct kan sluiten — de afbeelding is klein en
  /// lokaal. Elke uitgang die niets schrijft zet [lastRotationWriteFailure];
  /// zie daar waarom dat nodig was.
  String? _writeRotatedCopy() {
    lastRotationWriteFailure = null;
    if (_rotationQuarterTurns == 0) return null;
    if (_originalBytes == null) {
      lastRotationWriteFailure = 'de oorspronkelijke bytes zijn nooit geladen';
      return null;
    }
    final original = _originalBytes!;
    final decoded = img.decodeImage(original);
    if (decoded == null) {
      lastRotationWriteFailure = 'de afbeelding was niet te decoderen';
      return null;
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
      // Web kent geen bestandssysteem: dezelfde regel, andere opslag. `put`
      // levert een nieuw `mem:`-pad en laat het oude staan, zodat een dia die
      // nog naar de ongedraaide bytes wijst die ook houdt.
      final name = WebAssetStore.nameFor(widget.imagePath) ?? 'afbeelding.png';
      final copyName = rotatedCopyName(name, _rotationQuarterTurns) ?? name;
      return WebAssetStore.put(bytes, name: copyName);
    }

    final resolved = resolveSlideAssetPath(
      widget.imagePath,
      widget.projectPath,
    );
    if (resolved == null) {
      lastRotationWriteFailure = 'het pad viel buiten de projectmap';
      return null;
    }

    final copyName = rotatedCopyName(
      p.basename(widget.imagePath),
      _rotationQuarterTurns,
    );
    if (copyName == null) {
      // De draai heft zichzelf op: `foto.r90.jpg` een kwartslag terug ís
      // `foto.jpg`. Staat dat er nog, wijs de dia er dan gewoon weer op in
      // plaats van een vierde identiek bestand te schrijven.
      final base = _basePathFor(widget.imagePath);
      final baseResolved = base == null
          ? null
          : resolveSlideAssetPath(base, widget.projectPath);
      if (baseResolved != null && File(baseResolved).existsSync()) return base;
      // Het origineel is weg (hernoemd, opgeruimd). Dan is de gedraaide kopie
      // die er nu ligt het enige dat de dia heeft; laat hem staan.
      return null;
    }

    // Laat ons eigen beeld los vóór we schrijven. De voorvertoning heeft dit
    // bestand net gedecodeerd, en op Windows blijft een net gelezen bestand nog
    // even vastgehouden (errno 32, "used by another process"). We schrijven nu
    // wel naar een ánder pad, maar de doelnaam kan van een eerdere ronde al
    // bestaan — dan speelt dezelfde blokkade weer op.
    _releasePreview();
    final target = p.join(p.dirname(resolved), copyName);
    try {
      writeBytesAtomicSyncRetrying(File(target), bytes);
    } on Object catch (e) {
      // Een schrijffout mag de crop-keuze niet blokkeren — maar hij mag ook
      // niet spoorloos zijn. De dia houdt dan zijn oude, ongedraaide pad.
      lastRotationWriteFailure = e;
      logWarning('image crop: gedraaide kopie niet weggeschreven', e);
      return null;
    }
    // Bump de versie zodat de renderlaag een nieuwe CappedImage-cacheKey
    // gebruikt. Het doelpad kan van een eerdere ronde in de cache zitten met
    // andere bytes.
    bumpImageVersion(target);
    return p.join(p.dirname(widget.imagePath), copyName);
  }

  /// Het pad zonder rotatiemarkering: `images/foto.r90.jpg` → `images/foto.jpg`.
  /// `null` als er geen markering op zat.
  String? _basePathFor(String path) {
    final ext = p.extension(path);
    final split = splitRotationSuffix(p.basenameWithoutExtension(path));
    if (split.degrees == 0) return null;
    return p.join(p.dirname(path), '${split.base}$ext');
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
      _size = widget.imageSize;
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

  /// #1854: callout-markeringen over de bijsnijdstage, zodat de auteur ziet
  /// welke doelen al geplaatst zijn en of bijsnijden ze uit beeld schuift.
  /// De markeringen volgen de live focal-/zoom-waarden van de dialoog.
  Widget _calloutOverlay(double frameW, double frameH) {
    final callouts = widget.callouts;
    final intrinsic = _intrinsic;
    if (callouts.isEmpty || intrinsic == null) return const SizedBox();
    final painted = ImageViewportGeometry.paintedRect(
      imageW: intrinsic.width,
      imageH: intrinsic.height,
      slotW: frameW,
      slotH: frameH,
      focalX: _fx,
      focalY: _fy,
      zoom: _size,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final c in callouts)
          ...buildStaticCalloutMarkers(c, frameW, frameH, painted),
      ],
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
                  ColoredBox(
                    color:
                        widget.backgroundColor ??
                        Theme.of(context).colorScheme.surface,
                  ),
                  _stageContent(frameW, frameH),
                  // Rule-of-thirds guides make it easy to line a subject up.
                  const IgnorePointer(child: _ThirdsOverlay()),
                  // #1854: callout-markeringen meeladen zodat je ziet welke
                  // doelen je al geplaatst hebt — bijsnijden schuift ze
                  // mogelijk het beeld uit.
                  IgnorePointer(child: _calloutOverlay(frameW, frameH)),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.zoom_out, size: 18, color: AppTheme.slate500),
                  Expanded(
                    child: Slider(
                      // In cover-modus (_size == 0) toont de schuif op minZoom;
                      // slepen verlaat cover en stelt een echte zoom in.
                      value: _size.toDouble().clamp(
                        widget.minZoom.toDouble(),
                        widget.maxZoom.toDouble(),
                      ),
                      min: widget.minZoom.toDouble(),
                      max: widget.maxZoom.toDouble(),
                      divisions: (widget.maxZoom - widget.minZoom) ~/ 10,
                      label: _cover ? '${widget.minZoom}%' : '$_size%',
                      onChanged: (v) => setState(() => _size = v.round()),
                    ),
                  ),
                  Icon(Icons.zoom_in, size: 18, color: AppTheme.slate500),
                ],
              ),
              // Cover (imageSize 0) staat onder de schuif en is onbereikbaar
              // zodra je eenmaal inzoomt — deze knop zet het terug (#1879).
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _size = 0),
                  icon: Icon(
                    Icons.crop_free,
                    size: 16,
                    color: _cover ? AppTheme.accentFg : AppTheme.slate500,
                  ),
                  label: Text(
                    context.l10n.d('Vullen (bijsnijden)'),
                    style: TextStyle(
                      fontSize: 12,
                      color: _cover ? AppTheme.accentFg : AppTheme.slate600,
                    ),
                  ),
                ),
              ),
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
                // Draaien is de enige van de drie die iets op schijf zet: een
                // gedraaide kopie naast het origineel (IMAGE_ROTATION.md, optie
                // A). Dat is geen waarschuwing meer — het origineel blijft
                // heel — maar wel iets dat de auteur moet weten, want er
                // verschijnt een bestand in de map en de dia gaat ernaar
                // wijzen. Tot 2026-08-30 stond hier de waarschuwing die bij het
                // oude, overschrijvende gedrag hoorde.
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppTheme.slate500,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.d(
                          'Draaien schrijft een gedraaide kopie naast het origineel; je oorspronkelijke bestand blijft ongewijzigd.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate500,
                        ),
                      ),
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
              final rotated = _writeRotatedCopy();
              Navigator.of(context).pop(
                ImageCropResult(_size, _fx, _fy, rotatedImagePath: rotated),
              );
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
