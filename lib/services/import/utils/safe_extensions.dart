/// Veilige bestandsextensies voor media die met een import meekomt.
///
/// Een geïmporteerde presentatie bepaalt zelf hoe zijn bijlagen heten. Een
/// Keynote-video die `clip.command` of `clip.js` heet zou die naam anders
/// meenemen naar de `media/`-map van het deck: een uitvoerbare extensie die
/// niemand heeft gekozen. Deze laag knipt dat af — alleen extensies uit de
/// witte lijst blijven staan, al het andere wordt `mp4`.
///
/// Dit geldt net zo goed voor beeld. Dat stond hier eerder anders — "afbeeldingen
/// krijgen hun naam van `DeckBuilder`, niet van het bronbestand" — en dat was
/// niet waar: `DeckBuilder._imageName` nam de naam uit het archief over en
/// strípte alleen de mappen, dus `rapport.pdf.command` landde ongewijzigd in de
/// `images/`-map van de gebruiker. Beide kanten hebben nu een witte lijst.
library;

/// Toegestane video-extensies voor de `media/`-map.
const _videoExtensionWhitelist = {
  'mp4',
  'webm',
  'mov',
  'avi',
  'mkv',
  'm4v',
  'wmv',
  'mpg',
  'mpeg',
  'ogv',
  '3gp',
  'flv',
  'ts',
};

/// Normaliseert [fileName] zodat de extensie in de toegestane verzameling zit.
///
/// Ontbreekt de extensie, of staat hij niet in de witte lijst, dan wordt hij
/// vervangen door `mp4`.
String normalizeVideoFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '${fileName.isEmpty ? 'video' : fileName}.mp4';
  final base = fileName.substring(0, dot);
  final ext = fileName
      .substring(dot + 1)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final safeExt = _videoExtensionWhitelist.contains(ext) ? ext : 'mp4';
  return '$base.$safeExt';
}

/// Toegestane afbeeldingsextensies voor de `images/`-map.
const _imageExtensionWhitelist = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tif',
  'tiff',
  'svg',
  'avif',
  'heic',
  'ico',
  'emf',
  'wmf',
};

/// Normaliseert [fileName] zodat de extensie in de toegestane verzameling zit.
///
/// [fallbackExtension] is de extensie die de importeur uit de bytes afleidde;
/// staat ook die niet in de witte lijst, dan wordt het `png`.
String normalizeImageFileName(
  String fileName, {
  String fallbackExtension = 'png',
}) {
  final fallback = _imageExtensionWhitelist.contains(fallbackExtension)
      ? fallbackExtension
      : 'png';
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) {
    return '${fileName.isEmpty ? 'afbeelding' : fileName}.$fallback';
  }
  final base = fileName.substring(0, dot);
  final ext = fileName
      .substring(dot + 1)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final safeExt = _imageExtensionWhitelist.contains(ext) ? ext : fallback;
  return '$base.$safeExt';
}
