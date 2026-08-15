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

/// De rotatie in graden (met de klok mee, altijd 0, 90, 180 of 270) die de
/// EXIF-oriëntatietag van [bytes] voorschrijft. Andere formaten dan JPEG, een
/// ontbrekende tag en een onleesbare tag geven 0.
///
/// `img.decodeImage` bakt deze rotatie zelf al in de pixels en wist daarna de
/// tag, dus wie wil weten wát er gebakken is — bijvoorbeeld om er een eigen
/// rotatie mee te verrekenen — moet het uit de ruwe bytes lezen.
///
/// De spiegel-oriëntaties (2, 4, 5 en 7) leveren alleen hun rotatiedeel op; de
/// spiegeling zelf valt niet in een hoek uit te drukken. Die komen in de
/// praktijk niet uit camera's.
int jpegExifRotationDegrees(Uint8List bytes) {
  switch (_jpegExifOrientation(bytes)) {
    case 3:
    case 4:
      return 180;
    case 6:
    case 7:
      return 90;
    case 5:
    case 8:
      return 270;
    default:
      return 0;
  }
}

/// Loop de JPEG-segmenten langs tot de APP1 met de EXIF-blok en geef de
/// oriëntatietag terug (1 wanneer hij ontbreekt).
int _jpegExifOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 1;
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return 1;
    final marker = bytes[offset + 1];
    // Losse markers (opvulling, herstart, eind) dragen geen lengteveld.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      offset += 2;
      continue;
    }
    // Vanaf de scan volgt beeldsdata; een EXIF-blok komt daar niet meer.
    if (marker == 0xDA) return 1;
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (length < 2 || offset + 2 + length > bytes.length) return 1;
    if (marker == 0xE1) {
      final orientation = _orientationFromApp1(bytes, offset + 4, length - 2);
      if (orientation != null) return orientation;
    }
    offset += 2 + length;
  }
  return 1;
}

/// Lees de oriëntatie uit een APP1-segment van [length] bytes dat op [start]
/// begint. Geeft `null` wanneer het segment geen EXIF is of geen tag draagt.
int? _orientationFromApp1(Uint8List bytes, int start, int length) {
  // 'Exif\0\0', gevolgd door de TIFF-kop die ExifData zelf leest.
  const signature = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
  if (length <= signature.length) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[start + i] != signature[i]) return null;
  }
  try {
    final exif = img.ExifData.fromInputBuffer(
      img.InputBuffer(
        Uint8List.sublistView(bytes, start + signature.length, start + length),
      ),
    );
    return exif.imageIfd.orientation;
  } on Object catch (e) {
    logWarning('jpegExifRotationDegrees: EXIF unreadable', e);
    return null;
  }
}

/// Bak de rotatie van een geïmporteerde afbeelding in de pixels:
/// [clockwiseDegrees] geteld vanaf de rúwe bytes, en het resultaat draagt geen
/// EXIF-orientatietag meer. [path] bepaalt alleen het uitvoerformaat.
///
/// Zowel PowerPoint als Impress negeren de EXIF-orientatietag van een foto. Een
/// auteur die zijn liggend opgeslagen cameraopname rechtop wilde hebben,
/// draaide hem daar dus met de hand goed, en die hoek telt vanaf de ruwe
/// pixels. `img.decodeImage` bakt de EXIF-orientatie juist wél alvast in, dus
/// die hoek gaat er hier weer af — anders draait de foto twee keer.
///
/// Er wordt altijd opnieuw gecodeerd, ook als er per saldo niets te draaien
/// valt: dan verdwijnt de EXIF-tag uit de bytes en tonen ook renderers die geen
/// EXIF lezen (de PDF-export) dezelfde afbeelding. Bij een onleesbare
/// afbeelding komen de originele bytes ongewijzigd terug — een niet gedraaide
/// afbeelding is beter dan geen afbeelding.
Uint8List bakeImportRotation(
  Uint8List bytes,
  double clockwiseDegrees,
  String path,
) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final baked = jpegExifRotationDegrees(bytes);
    final effective = ((clockwiseDegrees - baked) % 360 + 360) % 360;
    final rotated = effective == 0
        ? decoded
        : img.copyRotate(decoded, angle: effective);
    final ext = path.split('.').last.toLowerCase();
    final encoded = ext == 'jpg' || ext == 'jpeg'
        ? img.encodeJpg(rotated)
        : ext == 'gif'
        ? img.encodeGif(rotated)
        : img.encodePng(rotated);
    return Uint8List.fromList(encoded);
  } on Object catch (e) {
    logWarning('bakeImportRotation: rotate failed', e);
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
