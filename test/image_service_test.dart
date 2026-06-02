import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  final service = ImageService();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_img'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('resolve', () {
    test('returns empty for an empty path', () {
      expect(service.resolve('', '/project'), '');
    });

    test('returns absolute paths unchanged', () {
      expect(service.resolve('/abs/pic.png', '/project'), '/abs/pic.png');
    });

    test('joins relative paths with the project path', () {
      expect(
        service.resolve('images/pic.png', '/project'),
        p.join('/project', 'images/pic.png'),
      );
    });
  });

  group('copyImagesToProject', () {
    test(
      'copies an absolute image into images/ and rewrites the path',
      () async {
        final src = File(p.join(tmp.path, 'photo.png'))
          ..writeAsBytesSync([1, 2]);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();

        final out = await service.copyImagesToProject([
          Slide.create(SlideType.image).copyWith(imagePath: src.path),
        ], project.path);

        expect(out.single.imagePath, 'images/photo.png');
        expect(
          File(p.join(project.path, 'images', 'photo.png')).existsSync(),
          isTrue,
        );
      },
    );

    test('leaves already-relative image paths unchanged', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final out = await service.copyImagesToProject([
        Slide.create(SlideType.image).copyWith(imagePath: 'images/keep.png'),
      ], project.path);
      expect(out.single.imagePath, 'images/keep.png');
    });

    test('leaves the path unchanged when the source file is missing', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final missing = p.join(tmp.path, 'does_not_exist.png');
      final out = await service.copyImagesToProject([
        Slide.create(SlideType.image).copyWith(imagePath: missing),
      ], project.path);
      expect(out.single.imagePath, missing);
    });

    test('copies the second image of a twoImages slide', () async {
      final a = File(p.join(tmp.path, 'a.png'))..writeAsBytesSync([1]);
      final b = File(p.join(tmp.path, 'b.png'))..writeAsBytesSync([2]);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final out = await service.copyImagesToProject([
        Slide.create(
          SlideType.twoImages,
        ).copyWith(imagePath: a.path, imagePath2: b.path),
      ], project.path);

      expect(out.single.imagePath, 'images/a.png');
      expect(out.single.imagePath2, 'images/b.png');
    });
  });

  group('copyMediaToProject', () {
    test(
      'copies absolute video/audio into media/ and rewrites paths',
      () async {
        final vid = File(p.join(tmp.path, 'clip.mp4'))..writeAsBytesSync([1]);
        final aud = File(p.join(tmp.path, 'sound.mp3'))..writeAsBytesSync([2]);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();

        final out = await service.copyMediaToProject([
          Slide.create(
            SlideType.video,
          ).copyWith(videoPath: vid.path, audioPath: aud.path),
        ], project.path);

        expect(out.single.videoPath, 'media/clip.mp4');
        expect(out.single.audioPath, 'media/sound.mp3');
        expect(
          File(p.join(project.path, 'media', 'clip.mp4')).existsSync(),
          isTrue,
        );
      },
    );
  });

  group('copyImageToClipboard', () {
    test('returns false for an empty path', () async {
      expect(await service.copyImageToClipboard(''), isFalse);
    });

    test('returns false for a non-existent file', () async {
      final missing = p.join(tmp.path, 'nope.png');
      expect(await service.copyImageToClipboard(missing), isFalse);
    });

    test('copyImageBytesToClipboard returns false for empty bytes', () async {
      expect(await service.copyImageBytesToClipboard(Uint8List(0)), isFalse);
    });
  });
}
