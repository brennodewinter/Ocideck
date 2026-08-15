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
  int? found;
  _forEachJpegSegment(bytes, (marker, start, length) {
    if (marker != 0xE1) return false;
    found = _orientationFromApp1(bytes, start, length);
    return found != null;
  });
  return found ?? 1;
}

/// Roep [onSegment] aan met de marker, het begin en de lengte van elk
/// JPEG-segment (beide zonder de marker en het lengteveld zelf), tot het `true`
/// teruggeeft of de beeldsdata begint.
///
/// Zowel de EXIF-oriëntatie (APP1) als de JFIF-pixeldichtheid (APP0) zit in zo'n
/// segment; ze delen deze wandeling zodat er maar één plek is die zich om
/// afgekapte of misvormde bytes hoeft te bekommeren.
void _forEachJpegSegment(
  Uint8List bytes,
  bool Function(int marker, int start, int length) onSegment,
) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return;
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return;
    final marker = bytes[offset + 1];
    // Losse markers (opvulling, herstart, eind) dragen geen lengteveld.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      offset += 2;
      continue;
    }
    // Vanaf de scan volgt beeldsdata; een APPn-blok komt daar niet meer.
    if (marker == 0xDA) return;
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (length < 2 || offset + 2 + length > bytes.length) return;
    if (onSegment(marker, offset + 4, length - 2)) return;
    offset += 2 + length;
  }
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

/// Zonder eigen resolutie rekent LibreOffice een afbeelding op 0,2 mm per
/// pixel (127 dpi) — gemeten door dezelfde uitsnede door
/// `soffice --convert-to odp` te halen met en zonder pHYs/JFIF-dichtheid.
const double _defaultPixelsPerCm = 50;

/// De natuurlijke afmeting van [bytes] in centimeters: het pixelformaat
/// gedeeld door de eigen resolutie van de afbeelding. `null` wanneer het
/// formaat niet te lezen is.
///
/// ODF meet `fo:clip` hiertegen af — niet tegen het kader waarin de afbeelding
/// staat, en niet tegen het pixelformaat. Wie de uitsnede in fracties van de
/// bron wil, deelt de geklikte lengte door deze maat.
({double width, double height})? imageNaturalSizeCm(Uint8List bytes) {
  // startDecode leest alleen de kop, niet de pixels: het formaat opvragen mag
  // geen tweede volledige decode kosten. Het zoeken naar een decoder struikelt
  // wél over afgekapte bytes, en die komen uit een bestand van buiten.
  final img.DecodeInfo? info;
  try {
    info = img.findDecoderForData(bytes)?.startDecode(bytes);
  } on Object catch (e) {
    logWarning('imageNaturalSizeCm: formaat onleesbaar', e);
    return null;
  }
  if (info == null || info.width <= 0 || info.height <= 0) return null;
  final density = _pixelsPerCm(bytes);
  return (
    width: info.width / (density?.$1 ?? _defaultPixelsPerCm),
    height: info.height / (density?.$2 ?? _defaultPixelsPerCm),
  );
}

/// De eigen resolutie van [bytes] in pixels per centimeter (x, y), uit de
/// PNG-`pHYs` of de JFIF-dichtheid. `null` wanneer de afbeelding er geen
/// draagt — dan geldt de standaard van de lezer.
(double, double)? _pixelsPerCm(Uint8List bytes) =>
    _pngPixelsPerCm(bytes) ?? _jfifPixelsPerCm(bytes);

