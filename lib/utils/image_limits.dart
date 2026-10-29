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

/// Maximum aantal frames dat een animated image (GIF/WebP/APNG) mag hebben.
///
/// De dimensie-cap vangt één frame, niet de animatie als geheel: een GIF met
/// 10.000 frames à 4096²×4 bytes is honderden GiB. Boven deze grens tonen we
/// alleen het eerste frame — dezelfde trade-off als de dimensie-cap al maakt
/// voor over-cap afbeeldingen.
const int kMaxImageFrames = 256;

/// De vaste treden waarop de weergave-gebonden decodegrens eindigt
/// (#2625). De trede — niet de exacte pixelmaat — is de cachesleutel, zodat
/// een scherm dat 1840 px meet en een dat 1900 px meet dezelfde decode delen
/// in plaats van elk een eigen 40-megabyte-entry te branden.
const List<int> kDecodeEdgeSteps = [1024, 2048, 4096];

/// De decodegrens die past bij een weergave van [displayWidth] logische
/// pixels op [devicePixelRatio]: de eerste trede uit [kDecodeEdgeSteps] die
/// de fysieke pixelmaat dekt, met [kMaxImageDecodeDimension] als plafond.
/// Een oneindige of niet-positieve breedte levert het plafond — er is dan
/// gewoon geen kleinere grens af te leiden.
int decodeEdgeForDisplay(double displayWidth, double devicePixelRatio) {
  if (!displayWidth.isFinite || displayWidth <= 0 || devicePixelRatio <= 0) {
    return kMaxImageDecodeDimension;
  }
  final px = displayWidth * devicePixelRatio;
  for (final step in kDecodeEdgeSteps) {
    if (px <= step) return step;
  }
  return kMaxImageDecodeDimension;
}

/// The decode target for the memory cap. Returns `(null, null)` — i.e. decode at
/// native resolution — whenever the image already fits within [cap] on both
/// axes, and only otherwise scales the longest side down to the cap (aspect
/// ratio preserved). [cap] is de decodegrens van dit oppervlak — standaard de
/// decodeerbom-grens [kMaxImageDecodeDimension], per oppervlak lager (#2625).
///
/// Decoding at native resolution within the cap is what lets **animated** images
/// (GIF/WebP/APNG) keep every frame: a concrete decode target (as [ResizeImage]
/// always passes, even when it equals the intrinsic size) sends the engine down
/// the resize path, which collapses an animated image to just its first frame.
/// Over-cap images are still scaled down, so the decode-bomb defence is intact —
/// such an image simply shows its first frame (a rare, safe trade-off).
({int? width, int? height}) cappedDecodeTarget(
  int width,
  int height, [
  int cap = kMaxImageDecodeDimension,
]) {
  if (width <= 0 || height <= 0) return (width: null, height: null);
  if (width <= cap && height <= cap) {
    return (width: null, height: null);
  }
  final aspect = width / height;
  if (width >= height) {
    final targetHeight = (cap / aspect).round();
    return (width: cap, height: math.max(1, targetHeight));
  }
  final targetWidth = (cap * aspect).round();
  return (width: math.max(1, targetWidth), height: cap);
}

/// An [ImageProvider] that caps the *decode* dimensions like [ResizeImage] but,
/// unlike it, decodes at native resolution whenever the image already fits the
/// cap — see [cappedDecodeTarget]. That single difference is what keeps animated
/// GIFs/WebP animating instead of freezing on the first frame, while over-cap
/// images are still scaled down so an untrusted image can't exhaust memory.
///
/// [cacheKey] is the shared image-cache identity (a file path, the bytes object,
/// …) so display, precache and export hit one cache entry. [loadBytes] fetches
/// the encoded bytes lazily on decode. [decodeEdge] vervangt de vaste
/// [kMaxImageDecodeDimension] door een per-weergave-grens (#2625) — met de
/// `cappedDecodeTarget`-semantiek die bij een beeld onder de grens op natieve
/// resolutie decodeert, zodat een animated image blijft animeren.
@immutable
class CappedImage extends ImageProvider<CappedImage> {
  const CappedImage(
    this.cacheKey,
    this.loadBytes, {
    this.scale = 1.0,
    this.decodeEdge,
  });

