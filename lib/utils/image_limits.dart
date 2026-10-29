import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'project_path.dart';

/// Upper bound on the decoded dimensions of a slide/background image.
///
/// `ui.instantiateImageCodec` allocates ~`width × height × 4` bytes regardless
/// of the box the image is painted in, so a small but huge-dimensioned file
/// (e.g. a uniformly-coloured 30000×30000 PNG that is a few KB on disk) decodes
/// to gigabytes and OOM-crashes the app. Capping the decode bounds memory to
/// ~`4096² × 4 ≈ 64 MiB` worst case while staying sharp for any realistic
/// display or 4K export.
const int kMaxImageDecodeDimension = 4096;

/// Treden waarop een scherm de decode afrondt. Een vaste trede houdt de
/// cachesleutel stabiel wanneer het vak een paar pixels verschuift, en 4096
/// blijft het absolute plafond (#2625).
const List<int> kDecodeEdgeSteps = [1024, 2048, 4096];

/// Export rastert op 1920×1080. De trede 2048 is daar scherp genoeg en scheelt
/// bij een fotodeck fors tegen de bronresolutie.
const int kExportImageDecodeEdge = 2048;

/// Onder deze grens blijft de miniatuur op [ResizeImage], zoals de strook dat
/// al deed. Daarboven gebruikt het scherm [CappedImage], zodat een GIF die in
/// de trede past blijft animeren.
const int kHardResizeDecodeEdge = 512;

/// Maximum aantal frames dat een animated image (GIF/WebP/APNG) mag hebben.
///
/// De dimensie-cap vangt één frame, niet de animatie als geheel: een GIF met
/// 10.000 frames à 4096²×4 bytes is honderden GiB. Boven deze grens tonen we
/// alleen het eerste frame — dezelfde trade-off als de dimensie-cap al maakt
/// voor over-cap afbeeldingen.
const int kMaxImageFrames = 256;

/// The decode target for the memory cap. Returns `(null, null)` — i.e. decode at
/// native resolution — whenever the image already fits within
/// [kMaxImageDecodeDimension] on both axes, and only otherwise scales the
/// longest side down to the cap (aspect ratio preserved).
///
/// Decoding at native resolution within the cap is what lets **animated** images
/// (GIF/WebP/APNG) keep every frame: a concrete decode target (as [ResizeImage]
/// always passes, even when it equals the intrinsic size) sends the engine down
/// the resize path, which collapses an animated image to just its first frame.
/// Over-cap images are still scaled down, so the decode-bomb defence is intact —
/// such an image simply shows its first frame (a rare, safe trade-off).
({int? width, int? height}) cappedDecodeTarget(
  int width,
  int height, {
  int maxEdge = kMaxImageDecodeDimension,
}) {
  if (width <= 0 || height <= 0) return (width: null, height: null);
  if (width <= maxEdge && height <= maxEdge) {
    return (width: null, height: null);
  }
  final aspect = width / height;
  if (width >= height) {
    final targetHeight = (maxEdge / aspect).round();
    return (width: maxEdge, height: math.max(1, targetHeight));
  }
  final targetWidth = (maxEdge * aspect).round();
  return (width: math.max(1, targetWidth), height: maxEdge);
}

/// Langste zijde van het vak, naar boven afgerond op [kDecodeEdgeSteps].
///
/// Een onbegrensd of leeg vak valt terug op het absolute plafond: liever iets
/// te scherp dan een dia die stilzwijgend op een miniatuur decodeert.
int decodeEdgeForBox(
  double maxWidth,
  double maxHeight,
  double devicePixelRatio,
) {
  final width = maxWidth.isFinite ? maxWidth : 0.0;
  final height = maxHeight.isFinite ? maxHeight : 0.0;
  final logical = math.max(width, height);
  if (logical <= 0) return kMaxImageDecodeDimension;
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final pixels = logical * dpr;
  for (final step in kDecodeEdgeSteps) {
    if (pixels <= step) return step;
  }
  return kMaxImageDecodeDimension;
}

/// Hoe een oppervlak zijn afbeelding laat decoderen.
///
/// [hardResize] is de miniatuurweg (ResizeImage op een vaste lage grens).
/// Een schermgrens of de exporttrede gaat via [CappedImage], zodat een GIF
/// die binnen de trede past blijft animeren — de reden dat het scherm niet
/// altijd op bronresolutie decodeerde was juist die animatie.
class DecodePlan {
  const DecodePlan({required this.edge, required this.hardResize});

  final int edge;
  final bool hardResize;
}

DecodePlan decodePlanForBox({
  required int? explicitEdge,
  required double maxWidth,
  required double maxHeight,
  required double devicePixelRatio,
}) {
  if (explicitEdge != null && explicitEdge <= kHardResizeDecodeEdge) {
    return DecodePlan(edge: explicitEdge, hardResize: true);
  }
  final edge =
      explicitEdge ?? decodeEdgeForBox(maxWidth, maxHeight, devicePixelRatio);
  return DecodePlan(edge: edge, hardResize: false);
}

