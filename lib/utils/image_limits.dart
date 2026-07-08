import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Upper bound on the decoded dimensions of a slide/background image.
///
/// `ui.instantiateImageCodec` allocates ~`width × height × 4` bytes regardless
/// of the box the image is painted in, so a small but huge-dimensioned file
/// (e.g. a uniformly-coloured 30000×30000 PNG that is a few KB on disk) decodes
/// to gigabytes and OOM-crashes the app. Capping the decode bounds memory to
/// ~`4096² × 4 ≈ 64 MiB` worst case while staying sharp for any realistic
/// display or 4K export.
const int kMaxImageDecodeDimension = 4096;

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
({int? width, int? height}) cappedDecodeTarget(int width, int height) {
  if (width <= 0 || height <= 0) return (width: null, height: null);
  if (width <= kMaxImageDecodeDimension && height <= kMaxImageDecodeDimension) {
    return (width: null, height: null);
  }
  final aspect = width / height;
  if (width >= height) {
    final targetHeight = (kMaxImageDecodeDimension / aspect).round();
    return (width: kMaxImageDecodeDimension, height: math.max(1, targetHeight));
  }
  final targetWidth = (kMaxImageDecodeDimension * aspect).round();
  return (width: math.max(1, targetWidth), height: kMaxImageDecodeDimension);
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
  const CappedImage(this.cacheKey, this.loadBytes, {this.scale = 1.0});

  final Object cacheKey;
  final Future<Uint8List> Function() loadBytes;
  final double scale;

  @override
  Future<CappedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CappedImage>(this);

  @override
  ImageStreamCompleter loadImage(CappedImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _decode(decode), scale: scale);
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await loadBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(
      buffer,
      getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
        final target = cappedDecodeTarget(intrinsicWidth, intrinsicHeight);
        return ui.TargetImageSize(width: target.width, height: target.height);
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CappedImage &&
      other.cacheKey == cacheKey &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(cacheKey, scale);

  @override
  String toString() => 'CappedImage($cacheKey, scale: $scale)';
}

/// A capped-decode provider for a deck-supplied image **file**. Decodes at
/// native resolution within [kMaxImageDecodeDimension] (so an animated GIF keeps
/// animating) and only scales huge images down. Keyed by path like [FileImage].
ImageProvider cappedFileImage(File file) =>
    CappedImage(file.path, () => file.readAsBytes());

/// A capped-decode provider for in-memory image [bytes] (`mem:` paths from the
/// WebAssetStore). Pass the *same* bytes object each time so the cache shares one
/// entry (identity keyed, like [MemoryImage]). Keeps animated images animating.
ImageProvider cappedMemoryImage(Uint8List bytes) =>
    CappedImage(bytes, () async => bytes);

/// A [NetworkImage] whose decode is capped to [kMaxImageDecodeDimension], the
/// network twin of [cappedFileImage]. Used for deck-supplied `http(s)` image
/// URLs so a remote (untrusted) image can't exhaust memory on decode. The
/// caller is responsible for the remote-media gate and SSRF host check before
/// constructing this; the cap is the decode-bomb defence only.
///
/// Remote images use [ResizeImage] (first frame only for animated sources): the
/// SSRF/remote-media gate governs them and re-fetching bytes for a custom
/// animated decode isn't worth the extra network surface.
ImageProvider cappedNetworkImage(String url) => ResizeImage(
  NetworkImage(url),
  width: kMaxImageDecodeDimension,
  height: kMaxImageDecodeDimension,
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);

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
