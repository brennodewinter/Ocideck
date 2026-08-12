import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'log.dart';

/// Schaal [image] zodanig dat de langste zijde hoogstens [maxEdge] pixels wordt.
/// Is het al klein genoeg, dan komt het ongewijzigd terug. Gebruikt
/// `Interpolation.average` (kwaliteit boven snelheid).
///
/// Eén plek voor het resize-recept dat voorheen in `html_image_embedder` en
/// `image_alt_ai_service` gekopieerd stond. De aanroeper doet de decode-cap,
/// de EXIF-strip en de encodeerkeuze — die verschillen per doel.
img.Image resizeLongestEdge(img.Image image, int maxEdge) {
  final longest = image.width >= image.height ? image.width : image.height;
  if (longest <= maxEdge) return image;
  return image.width >= image.height
      ? img.copyResize(
          image,
          width: maxEdge,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: maxEdge,
          interpolation: img.Interpolation.average,
        );
}

/// Bak de EXIF-orientatie van [bytes] in de pixels en wis de tag, zodat elke
/// renderer (Flutter, export, HTML) de afbeelding correct toont zonder EXIF
/// te hoeven interpreteren. Flutter's decoder negeert EXIF-orientatie, dus
/// een JPEG met orientatie 3 (180°) staat anders op de kop.
///
/// Alleen JPEGs hebben in de praktijk een EXIF-orientatie-tag; andere
/// formaten gaan ongewijzigd terug. De overige EXIF (GPS, cameramodel) blijft
/// staan; die wordt pas gestript bij de HTML-export.
Uint8List bakeJpegOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return bytes;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    if (!decoded.exif.imageIfd.hasOrientation ||
        decoded.exif.imageIfd.orientation == 1) {
      return bytes;
    }
    final baked = img.bakeOrientation(decoded);
    return Uint8List.fromList(img.encodeJpg(baked, quality: 95));
  } on Object catch (e) {
    logWarning('bakeJpegOrientation: decode/encode failed', e);
    return bytes;
  }
}

/// Roteer [bytes] met [angleDegrees] en re-encodeer. Keynote bewaart de
/// rotatie van een afbeelding in de IWA-transform (niet in EXIF), dus bij
/// import staan afbeeldingen met een 180°-rotatie anders op de kop. Alleen
/// veelvouden van 90° worden ondersteund — andere hoeken komen zelden voor
/// in presentaties en OciDeck heeft geen vrij-rotatie-rendering.
Uint8List rotateImageBytes(Uint8List bytes, double angleDegrees) {
  final normalized = angleDegrees.round() % 360;
  if (normalized == 0) return bytes;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final rotated = img.copyRotate(decoded, angle: normalized);
    final isJpeg = bytes.length > 1 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    return Uint8List.fromList(
      isJpeg ? img.encodeJpg(rotated, quality: 95) : img.encodePng(rotated),
    );
  } on Object catch (e) {
    logWarning('rotateImageBytes: rotate failed', e);
    return bytes;
  }
}
