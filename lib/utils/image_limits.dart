import 'dart:io';
import 'dart:typed_data';

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

/// A [FileImage] whose decode is capped to [kMaxImageDecodeDimension] on the
/// longest side (aspect ratio preserved). Use this everywhere a deck-supplied
/// image file is decoded for display, export, or precache, so the providers
/// share a cache key and an untrusted image can't exhaust memory.
ImageProvider cappedFileImage(File file) => ResizeImage(
  FileImage(file),
  width: kMaxImageDecodeDimension,
  height: kMaxImageDecodeDimension,
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);

/// A [NetworkImage] whose decode is capped to [kMaxImageDecodeDimension], the
/// network twin of [cappedFileImage]. Used for deck-supplied `http(s)` image
/// URLs so a remote (untrusted) image can't exhaust memory on decode. The
/// caller is responsible for the remote-media gate and SSRF host check before
/// constructing this; the cap is the decode-bomb defence only.
ImageProvider cappedNetworkImage(String url) => ResizeImage(
  NetworkImage(url),
  width: kMaxImageDecodeDimension,
  height: kMaxImageDecodeDimension,
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);

/// A [MemoryImage] whose decode is capped to [kMaxImageDecodeDimension], the
/// in-memory twin of [cappedFileImage]. Gebruikt voor `mem:`-paden uit de
/// WebAssetStore (webversie) — zelfde decode-bom-verdediging als bij
/// bestanden. Geef steeds hetzélfde bytes-object door, dan deelt de
/// image-cache één entry (MemoryImage vergelijkt op object-identiteit).
ImageProvider cappedMemoryImage(Uint8List bytes) => ResizeImage(
  MemoryImage(bytes),
  width: kMaxImageDecodeDimension,
  height: kMaxImageDecodeDimension,
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);