/// Lees de `pHYs`-chunk van een PNG: pixels per eenheid op beide assen, waarbij
/// alleen eenheid 1 (de meter) een echte resolutie is.
(double, double)? _pngPixelsPerCm(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < signature.length) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  var offset = signature.length;
  // Chunk: lengte (4), type (4), data, CRC (4).
  while (offset + 12 <= bytes.length) {
    final length = _uint32(bytes, offset);
    final isPhys =
        bytes[offset + 4] == 0x70 && // p
        bytes[offset + 5] == 0x48 && // H
        bytes[offset + 6] == 0x59 && // Y
        bytes[offset + 7] == 0x73; //  s
    if (offset + 12 + length > bytes.length) return null;
    if (isPhys && length >= 9) {
      final data = offset + 8;
      if (bytes[data + 8] != 1) return null; // eenheid onbekend
      final x = _uint32(bytes, data) / 100;
      final y = _uint32(bytes, data + 4) / 100;
      return x > 0 && y > 0 ? (x, y) : null;
    }
    offset += 12 + length;
  }
  return null;
}

/// Lees de dichtheid uit het JFIF-segment (APP0) van een JPEG: eenheid 1 is per
/// inch, eenheid 2 per centimeter, eenheid 0 zegt alleen iets over de
/// beeldverhouding en telt dus niet als resolutie.
(double, double)? _jfifPixelsPerCm(Uint8List bytes) {
  (double, double)? density;
  _forEachJpegSegment(bytes, (marker, start, length) {
    if (marker != 0xE0 || length < 12) return false;
    const signature = [0x4A, 0x46, 0x49, 0x46, 0x00]; // 'JFIF\0'
    for (var i = 0; i < signature.length; i++) {
      if (bytes[start + i] != signature[i]) return false;
    }
    final units = bytes[start + 7];
    final x = (bytes[start + 8] << 8) | bytes[start + 9];
    final y = (bytes[start + 10] << 8) | bytes[start + 11];
    if (x <= 0 || y <= 0) return true;
    if (units == 1) density = (x / 2.54, y / 2.54);
    if (units == 2) density = (x.toDouble(), y.toDouble());
    return true;
  });
  return density;
}

int _uint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// De uitsnede die een presentatieprogramma op een bronafbeelding legt: per
/// zijde de fractie (0..1) van de bron die wegvalt. Gemaakt met [importCrop].
typedef ImportCrop = ({double left, double top, double right, double bottom});

/// Een [ImportCrop] van vier fracties, of `null` wanneer er niets wegvalt.
///
/// Negatieve waarden betekenen in beide formaten dat het bronprogramma de
/// afbeelding juist aanvult in plaats van bijsnijdt; dat kan OciDeck niet
/// weergeven, dus die zijde blijft heel. Een uitsnede die niets zou overlaten
/// wordt ook genegeerd — een lege afbeelding is slechter dan een die niet is
/// bijgesneden.
ImportCrop? importCrop({
  double left = 0,
  double top = 0,
  double right = 0,
  double bottom = 0,
}) {
  final l = left.isFinite && left > 0 ? left : 0.0;
  final t = top.isFinite && top > 0 ? top : 0.0;
  final r = right.isFinite && right > 0 ? right : 0.0;
  final b = bottom.isFinite && bottom > 0 ? bottom : 0.0;
  if (l + r >= 1 || t + b >= 1) return null;
  if (l == 0 && t == 0 && r == 0 && b == 0) return null;
  return (left: l, top: t, right: r, bottom: b);
}

/// De geometrie die een presentatieprogramma bovenop een bronafbeelding legt.
///
/// PowerPoint en Impress bewaren bijsnijden, spiegelen en draaien als
/// eigenschappen van de vórm, niet in de afbeelding zelf. OciDeck zet een
/// afbeelding zonder eigen geometrie op de dia, dus bakt de import ze in de
/// pixels — zie [bakeImportGeometry].
class ImportImageGeometry {
  const ImportImageGeometry({
    this.crop,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.clockwiseDegrees = 0,
  });

  /// Wat er van de bron wegvalt, of `null` als de hele afbeelding meedoet.
  final ImportCrop? crop;

  /// Spiegelen om de verticale as (links en rechts wisselen).
  final bool flipHorizontal;

  /// Spiegelen om de horizontale as (boven en onder wisselen).
  final bool flipVertical;

