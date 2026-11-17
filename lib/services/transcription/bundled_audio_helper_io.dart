import 'dart:io';

import 'package:path/path.dart' as p;

/// An installed helper next to OciDeck, independent of the user's PATH.
String? bundledAudioHelper({String? executable, bool? windows}) {
  final directory = p.dirname(executable ?? Platform.resolvedExecutable);
  final name = (windows ?? Platform.isWindows)
      ? 'ocideck-audio.exe'
      : 'ocideck-audio';
  final candidate = p.join(directory, name);
  return File(candidate).existsSync() ? candidate : null;
}

/// The extra macOS decoder is bundled, never discovered through PATH.
String? bundledMacMediaDecoder({String? executable, bool? macOS}) {
  if (!(macOS ?? Platform.isMacOS)) return null;
  final directory = p.dirname(executable ?? Platform.resolvedExecutable);
  final candidate = p.normalize(p.join(directory, '..', 'Helpers', 'ffmpeg'));
  return File(candidate).existsSync() ? candidate : null;
}
