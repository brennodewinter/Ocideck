import 'package:image/image.dart' as img;

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
