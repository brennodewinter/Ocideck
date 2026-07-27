import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:path/path.dart' as p;

/// A minimal PNG signature so `looksLikeImage` accepts the bytes.
final _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
]);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final service = ImageService();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_img_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('looksLikeImage', () {
    test('accepts known raster signatures', () {
      expect(ImageService.looksLikeImage(_pngBytes), isTrue);
      expect(ImageService.looksLikeImage([0xFF, 0xD8, 0xFF, 0x00]), isTrue);
      expect(ImageService.looksLikeImage([0x47, 0x49, 0x46, 0x38]), isTrue);
      expect(ImageService.looksLikeImage([0x42, 0x4D, 0x00, 0x00]), isTrue);
      expect(
        ImageService.looksLikeImage([
          0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, //
          0x57, 0x45, 0x42, 0x50,
        ]),
        isTrue,
      );
    });

    test('rejects too-short or unknown bytes', () {
      expect(ImageService.looksLikeImage([1, 2]), isFalse);
      expect(ImageService.looksLikeImage([0, 1, 2, 3]), isFalse);
      // RIFF header without the WEBP marker is not an image.
      expect(
        ImageService.looksLikeImage([
          0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, //
          0x00, 0x00, 0x00, 0x00,
        ]),
        isFalse,
      );
    });
  });

  group('readSlideImageBytes', () {
    test('returns null for an empty path', () async {
      expect(await service.readSlideImageBytes(''), isNull);
    });

    test('reads a project-relative image inside the project', () async {
      final rel = p.join('images', 'pic.png');
      final abs = File(p.join(tmp.path, rel));
      await abs.parent.create(recursive: true);
      await abs.writeAsBytes(_pngBytes);

      final bytes = await service.readSlideImageBytes(
        'images/pic.png',
        projectPath: tmp.path,
      );
      expect(bytes, _pngBytes);
    });

    test('reads an absolute path when there is no project', () async {
      final abs = File(p.join(tmp.path, 'loose.png'));
      await abs.writeAsBytes(_pngBytes);
      final bytes = await service.readSlideImageBytes(abs.path);
      expect(bytes, _pngBytes);
    });

    test('refuses a path that escapes the project', () async {
      expect(
        await service.readSlideImageBytes(
          '../secret.png',
          projectPath: tmp.path,
        ),
        isNull,
      );
    });

    test('refuses an absolute path outside the project', () async {
      final outside = File(p.join(Directory.systemTemp.path, 'outside.png'));
      expect(
        await service.readSlideImageBytes(outside.path, projectPath: tmp.path),
        isNull,
      );
    });

    test('returns null when the resolved file is missing', () async {
      expect(
        await service.readSlideImageBytes(
          'images/nope.png',
          projectPath: tmp.path,
        ),
        isNull,
      );
    });
  });

  group('resolve', () {
    test('returns empty string for an empty path', () {
      expect(service.resolve('', tmp.path), '');
    });

    test('joins a project-relative path to an absolute path', () {
      final resolved = service.resolve('images/pic.png', tmp.path);
      expect(resolved, p.join(tmp.path, 'images', 'pic.png'));
    });

    test('normalises an absolute path', () {
      final abs = p.join(tmp.path, 'a', '..', 'b.png');
      expect(service.resolve(abs, null), p.normalize(abs));
    });
  });

  group('copyImagesToProject', () {
    test(
      'copies an absolute image in and rewrites to a relative path',
      () async {
        final src = File(p.join(tmp.path, 'source.png'));
        await src.writeAsBytes(_pngBytes);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();

        final slide = Slide.create(
          SlideType.bulletsImage,
        ).copyWith(imagePath: src.path);
        final out = await service.copyImagesToProject([slide], project.path);

        expect(out.single.imagePath, 'images/source.png');
        expect(
          File(p.join(project.path, 'images', 'source.png')).existsSync(),
          isTrue,
        );
      },
    );

    test('handles both imagePath and imagePath2', () async {
      final a = File(p.join(tmp.path, 'a.png'))..writeAsBytesSync(_pngBytes);
      final b = File(p.join(tmp.path, 'b.png'))..writeAsBytesSync(_pngBytes);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final slide = Slide.create(
        SlideType.bulletsImage,
      ).copyWith(imagePath: a.path, imagePath2: b.path);
      final out = await service.copyImagesToProject([slide], project.path);

      expect(out.single.imagePath, 'images/a.png');
      expect(out.single.imagePath2, 'images/b.png');
    });

    test('leaves an already-relative images/ path untouched', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final slide = Slide.create(
        SlideType.bulletsImage,
      ).copyWith(imagePath: 'images/keep.png');

      final out = await service.copyImagesToProject([slide], project.path);
      expect(out.single.imagePath, 'images/keep.png');
      // Nothing was copied for an already-relative path.
      expect(Directory(p.join(project.path, 'images')).listSync(), isEmpty);
    });

    test('leaves a missing absolute source path untouched', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final missing = p.join(tmp.path, 'gone.png');
      final slide = Slide.create(
        SlideType.bulletsImage,
      ).copyWith(imagePath: missing);

      final out = await service.copyImagesToProject([slide], project.path);
      expect(out.single.imagePath, missing);
    });

    test(
      'does not re-copy when the destination already exists (dedup)',
      () async {
        final src = File(p.join(tmp.path, 'dup.png'));
        await src.writeAsBytes(_pngBytes);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();

        final s1 = Slide.create(
          SlideType.bulletsImage,
        ).copyWith(imagePath: src.path);
        final s2 = Slide.create(
          SlideType.bulletsImage,
        ).copyWith(imagePath: src.path);

        final out = await service.copyImagesToProject([s1, s2], project.path);
        expect(out[0].imagePath, 'images/dup.png');
        expect(out[1].imagePath, 'images/dup.png');
        // Both slides point at the single copied file.
        final files = Directory(
          p.join(project.path, 'images'),
        ).listSync().whereType<File>();
        expect(files.length, 1);
      },
    );
  });

  group('copyMediaToProject', () {
    test('copies absolute video and audio into media/', () async {
      final video = File(p.join(tmp.path, 'clip.mp4'))
        ..writeAsBytesSync([1, 2, 3]);
      final audio = File(p.join(tmp.path, 'sound.mp3'))
        ..writeAsBytesSync([4, 5, 6]);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(videoPath: video.path, audioPath: audio.path);
      final out = await service.copyMediaToProject([slide], project.path);

      expect(out.single.videoPath, 'media/clip.mp4');
      expect(out.single.audioPath, 'media/sound.mp3');
      expect(
        File(p.join(project.path, 'media', 'clip.mp4')).existsSync(),
        true,
      );
      expect(
        File(p.join(project.path, 'media', 'sound.mp3')).existsSync(),
        true,
      );
    });

    test('leaves already project-relative and empty paths untouched', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(videoPath: 'media/existing.mp4', audioPath: '');

      final out = await service.copyMediaToProject([slide], project.path);
      expect(out.single.videoPath, 'media/existing.mp4');
      expect(out.single.audioPath, '');
    });

    test(
      'leaves an images/ path untouched (only media/ is normalised)',
      () async {
        final project = Directory(p.join(tmp.path, 'project'))..createSync();
        final slide = Slide.create(
          SlideType.bullets,
        ).copyWith(videoPath: 'images/oops.mp4');
        final out = await service.copyMediaToProject([slide], project.path);
        expect(out.single.videoPath, 'images/oops.mp4');
      },
    );

    test('leaves a missing absolute media source untouched', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final missing = p.join(tmp.path, 'gone.mp4');
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(videoPath: missing);
      final out = await service.copyMediaToProject([slide], project.path);
      expect(out.single.videoPath, missing);
    });
  });

  group('clipboard (no plugin)', () {
    test('copyImageBytesToClipboard returns false for empty bytes', () async {
      expect(await service.copyImageBytesToClipboard(Uint8List(0)), isFalse);
    });

    test('copyImageToClipboard returns false for an empty path', () async {
      expect(await service.copyImageToClipboard(''), isFalse);
    });

    test('copyImageToClipboard returns false for a missing file', () async {
      expect(
        await service.copyImageToClipboard(p.join(tmp.path, 'nope.png')),
        isFalse,
      );
    });
  });

  group('clipboard (mocked pasteboard channel)', () {
    const channel = MethodChannel('pasteboard');
    Object? clipboardImage; // what the mocked `image` getter returns
    final calls = <MethodCall>[];

    setUp(() {
      clipboardImage = null;
      calls.clear();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'image') {
          final content = clipboardImage;
          // Het pasteboard-pakket kent per platform een ander contract voor
          // `image`: op macOS/Linux zijn het de bytes rechtstreeks, op Windows
          // een bestandspad dat het pakket zelf leest én verwijdert. De mock
          // volgt dat contract, zodat dezelfde test op elk platform de echte
          // service-weg beproeft in plaats van op de cast te stranden (#926).
          if (content is Uint8List && Platform.isWindows) {
            final file = File(p.join(tmp.path, 'clip_${calls.length}.png'));
            file.writeAsBytesSync(content);
            return file.path;
          }
          return content;
        }
        return null; // writeImage etc.
      });
    });
    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test(
      'copyImageBytesToClipboard succeeds when the channel accepts',
      () async {
        final ok = await service.copyImageBytesToClipboard(_pngBytes);
        if (Platform.isLinux) {
          // Op Linux schrijft de service via het eigen ocideck/clipboard-
          // kanaal (#758, getest in linux_clipboard_write_test.dart). Dat is
          // hier niet gemockt: eerlijk false, en het pasteboard-kanaal blijft
          // onaangeraakt.
          expect(ok, isFalse);
          expect(calls, isEmpty);
        } else {
          expect(ok, isTrue);
          expect(calls.single.method, 'writeImage');
        }
      },
    );

    test('pasteImageDetailed reports an empty clipboard', () async {
      clipboardImage = null;
      final outcome = await service.pasteImageDetailed(projectPath: tmp.path);
      expect(outcome.path, isNull);
      expect(outcome.failure, ImageImportFailure.noClipboardImage);
    });

    test('pasteImageDetailed writes into the project images/ dir', () async {
      clipboardImage = _pngBytes;
      final outcome = await service.pasteImageDetailed(projectPath: tmp.path);

      expect(outcome.failure, isNull);
      expect(outcome.path, isNotNull);
      expect(outcome.path, startsWith('images/'));
      expect(File(p.join(tmp.path, outcome.path!)).existsSync(), isTrue);
    });

    test('pasteImage returns just the path on success', () async {
      clipboardImage = _pngBytes;
      final path = await service.pasteImage(projectPath: tmp.path);
      expect(path, startsWith('images/'));
    });

    test('pasteImageDetailed reports a write failure', () async {
      clipboardImage = _pngBytes;
      // Point the "project" at a regular file so creating images/ under it
      // raises a FileSystemException the service turns into writeFailed.
      final asFile = File(p.join(tmp.path, 'not_a_dir'));
      await asFile.writeAsBytes([0]);

      final outcome = await service.pasteImageDetailed(
        projectPath: asFile.path,
      );
      expect(outcome.failure, ImageImportFailure.writeFailed);
    });
  });
}
