// Shared host/app plan. Filesystem edits happen only between app processes.
import 'dart:io';
import 'package:path/path.dart' as p;

const nativeRoundtripPhases = [
  'write',
  'md',
  'renamed',
  'moved',
  'save-as',
  'package',
];
String roundtripPath(String root, String phase) => switch (phase) {
  'write' || 'md' => p.join(root, 'project', 'source.md'),
  'renamed' => p.join(root, 'project', 'Hernoemd verslag.MD'),
  'moved' => p.join(root, 'verplaatst project', 'Hernoemd verslag.MD'),
  'save-as' => p.join(root, 'kopie', 'Ander verslag.md'),
  'package' => p.join(root, 'archive.ocideck'),
  _ => throw ArgumentError.value(phase),
};

void prepareRoundtripPhase(String root, String phase) {
  if (phase == 'renamed') {
    File(roundtripPath(root, 'md')).renameSync(roundtripPath(root, phase));
  } else if (phase == 'moved') {
    final source = Directory(p.join(root, 'project'));
    final target = Directory(p.join(root, 'verplaatst project'))..createSync();
    File(
      roundtripPath(root, 'renamed'),
    ).renameSync(roundtripPath(root, 'moved'));
    for (final companion in source.listSync(followLinks: false)) {
      final destination = p.join(target.path, p.basename(companion.path));
      if (companion is Directory) {
        companion.renameSync(destination);
      } else if (companion is File) {
        companion.renameSync(destination);
      } else {
        throw StateError('Unexpected fixture companion');
      }
    }
    source.deleteSync();
  } else if (phase == 'package') {
    // The package must be self-contained. Neither original nor Save-as assets
    // are allowed to rescue a missing package member after the next restart.
    Directory(p.join(root, 'verplaatst project')).deleteSync(recursive: true);
    Directory(p.join(root, 'kopie')).deleteSync(recursive: true);
  }
}

void prepareRoundtripAssets(String root) {
  final project = p.join(root, 'project');
  for (final entry in {
    'images/a.png': 'assets/images/ocideck-logo.png',
    'images/b.png': 'assets/images/librekat-logo.png',
    'media/film.mp4': 'integration_test/fixtures/audio/silent-video.mp4',
    'audio/tone.wav': 'integration_test/fixtures/audio_formats/wav-pcm16.wav',
  }.entries) {
    final file = File(p.join(project, entry.key));
    file.parent.createSync(recursive: true);
    File(entry.value).copySync(file.path);
  }
  File(
    p.join(project, 'media/film.vtt'),
  ).writeAsStringSync('WEBVTT\n\n00:00.000 --> 00:01.000\nNative bijschrift\n');
  Directory(p.join(project, 'data')).createSync();
  File(
    p.join(project, 'data/series.csv'),
  ).writeAsStringSync(',Serie\nEen,12.0\nTwee,34.0\n');
}
