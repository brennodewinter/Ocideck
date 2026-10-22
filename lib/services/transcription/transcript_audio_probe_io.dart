import 'dart:io';

import '../../utils/project_path.dart';

/// Lost [relPath] op via de bestaande containment-guard (geen `../`, geen
/// symlink naar buiten het project) en kijkt of het bestand er ligt.
/// `true`/`false` is een feit; `null` — geen projectpad — betekent
/// "niet te verifiëren", en de UI zwijgt dan liever dan te waarschuwen
/// voor iets dat hij niet kan zien.
bool? transcriptAudioExists(String? projectPath, String relPath) {
  final resolved = resolveContainedRealPath(relPath, projectPath);
  if (resolved == null) return null;
  return File(resolved).existsSync();
}
