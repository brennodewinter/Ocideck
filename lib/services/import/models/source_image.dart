import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// A normalised image extracted from a source presentation.
///
/// Identity is content-based: [sha256] lets the deck builder hand identical
/// bytes one and the same `mem:` path, so an image repeated across slides is
/// stored once in the deck's own `images/` folder on save. The original [name]
/// is kept for the on-disk filename and for captions.
class SourceImage {
  SourceImage({
    required this.bytes,
    required this.ext,
    this.name,
    this.caption,
  });

  final Uint8List bytes;

  /// Lower-cased extension without a dot, e.g. `png`, `jpg`, `gif`, `svg`.
  final String ext;

  /// Original filename from the source archive, when available.
  final String? name;

  /// Caption text found beside the image in the source, when available.
  final String? caption;

  /// SHA-256 hex digest of [bytes]; the content-based identity for dedup.
  late final String sha256 = crypto.sha256.convert(bytes).toString();
}
