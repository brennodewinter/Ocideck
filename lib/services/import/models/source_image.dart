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
    this.placement,
  });

  final Uint8List bytes;

  /// Lower-cased extension without a dot, e.g. `png`, `jpg`, `gif`, `svg`.
  final String ext;

  /// Original filename from the source archive, when available.
  final String? name;

  /// Caption text found beside the image in the source, when available.
  final String? caption;

  /// De plek van de afbeelding op de brondia, genormaliseerd naar 0..1.
  ///
  /// OciDeck bewaart vrije afbeeldingsplaatsing niet, maar de importanalyse
  /// heeft deze ene aanwijzing wel nodig: hetzelfde kleine beeld op meerdere
  /// dia's in de boven- of onderrand is waarschijnlijk een logo. Importers die
  /// de brondiamaten niet betrouwbaar kennen laten dit veld leeg; onbekende
  /// geometrie mag nooit als bewijs voor een logo gelden.
  final SourceImagePlacement? placement;

  /// SHA-256 hex digest of [bytes]; the content-based identity for dedup.
  late final String sha256 = crypto.sha256.convert(bytes).toString();
}

class SourceImagePlacement {
  const SourceImagePlacement({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get bottom => top + height;

  bool get isLogoLikeAtVerticalEdge {
    final boundedHeight = height > 0 && height <= 0.30;
    final boundedArea = width > 0 && width * height <= 0.12;
    return boundedHeight && boundedArea && (top <= 0.20 || bottom >= 0.80);
  }

  bool get isAtTop => top <= 0.20;
}
