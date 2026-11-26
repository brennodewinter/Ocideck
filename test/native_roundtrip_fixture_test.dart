import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

import 'support/native_roundtrip_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'authored all-type fixture survives real Markdown and package storage',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'native-roundtrip-fixture-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final entry in {
        'images/a.png': 'assets/images/ocideck-logo.png',
        'images/b.png': 'assets/images/librekat-logo.png',
        'media/film.mp4': 'integration_test/fixtures/audio/silent-video.mp4',
        'audio/tone.wav':
            'integration_test/fixtures/audio_formats/wav-pcm16.wav',
      }.entries) {
        final file = File(p.join(dir.path, entry.key));
        file.parent.createSync(recursive: true);
        File(entry.value).copySync(file.path);
      }
      File(p.join(dir.path, 'media/film.vtt')).writeAsStringSync(
        'WEBVTT\n\n00:00.000 --> 00:01.000\nNative bijschrift\n',
      );
      Directory(p.join(dir.path, 'data')).createSync();
      File(
        p.join(dir.path, 'data/series.csv'),
      ).writeAsStringSync(',Serie\nEen,12.0\nTwee,34.0\n');
      final input = nativeRoundtripFixture(dir.path);
      expect(input.slides.map((s) => s.type), SlideType.values);
      final expected = nativeDeckSnapshot(input);
      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );
      final path = p.join(dir.path, 'deck.md');
      await service.saveDeck(input, path);
      final reopened = (await service.openDeck(path))!;
      for (var i = 0; i < expected.length; i++) {
        final actual = nativeSlideSnapshot(
          reopened.slides[i],
          reopened.projectPath,
        );
        for (final field in expected[i].entries) {
          expect(
            actual[field.key],
            field.value,
            reason: '${input.slides[i].type.name}.${field.key}',
          );
        }
      }
      final package = p.join(dir.path, 'archive.ocideck');
      await service.exportPackage(input, package);
      final importedPath = await service.importPackageBytes(
        File(package).readAsBytesSync(),
        p.join(dir.path, 'unpacked'),
      );
      final imported = (await service.openDeck(importedPath!))!;
      expect(nativeDeckSnapshot(imported), expected);
    },
  );
}