  /// De draaiing met de klok mee, in graden, geteld vanaf de ruwe bron.
  final double clockwiseDegrees;

  /// True wanneer er niets te bakken valt en de bronbytes ongemoeid kunnen
  /// blijven.
  bool get isIdentity =>
      crop == null &&
      !flipHorizontal &&
      !flipVertical &&
      clockwiseDegrees % 360 == 0;
}

/// Bak de geometrie van een geïmporteerde afbeelding in de pixels; het
/// resultaat draagt geen EXIF-orientatietag meer. [path] bepaalt alleen het
/// uitvoerformaat.
///
/// De volgorde ligt vast en is getoetst tegen wat LibreOffice van dezelfde
/// PPTX- en ODP-bestanden rendert: eerst bijsnijden (in de ruwe bron), dan
/// spiegelen, dan draaien. Andersom draaien-dan-spiegelen levert bij een hoek
/// die geen veelvoud van 180° is een zichtbaar ander beeld op.
///
/// Zowel PowerPoint als Impress negeren de EXIF-orientatietag van een foto. Een
/// auteur die zijn liggend opgeslagen cameraopname rechtop wilde hebben,
/// draaide hem daar dus met de hand goed, en al zijn geometrie telt vanaf de
/// ruwe pixels. `img.decodeImage` bakt de EXIF-orientatie juist wél alvast in,
/// dus die gaat er hier eerst weer af — anders zou de uitsnede een gedraaide
/// hoek van de foto wegsnijden en de foto twee keer draaien.
///
/// Er wordt altijd opnieuw gecodeerd, ook als er per saldo niets verandert:
/// dan verdwijnt de EXIF-tag uit de bytes en tonen ook renderers die geen EXIF
/// lezen (de PDF-export) dezelfde afbeelding. Bij een onleesbare afbeelding
/// komen de originele bytes ongewijzigd terug — een niet bewerkte afbeelding is
/// beter dan geen afbeelding.
Uint8List bakeImportGeometry(
  Uint8List bytes,
  ImportImageGeometry geometry,
  String path,
) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final baked = jpegExifRotationDegrees(bytes);
    var image = baked == 0
        ? decoded
        : img.copyRotate(decoded, angle: 360 - baked);
    image = _cropped(image, geometry.crop);
    image = _flipped(image, geometry);
    final turn = (geometry.clockwiseDegrees % 360 + 360) % 360;
    if (turn != 0) image = img.copyRotate(image, angle: turn);
    return _encodeLike(image, path);
  } on Object catch (e) {
    logWarning('bakeImportGeometry: bakken mislukt', e);
    return bytes;
  }
}

img.Image _cropped(img.Image image, ImportCrop? crop) {
  if (crop == null) return image;
  final left = (crop.left * image.width).round();
  final top = (crop.top * image.height).round();
  final width = image.width - left - (crop.right * image.width).round();
  final height = image.height - top - (crop.bottom * image.height).round();
  // Afronden kan bij een piepkleine afbeelding alsnog niets overlaten.
  if (width < 1 || height < 1) return image;
  return img.copyCrop(image, x: left, y: top, width: width, height: height);
}

img.Image _flipped(img.Image image, ImportImageGeometry geometry) {
  if (!geometry.flipHorizontal && !geometry.flipVertical) return image;
  return img.copyFlip(
    image,
    direction: geometry.flipHorizontal && geometry.flipVertical
        ? img.FlipDirection.both
        : geometry.flipHorizontal
        ? img.FlipDirection.horizontal
        : img.FlipDirection.vertical,
  );
}

Uint8List _encodeLike(img.Image image, String path) {
  final ext = path.split('.').last.toLowerCase();
  final encoded = ext == 'jpg' || ext == 'jpeg'
      ? img.encodeJpg(image)
      : ext == 'gif'
      ? img.encodeGif(image)
      : img.encodePng(image);
  return Uint8List.fromList(encoded);
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
