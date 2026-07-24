import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:path/path.dart' as p;

/// Dat een geïmporteerde video ook echt op schijf belandt.
///
/// De import zet ingebedde media als `mem:`-pad neer; `copyMediaToProject` moet
/// die bytes bij het opslaan in de `media/`-map van het deck schrijven. Die tak
/// bestond eerst niet — `_shouldCopy` eiste een absoluut pad, dus een `mem:`-pad
/// viel er stil buiten en het deck hield een verwijzing over naar een bestand
/// dat nooit is weggeschreven. De reparatie zat in de eerste ronde zonder test;
/// de dekkingsmeting wees dat aan (#772).
void main() {
  late Directory project;

  setUp(() {
    WebAssetStore.clear();
    project = Directory.systemTemp.createTempSync('ocideck_media_');
  });
  tearDown(() {
    WebAssetStore.clear();
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  final service = ImageService();

  test(
    'een mem:-video wordt in media/ geschreven met zijn eigen bytes',
    () async {
      final movie = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final memPath = WebAssetStore.put(movie, name: 'clip.mp4');
      final slide = Slide.create(SlideType.video).copyWith(videoPath: memPath);

      final out = await service.copyMediaToProject([slide], project.path);

      expect(out.single.videoPath, 'media/clip.mp4');
      final written = File(p.join(project.path, 'media', 'clip.mp4'));
      expect(written.existsSync(), isTrue, reason: 'de bytes horen op schijf');
      expect(written.readAsBytesSync(), movie);
    },
  );

  test('een mem:-audio zonder extensie wordt geen .mp4', () async {
    // Video en audio deelden één terugval, dus audio zonder extensie landde als
    // `.mp4`. Per soort, dus.
    final sound = Uint8List.fromList([7, 7, 7]);
    final memPath = WebAssetStore.put(sound, name: 'opname');
    final slide = Slide.create(SlideType.video).copyWith(audioPath: memPath);

    final out = await service.copyMediaToProject([slide], project.path);

    expect(out.single.audioPath, isNot(endsWith('.mp4')));
    expect(out.single.audioPath, 'media/opname.m4a');
  });

  test('een gewoon projectrelatief pad blijft ongemoeid', () async {
    final slide = Slide.create(
      SlideType.video,
    ).copyWith(videoPath: 'media/bestaand.mp4');

    final out = await service.copyMediaToProject([slide], project.path);

    expect(out.single.videoPath, 'media/bestaand.mp4');
  });
}