/// Kiest de provider bij de grootte van het vak. De slidestrook geeft een
/// vaste [explicitEdge] van 512 mee; preview, presentator en beamer laten
/// hem null en volgen het vak.
class ResolvedDecodeImage extends StatelessWidget {
  const ResolvedDecodeImage({
    super.key,
    required this.explicitEdge,
    required this.imageFor,
    required this.child,
  });

  final int? explicitEdge;
  final ImageProvider Function(DecodePlan plan) imageFor;
  final Widget Function(ImageProvider image) child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plan = decodePlanForBox(
          explicitEdge: explicitEdge,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        return child(imageFor(plan));
      },
    );
  }
}

/// An [ImageProvider] that caps the *decode* dimensions like [ResizeImage] but,
/// unlike it, decodes at native resolution whenever the image already fits the
/// cap — see [cappedDecodeTarget]. That single difference is what keeps animated
/// GIFs/WebP animating instead of freezing on the first frame, while over-cap
/// images are still scaled down so an untrusted image can't exhaust memory.
///
/// [cacheKey] is the shared image-cache identity (a file path, the bytes object,
/// …) so display, precache and export hit one cache entry. [loadBytes] fetches
/// the encoded bytes lazily on decode.
@immutable
class CappedImage extends ImageProvider<CappedImage> {
  const CappedImage(
    this.cacheKey,
    this.loadBytes, {
    this.scale = 1.0,
    this.maxEdge = kMaxImageDecodeDimension,
  });

  final Object cacheKey;
  final Future<Uint8List> Function() loadBytes;
  final double scale;

  /// Langste zijde waarop gedecodeerd mag worden. Een beeld dat erin past
  /// blijft op bronresolutie — dat houdt een GIF in beweging.
  final int maxEdge;

  @override
  Future<CappedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CappedImage>(this);

  @override
  ImageStreamCompleter loadImage(CappedImage key, ImageDecoderCallback decode) {
    final completer = MultiFrameImageStreamCompleter(
      codec: _decode(decode),
      scale: scale,
    );
    // Dezelfde terugval als FileImage/NetworkImage/ResizeImage: bij een lees-
    // of decodefout de cache-entry weggooien. Zonder dit blijft de gefaalde
    // completer in `ImageCache._pendingImages` staan en krijgt elke latere
    // resolve op deze key díé fout opnieuw — één transiënte hik (een sync-map
    // die het bestand net herschrijft, een netwerkschijf) zette de afbeelding
    // dan voor de rest van de sessie op de placeholder, terwijl het
    // beamervenster — een aparte engine met een eigen cache — hem wel toonde
    // (#2159). De microtask geeft de cache de kans de key eerst te registreren.
    completer.addEphemeralErrorListener((Object exception, StackTrace? stack) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
    });
    return completer;
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await loadBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(
      buffer,
      getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
        final target = cappedDecodeTarget(
          intrinsicWidth,
          intrinsicHeight,
          maxEdge: maxEdge,
        );
        return ui.TargetImageSize(width: target.width, height: target.height);
      },
    );
    // Frame-count cap: een animated image met te veel frames her-decoderen met
    // een concreet doel (gelijk aan de intrinsieke grootte), wat de engine naar
    // het resize-pad stuurt en de animatie tot het eerste frame samenvat —
    // dezelfde trade-off als bij over-cap dimensies.
    if (codec.frameCount > kMaxImageFrames) {
      final rebuf = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(
        rebuf,
        getTargetSize: (int w, int h) =>
            ui.TargetImageSize(width: w, height: h),
      );
    }
    return codec;
  }

  @override
  bool operator ==(Object other) =>
      other is CappedImage &&
      other.cacheKey == cacheKey &&
      other.scale == scale &&
      other.maxEdge == maxEdge;

  @override
  int get hashCode => Object.hash(cacheKey, scale, maxEdge);

  @override
  String toString() =>
      'CappedImage($cacheKey, scale: $scale, maxEdge: $maxEdge)';
}

/// Process-local versie-teller per bestandspad. Wordt opgehoogd door
/// [bumpImageVersion] nadat een afbeelding op schijf is herschreven (bv. na
/// rotatie in de crop-dialoog). De renderlaag leest [imageVersionOf] en neemt
/// de versie op in de [CappedImage]-cacheKey, zodat de `Image`-widget een
/// nieuwe provider identiteit ziet en opnieuw decodeert in plaats van de
/// verouderde cache-entry te tonen.
final Map<String, int> _imageVersions = {};

/// Huidige versie van [path], of 0 als hij nooit is bumped.
int imageVersionOf(String path) => _imageVersions[path] ?? 0;

/// Verhoog de versie van [path] zodat de volgende render een nieuwe cacheKey
/// gebruikt en de afbeelding opnieuw van schijf leest.
void bumpImageVersion(String path) =>
    _imageVersions[path] = (_imageVersions[path] ?? 0) + 1;

/// [FileImage] met een versienummer in `==`/`hashCode`, zodat [ResizeImage]
/// een andere cache-key krijgt na [bumpImageVersion] en opnieuw decodeert.
class _VersionedFileImage extends FileImage {
  final int version;

