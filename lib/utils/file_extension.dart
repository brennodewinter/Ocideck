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

/// De bestandsnaam zonder map of extensie — de terugval voor een deck dat zelf
/// geen titel meebrengt. Padscheiding-veilig zonder `dart:io`.
String stemOfFileName(String filename) {
  final base = filename.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// De extensie van [path] in kleine letters, of [fallback] als er geen punt
/// staat of de extensie leeg is.
String extOfFileName(String path, {String fallback = 'png'}) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return fallback;
  final ext = path.substring(dot + 1).toLowerCase();
  return ext.isEmpty ? fallback : ext;
}
