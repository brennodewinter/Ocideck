import 'package:path/path.dart' as p;

/// Voegt [ext] aan [path] toe wanneer die er nog niet (hoofdletterongevoelig)
/// op staat. [ext] mag al dan niet met een punt beginnen — beide vormen werken.
///
/// Vroeger stond op vijf opslaan- en exportroutes een `endsWith('.md')`-check
/// die hoofdlettergevoelig was: wie `Deck.MD` koos kreeg `Deck.MD.md`. Deze
/// helper vergelijkt via `p.extension(path).toLowerCase()`, zodat `.MD` en
/// `.md` hetzelfde zijn. `p.extension` vangt bovendien een mapnaam met een punt
/// die geen bestandsextensie is.
String withExtension(String path, String ext) {
  final normalized = ext.startsWith('.') ? ext : '.$ext';
  if (p.extension(path).toLowerCase() == normalized.toLowerCase()) {
    return path;
  }
  return '$path$normalized';
}
