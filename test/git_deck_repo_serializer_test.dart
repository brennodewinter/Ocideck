import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/asset_pool.dart';
import 'package:ocideck/services/git/deck_repo_serializer.dart';
import 'package:ocideck/services/markdown_service.dart';

import 'git_forge_fake.dart';

// buildDeckRepoFiles is de omkering van het open-pad: het deck-in-de-editor
// wordt zijn repo-bestandenset (deck.md + pool-blobs), met de afbeeldingen
// mem:→repo: herschreven. De test bewaakt dat de heenweg klopt én dat de pool
// zijn werk doet: wat er al staat gaat niet opnieuw omhoog.
void main() {
  const deckDir = 'decks/kwartaalcijfers';
  final md = MarkdownService();

  setUp(AssetPool.clearCache);

  Uint8List png(int seed) =>
      Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, seed, seed + 1, seed + 2]);

  String refFor(Uint8List bytes, String ext) =>
      GitRepoLayout.assetRef(sha256.convert(bytes).toString(), ext)!;

  /// Resolver die een vaste map van pad→bytes naspeelt (de rol van
  /// ImageService.readSlideImageBytes in de app).
  AssetByteResolver resolverFrom(Map<String, Uint8List> table) =>
      (path) async => table[path];

  AssetPool poolFor(FakeRepo repo) =>
      AssetPool(forge: FakeForge(repo), branch: 'main');

  Deck deckWith(List<Slide> slides) => Deck(title: 'Kwartaal', slides: slides);

  Slide imageSlide(String imagePath, {String imagePath2 = ''}) =>
      Slide.create(SlideType.bulletsImage).copyWith(
        title: 'Beeld',
        bullets: const ['punt'],
        imagePath: imagePath,
        imagePath2: imagePath2,
      );

  test('een mem:-afbeelding wordt gepoold en deck.md verwijst ernaar', () async {
    final bytes = png(1);
    const memPath = 'mem:img-1';
    final ref = refFor(bytes, 'png');
    final poolPath = GitRepoLayout.assetPathOf(ref)!;

    final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
    final out = await buildDeckRepoFiles(
      deckWith([imageSlide(memPath)]),
      md: md,
      pool: poolFor(repo),
      deckDir: deckDir,
      resolveBytes: resolverFrom({memPath: bytes}),
    );

    // deck.md staat onder de deckmap en verwijst naar de repo:-ref, niet mem:.
    final deckMd = out.upserts['$deckDir/deck.md'];
    expect(deckMd, isNotNull);
    final markdown = utf8.decode(deckMd!);
    expect(markdown, contains(ref));
    expect(markdown, isNot(contains(memPath)));

    // De blob gaat mee onder zijn poolpad, met exact de bytes.
    expect(out.upserts[poolPath], bytes);
    expect(out.warnings, isEmpty);
  });

  test('een blob die al in de pool staat gaat niet opnieuw omhoog', () async {
    final bytes = png(2);
    const memPath = 'mem:img-2';
    final ref = refFor(bytes, 'png');
    final poolPath = GitRepoLayout.assetPathOf(ref)!;

    // De repo heeft de blob al.
    final repo = FakeRepo(branches: {'main': 'c0'}, files: {poolPath: bytes});
    final out = await buildDeckRepoFiles(
      deckWith([imageSlide(memPath)]),
      md: md,
      pool: poolFor(repo),
      deckDir: deckDir,
      resolveBytes: resolverFrom({memPath: bytes}),
    );

    // deck.md verwijst er wél naar, maar de blob zit niet in de upserts.
    expect(utf8.decode(out.upserts['$deckDir/deck.md']!), contains(ref));
    expect(out.upserts.containsKey(poolPath), isFalse);
    expect(out.upserts.keys, ['$deckDir/deck.md']);
  });

  test('twee slides met dezelfde afbeelding leveren één blob', () async {
    final bytes = png(3);
    const memPath = 'mem:img-3';
    final poolPath = GitRepoLayout.assetPathOf(refFor(bytes, 'png'))!;

    final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
    final out = await buildDeckRepoFiles(
      deckWith([imageSlide(memPath), imageSlide(memPath)]),
      md: md,
      pool: poolFor(repo),
      deckDir: deckDir,
      resolveBytes: resolverFrom({memPath: bytes}),
    );

    final blobPaths = out.upserts.keys.where((k) => k.startsWith('assets/'));
    expect(blobPaths, [poolPath]);
  });

  test('twee kolommen op één slide poolen allebei', () async {
    final b1 = png(4);
    final b2 = png(5);
    final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
    final out = await buildDeckRepoFiles(
      deckWith([imageSlide('mem:a', imagePath2: 'mem:b')]),
      md: md,
      pool: poolFor(repo),
      deckDir: deckDir,
      resolveBytes: resolverFrom({'mem:a': b1, 'mem:b': b2}),
    );
    expect(out.upserts[GitRepoLayout.assetPathOf(refFor(b1, 'png'))!], b1);
    expect(out.upserts[GitRepoLayout.assetPathOf(refFor(b2, 'png'))!], b2);
  });

  test(
    'video en audio worden gemeld, niet als kapotte ref geschreven',
    () async {
      final slide = Slide.create(SlideType.video).copyWith(
        title: 'Film',
        videoPath: 'mem:vid',
        audioPath: '/tmp/geluid.mp3',
      );
      final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
      final out = await buildDeckRepoFiles(
        deckWith([slide]),
        md: md,
        pool: poolFor(repo),
        deckDir: deckDir,
        resolveBytes: resolverFrom(const {}),
      );
      expect(out.warnings, containsAll(['mem:vid', '/tmp/geluid.mp3']));
      expect(out.upserts.keys, ['$deckDir/deck.md']);
    },
  );

  test('een afbeelding die niet te lezen is wordt gemeld', () async {
    const memPath = 'mem:weg'; // na herlaad: geen bytes meer
    final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
    final out = await buildDeckRepoFiles(
      deckWith([imageSlide(memPath)]),
      md: md,
      pool: poolFor(repo),
      deckDir: deckDir,
      resolveBytes: resolverFrom(const {}),
    );
    expect(out.warnings, [memPath]);
    expect(out.upserts.keys, ['$deckDir/deck.md']);
  });

  test('een reeds gepoolde repo:-afbeelding blijft ongemoeid', () async {
    final ref = refFor(png(6), 'png');
    final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
    final out = await buildDeckRepoFiles(
      deckWith([imageSlide(ref)]),
      md: md,
      pool: poolFor(repo),
      deckDir: deckDir,
      // resolver wordt niet geraadpleegd voor een repo:-ref
      resolveBytes: (_) async => throw StateError('mag niet gelezen worden'),
    );
    expect(utf8.decode(out.upserts['$deckDir/deck.md']!), contains(ref));
    expect(out.warnings, isEmpty);
    expect(out.upserts.keys, ['$deckDir/deck.md']);
  });
}