  /// Deckgrens voor de byte-lezing; `null` buiten een deck (#2624). De
  /// containment zit in [_loadContained], waar [loadImage] doorheen loopt —
  /// het enige decodepad dat de beeldcache nog bevraagt.
  final String? projectPath;

  const _VersionedFileImage(super.file, {this.version = 0, this.projectPath});

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    if (projectPath == null) return super.loadImage(key, decode);
    return MultiFrameImageStreamCompleter(
      codec: _loadContained(key, decode),
      scale: key.scale,
      debugLabel: key.file.path,
      informationCollector: () => <DiagnosticsNode>[
        ErrorDescription('Path: ${file.path}'),
      ],
    );
  }

  Future<ui.Codec> _loadContained(
    FileImage key,
    Future<ui.Codec> Function(ui.ImmutableBuffer buffer) decode,
  ) async {
    final bytes = await readContainedImageBytes(file, projectPath);
    if (bytes.isEmpty) {
      // Zelfde terugval als FileImage: het bestand kan later alsnog groeien.
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('$file is empty and cannot be loaded as an image.');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _VersionedFileImage &&
      other.file.path == file.path &&
      other.version == version &&
      other.projectPath == projectPath &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(file.path, version, projectPath, scale);
}

/// Een miniatuur-provider die op béide assen begrensd is.
///
/// `Image.file(cacheWidth: n)` begrenst alleen de breedte: de hoogte wordt
/// `n × H/W` en is dus onbegrensd. Een geldige PNG van 512 × 400000 — een paar
/// KB op schijf — decodeerde in de afbeeldingkiezer tot honderden megabytes, en
/// die kiezer loopt de projectmap automatisch af, dus je hoefde het bestand niet
/// eens aan te klikken.
///
/// Béide meegeven aan `cacheWidth`/`cacheHeight` is niet de oplossing: dat
/// gebruikt [ResizeImagePolicy.exact] en trekt de afbeelding scheef. Vandaar
/// `fit`, dat binnen het vierkant past met behoud van verhouding.
///
/// [version] komt van [imageVersionOf] en forceert een cache-miss na
/// [bumpImageVersion], zodat de miniatuur de nieuwe bytes toont.
ImageProvider boundedFileImage(
  File file,
  int maxEdge, {
  int version = 0,
  String? projectPath,
}) => ResizeImage(
  _VersionedFileImage(file, version: version, projectPath: projectPath),
  width: maxEdge,
  height: maxEdge,
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);

/// Leest de bytes van [file], met deck-containment wanneer [projectPath] gezet
/// is: de realpath van het bestand moet binnen de projectmap vallen — dit is de
/// laad-tijd-helft van #2624, één async realpath per decode in plaats van twee
/// synchrone per build. Een ontsnappende symlink werpt [ProjectEscapeException],
/// dat de errorBuilder als `outsideDeck`-placeholder tekent; een gewone
/// leesfout (missend bestand) blijft een `FileSystemException`.
///
/// Bij [projectPath] `null` — editor- of vertrouwde paden buiten een
/// deckgrens — is er geen grens om af te dwingen en leest dit gewoon [file].
Future<Uint8List> readContainedImageBytes(
  File file,
  String? projectPath,
) async {
  if (projectPath == null) return file.readAsBytes();
  final real = await containedRealPathOrNull(file.path, projectPath);
  if (real == null) throw ProjectEscapeException(file.path);
  return File(real).readAsBytes();
}

/// A capped-decode provider for a deck-supplied image **file**. Decodes at
/// native resolution within [kMaxImageDecodeDimension] (so an animated GIF keeps
/// animating) and only scales huge images down. Keyed by path like [FileImage].
///
/// [version] komt van [imageVersionOf] en forceert een cache-miss na
/// [bumpImageVersion]. [projectPath] dwingt de deck-containment af *bij de
/// byte-lezing* — zie [readContainedImageBytes] (#2624).
ImageProvider cappedFileImage(
  File file, {
  int version = 0,
  String? projectPath,
  int maxEdge = kMaxImageDecodeDimension,
}) => CappedImage(
  version == 0 ? file.path : '${file.path}#$version',
  () => readContainedImageBytes(file, projectPath),
  maxEdge: maxEdge,
);

/// A capped-decode provider for in-memory image [bytes] (`mem:` paths from the
/// WebAssetStore). Pass the *same* bytes object each time so the cache shares one
/// entry (identity keyed, like [MemoryImage]). Keeps animated images animating.
ImageProvider cappedMemoryImage(
  Uint8List bytes, {
  int maxEdge = kMaxImageDecodeDimension,
}) => CappedImage(bytes, () async => bytes, maxEdge: maxEdge);

/// An [AssetImage] whose decode is capped to [kMaxImageDecodeDimension] —
/// voor `asset:`-paden (méégebundelde logo's van ingebouwde stijlprofielen).
/// Gebundelde assets zijn vertrouwd en statisch, dus [ResizeImage] volstaat;
/// de cap houdt alle logopaden uniform en gratis veilig.
ImageProvider cappedBundledAssetImage(String assetKey) => ResizeImage(
  AssetImage(assetKey),
  width: kMaxImageDecodeDimension,
  height: kMaxImageDecodeDimension,
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);
