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