  final Object cacheKey;
  final Future<Uint8List> Function() loadBytes;
  final double scale;
  final int? decodeEdge;

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
          decodeEdge ?? kMaxImageDecodeDimension,
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
      other.decodeEdge == decodeEdge;

  @override
  int get hashCode => Object.hash(cacheKey, scale, decodeEdge);

  @override
  String toString() => 'CappedImage($cacheKey, scale: $scale)';
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

/// Leest [file] pas nadat de projectgrens is gecontroleerd — en leest dan het
/// *reële* doelpad, zodat een tussen controle en open gewisselde symlink geen
/// ontsnappende bytes kan leveren (TOCTOU). Werpt [ProjectEscapeException]
/// wanneer het pad ontsnapt; een gewone leesfout (missend bestand) blijft een
/// `FileSystemException`.
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

/// Een miniatuur-provider die op béide assen begrensd is.
///
/// `Image.file(cacheWidth: n)` begrenst alleen de breedte: de hoogte wordt
/// `n × H/W` en is dus onbegrensd. Een geldige PNG van 512 × 400000 — een paar
/// KB op schijf — decodeerde in de afbeeldingkiezer tot honderden megabytes, en
/// die kiezer loopt de projectmap automatisch af, dus je hoefde het bestand niet
/// eens aan te klikken.
///
/// Béide assen meegeven als `cacheWidth`/`cacheHeight` is niet de oplossing:
/// dat gebruikt [ResizeImagePolicy.exact] en trekt de afbeelding scheef. De
/// `decodeEdge` past daarentegen binnen het vierkant met behoud van
/// verhouding — op natieve resolutie onder de grens (animated blijft
/// animeren), omlaag geschaald daarboven.
///
/// [version] komt van [imageVersionOf] en forceert een cache-miss na
/// [bumpImageVersion], zodat de miniatuur de nieuwe bytes toont. [projectPath]
/// dwingt de deck-containment af *bij de byte-lezing*, niet bij de build —
/// zie [readContainedImageBytes] (#2624).
ImageProvider boundedFileImage(
  File file,
  int maxEdge, {
  int version = 0,
  String? projectPath,
}) => CappedImage(
  version == 0 ? file.path : '${file.path}#$version',
  () => readContainedImageBytes(file, projectPath),
  decodeEdge: maxEdge,
);

/// A capped-decode provider for a deck-supplied image **file**. Decodes at
/// native resolution within [kMaxImageDecodeDimension] (so an animated GIF keeps
/// animating) and only scales huge images down. Keyed by path like [FileImage].
///
/// [version] komt van [imageVersionOf] en forceert een cache-miss na
/// [bumpImageVersion]. [projectPath] verplaatst de symlink-containment naar
/// de byte-lezing: één async realpath per decode in plaats van twee synchrone
/// per build (#2624). Een ontsnappende symlink werpt [ProjectEscapeException]
/// in de laadstroom — de errorBuilder tekent de `outsideDeck`-placeholder.
/// [decodeEdge] is de per-weergave-decodegrens (#2625); null = de
/// decodeerbom-grens [kMaxImageDecodeDimension].
ImageProvider cappedFileImage(
  File file, {
  int version = 0,
  String? projectPath,
  int? decodeEdge,
}) => CappedImage(
  version == 0 ? file.path : '${file.path}#$version',
  () => readContainedImageBytes(file, projectPath),
  decodeEdge: decodeEdge,
);

/// A capped-decode provider for in-memory image [bytes] (`mem:` paths from the
/// WebAssetStore). Pass the *same* bytes object each time so the cache shares one
/// entry (identity keyed, like [MemoryImage]). Keeps animated images animating.
ImageProvider cappedMemoryImage(Uint8List bytes) =>
    CappedImage(bytes, () async => bytes);

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
