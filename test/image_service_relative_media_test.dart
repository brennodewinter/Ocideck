import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'Save as copies relative media without overwriting other bytes',
    () async {
      final root = Directory.systemTemp.createTempSync('relative-media-');
      addTearDown(() => root.deleteSync(recursive: true));
      final source = Directory(p.join(root.path, 'source'))..createSync();
      final target = Directory(p.join(root.path, 'target'))..createSync();
      final paths = ['audio/tone.wav', 'media/film.mp4', 'media/film.vtt'];
      for (final path in paths) {
        final file = File(p.join(source.path, path));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('authored $path');
      }
      final collision = File(p.join(target.path, 'media/tone.wav'));
      collision.parent.createSync(recursive: true);
      collision.writeAsStringSync('existing recording');
      final output = await ImageService().copyMediaToProject(
        [
          Slide.create(SlideType.video).copyWith(
            audioPath: paths[0],
            videoPath: paths[1],
            videoCaptions: paths[2],
          ),
        ],
        target.path,
        sourceProjectPath: source.path,
      );
      final slide = output.single;
      final stored = [slide.audioPath, slide.videoPath, slide.videoCaptions];
      for (var i = 0; i < paths.length; i++) {
        expect(
          File(p.join(target.path, stored[i])).readAsStringSync(),
          'authored ${paths[i]}',
        );
      }
      expect(collision.readAsStringSync(), 'existing recording');
      source.deleteSync(recursive: true);
      // A second save in place must not duplicate files or change paths.
      final again = await ImageService().copyMediaToProject(
        output,
        target.path,
        sourceProjectPath: target.path,
      );
      expect(again.single.audioPath, slide.audioPath);
      expect(again.single.videoPath, slide.videoPath);
      expect(again.single.videoCaptions, slide.videoCaptions);
      expect(Directory(p.join(target.path, 'media')).listSync(), hasLength(4));
    },
  );

  test('relative media cannot escape the source project', () async {
    final root = Directory.systemTemp.createTempSync('relative-media-escape-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory(p.join(root.path, 'source'))..createSync();
    final target = Directory(p.join(root.path, 'target'))..createSync();
    final secret = File(p.join(root.path, 'secret.wav'))
      ..writeAsStringSync('private');
    Link(p.join(source.path, 'link.wav')).createSync(secret.path);
    for (final path in ['../secret.wav', 'link.wav']) {
      final output = await ImageService().copyMediaToProject(
        [Slide.create(SlideType.bullets).copyWith(audioPath: path)],
        target.path,
        sourceProjectPath: source.path,
      );
      expect(output.single.audioPath, path);
    }
    expect(Directory(p.join(target.path, 'media')).listSync(), isEmpty);
  }, skip: Platform.isWindows);
}
