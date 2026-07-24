/// Veilige bestandsextensies voor media die met een import meekomt.
///
/// Een geïmporteerde presentatie bepaalt zelf hoe zijn bijlagen heten. Een
/// Keynote-video die `clip.command` of `clip.js` heet zou die naam anders
/// meenemen naar de `media/`-map van het deck: een uitvoerbare extensie die
/// niemand heeft gekozen. Deze laag knipt dat af — alleen extensies uit de
/// witte lijst blijven staan, al het andere wordt `mp4`.
///
/// Alleen de videokant staat hier. De import kent geen tweede plek waar een
/// bronnaam een bestandsnaam wordt: afbeeldingen reizen als bytes met een
/// inhoudshash mee (`SourceImage`) en krijgen hun naam van `DeckBuilder`, niet
/// van het bronbestand.
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
