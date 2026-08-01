import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/package_asset_resolver.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/mem_asset_blob.dart';

/// #854: video/audio uit een `.ocideck`-pakket kwamen op web niet in de
/// [WebAssetStore] terecht, dus een `<video src="media/…">` wees naar een
/// archief-intern pad dat daar geen URL is en er speelde niets.
void main() {
  tearDown(() {
    WebAssetStore.clear();
    WebAssetStore.overrideTotalBudgetForTest(null);
  });

  Uint8List fill(int v, int len) => Uint8List.fromList(List.filled(len, v));

  Deck deckWith(List<Slide> slides) => Deck(title: 'demo', slides: slides);

  test(
    'pakket-video en -audio gaan naar mem: en de bytes staan in de store',
    () {
      final video = fill(7, 64);
      final audio = fill(9, 32);
      final out = attachPackageAssetsToMem(
        deckWith([
          Slide.create(SlideType.video).copyWith(videoPath: 'media/clip.mp4'),
          Slide.create(SlideType.bullets).copyWith(audioPath: 'media/tune.mp3'),
        ]),
        <({String name, Uint8List bytes})>[
          (name: 'media/clip.mp4', bytes: video),
          (name: 'media/tune.mp3', bytes: audio),
        ],
        'demo.md',
      );

      final vp = out.slides[0].videoPath;
      final ap = out.slides[1].audioPath;
      expect(WebAssetStore.isMemPath(vp), isTrue, reason: 'video → mem:');
      expect(WebAssetStore.isMemPath(ap), isTrue, reason: 'audio → mem:');
      expect(WebAssetStore.bytesFor(vp), video);
      expect(WebAssetStore.bytesFor(ap), audio);
    },
  );

  test('een externe video-URL wordt niet herschreven', () {
    final out = attachPackageAssetsToMem(
      deckWith([
        Slide.create(
          SlideType.video,
        ).copyWith(videoPath: 'https://youtu.be/abc'),
      ]),
      const [],
      'demo.md',
    );
    expect(out.slides[0].videoPath, 'https://youtu.be/abc');
  });

  test('een video zonder bijbehorend pakket-lid blijft ongewijzigd', () {
    final out = attachPackageAssetsToMem(
      deckWith([
        Slide.create(
          SlideType.video,
        ).copyWith(videoPath: 'media/ontbreekt.mp4'),
      ]),
      const [],
      'demo.md',
    );
    expect(out.slides[0].videoPath, 'media/ontbreekt.mp4');
  });

  test(
    'een pakket boven het resterende budget laat geen halve assets achter',
    () {
      WebAssetStore.overrideTotalBudgetForTest(80);
      final video = fill(7, 64);
      final audio = fill(9, 32);

      expect(
        () => attachPackageAssetsToMem(
          deckWith([
            Slide.create(SlideType.video).copyWith(videoPath: 'media/clip.mp4'),
            Slide.create(
              SlideType.bullets,
            ).copyWith(audioPath: 'media/tune.mp3'),
          ]),
          <({String name, Uint8List bytes})>[
            (name: 'media/clip.mp4', bytes: video),
            (name: 'media/tune.mp3', bytes: audio),
          ],
          'demo.md',
        ),
        throwsA(isA<WebAssetBudgetExceeded>()),
      );
      expect(WebAssetStore.isEmpty, isTrue);
      expect(WebAssetStore.totalBytes, 0);
    },
  );

  // Buiten de browser bestaat er geen blob-URL; de stub-helft van
  // mem_asset_blob levert dan null (de web-helft staat in de dekkingsbasislijn).
  test('memAssetBlobUrl geeft buiten web null', () {
    expect(memAssetBlobUrl('mem:whatever'), isNull);
  });
}
