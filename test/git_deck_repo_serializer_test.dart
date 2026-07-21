import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/asset_index.dart';
import 'package:ocideck/services/git/asset_pool.dart';
import 'package:ocideck/services/git/deck_repo_serializer.dart';
import 'package:ocideck/services/git/repo_asset_resolver.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';

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

  // Grafiekdata krijgt een eigen bestand op een stabiel pad naast deck.md.
  // Regressie op twee dingen tegelijk: de cijfers mogen niet verdwijnen (dat
  // deden ze, stil, tot de verwijzing zonder data werd gecommit), en ze mogen
  // niet in de content-geadresseerde pool belanden — dan levert elke gewijzigde
  // cel een nieuw bestand op en is er geen diff te lezen.
  group('grafiekdata', () {
    Slide chartSlide({
      required String source,
      List<double> data = const [10, 14],
    }) => Slide.create(SlideType.chart).copyWith(
      customMarkdown: ChartSpec(
        type: ChartType.line,
        title: 'Omzet',
        source: source,
        x: const ['Q1', 'Q2'],
        series: [ChartSeries(name: '2025', data: data)],
      ).toBlock(),
    );

    Future<RepoDeckFiles> build(Deck deck) async => buildDeckRepoFiles(
      deck,
      md: md,
      pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
      deckDir: deckDir,
      resolveBytes: resolverFrom({}),
    );

    test('krijgt een eigen bestand, deck.md houdt de verwijzing', () async {
      final out = await build(
        deckWith([chartSlide(source: 'data/omzet.json')]),
      );

      // Een stabiel pad onder de deckmap, niet assets/<hash>.
      expect(out.upserts.containsKey('$deckDir/data/omzet.json'), isTrue);
      expect(out.upserts.keys.where((k) => k.startsWith('assets/')), isEmpty);
      expect(
        utf8.decode(out.upserts['$deckDir/data/omzet.json']!),
        contains('10'),
      );

      final spec = ChartSpec.parse(
        md
            .parseDeck(utf8.decode(out.upserts['$deckDir/deck.md']!))!
            .slides
            .single
            .customMarkdown,
      );
      expect(spec.source, 'data/omzet.json');
      expect(spec.hasInlineData, isFalse);
    });

    test('hetzelfde pad blijft hetzelfde pad bij een gewijzigde cel', () async {
      final first = await build(
        deckWith([
          chartSlide(source: 'data/omzet.json', data: [10, 14]),
        ]),
      );
      final second = await build(
        deckWith([
          chartSlide(source: 'data/omzet.json', data: [10, 99]),
        ]),
      );

      // Zou de data via de pool lopen, dan stond de nieuwe inhoud onder een
      // ander pad en was de wijziging geen diff maar een nieuw bestand.
      const path = '$deckDir/data/omzet.json';
      expect(first.upserts.containsKey(path), isTrue);
      expect(second.upserts.containsKey(path), isTrue);
      expect(utf8.decode(second.upserts[path]!), contains('99'));
    });

    test('een deck dat een .csv koppelt houdt .csv', () async {
      final out = await build(deckWith([chartSlide(source: 'data/omzet.csv')]));
      expect(
        utf8.decode(out.upserts['$deckDir/data/omzet.csv']!),
        contains('Q1,10'),
      );
    });

    test(
      'een source buiten de deckmap wordt gemeld, niet geschreven',
      () async {
        final out = await build(
          deckWith([chartSlide(source: '../../geheim.json')]),
        );
        expect(out.upserts.keys, ['$deckDir/deck.md']);
        expect(out.warnings, contains('../../geheim.json'));
      },
    );

    test(
      'zonder cijfers in het geheugen blijft het bestand ongemoeid',
      () async {
        // Het exemplaar in de repo is dan het enige dat er is; overschrijven met
        // een leeg bestand zou het weggooien.
        final out = await build(
          deckWith([
            Slide.create(SlideType.chart).copyWith(
              customMarkdown: const ChartSpec(
                source: 'data/omzet.json',
              ).toBlock(),
            ),
          ]),
        );
        expect(out.upserts.keys, ['$deckDir/deck.md']);
      },
    );

    test(
      'round-trip: schrijven en terugleren geeft de cijfers terug',
      () async {
        final out = await build(
          deckWith([chartSlide(source: 'data/omzet.json')]),
        );
        final parsed = md.parseDeck(
          utf8.decode(out.upserts['$deckDir/deck.md']!),
        )!;

        final back = await withRepoChartData(
          parsed,
          deckDir: deckDir,
          read: (path) async => out.upserts[path],
        );
        final spec = ChartSpec.parse(back.deck.slides.single.customMarkdown);
        expect(spec.x, ['Q1', 'Q2']);
        expect(spec.series.single.data, [10, 14]);
        expect(back.missing, isEmpty);
      },
    );

    test('een ontbrekend databestand wordt gemeld, niet verzwegen', () async {
      final out = await build(
        deckWith([chartSlide(source: 'data/omzet.json')]),
      );
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;

      // De blob is weg uit de repo: de grafiek tekent leeg, maar dat hoort
      // gezegd te worden in plaats van als "geen cijfers" te passeren.
      final back = await withRepoChartData(
        parsed,
        deckDir: deckDir,
        read: (_) async => null,
      );
      expect(back.missing, ['data/omzet.json']);
      expect(
        ChartSpec.parse(back.deck.slides.single.customMarkdown).hasInlineData,
        isFalse,
      );
    });

    test('een leesfout laat het deck openen, niet mislukken', () async {
      final out = await build(
        deckWith([chartSlide(source: 'data/omzet.json')]),
      );
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final back = await withRepoChartData(
        parsed,
        deckDir: deckDir,
        read: (_) async => throw StateError('forge onbereikbaar'),
      );
      expect(back.missing, ['data/omzet.json']);
      expect(back.deck.slides, hasLength(1));
    });

    test('een source met ../ wordt bij het lezen niet gevolgd', () async {
      final deck = deckWith([chartSlide(source: '../../geheim.json')]);
      var asked = false;
      final back = await withRepoChartData(
        deck.copyWith(
          slides: [
            Slide.create(SlideType.chart).copyWith(
              customMarkdown: const ChartSpec(
                source: '../../geheim.json',
              ).toBlock(),
            ),
          ],
        ),
        deckDir: deckDir,
        read: (path) async {
          asked = true;
          return null;
        },
      );
      expect(asked, isFalse, reason: 'het pad mag niet eens opgevraagd worden');
      expect(back.missing, ['../../geheim.json']);
    });
  });

  // Afbeeldingen in de vrije tekst horen dezelfde route te lopen als de velden.
  // Blijft er een gewoon pad staan, dan kent de forge de verwijzing niet én
  // telt de asset voor AssetIndex als ongebruikt — en opruimen is onomkeerbaar.
  group('afbeeldingen in de vrije tekst', () {
    Slide textSlide(String markdown) => Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(title: 'Tekst', customMarkdown: markdown);

    test('een inline mem:-afbeelding wordt gepoold en herschreven', () async {
      final bytes = png(11);
      final ref = refFor(bytes, 'png');
      final poolPath = GitRepoLayout.assetPathOf(ref)!;

      final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
      final out = await buildDeckRepoFiles(
        deckWith([textSlide('Kijk hier:\n\n![w:600 de foto](mem:inline)\n')]),
        md: md,
        pool: poolFor(repo),
        deckDir: deckDir,
        resolveBytes: resolverFrom({'mem:inline': bytes}),
      );

      final markdown = utf8.decode(out.upserts['$deckDir/deck.md']!);
      expect(markdown, contains('![w:600 de foto]($ref)'));
      expect(markdown, isNot(contains('mem:inline')));
      expect(out.upserts[poolPath], bytes);
      expect(out.warnings, isEmpty);
    });

    test('AssetIndex ziet die verwijzing terug in de deck.md', () async {
      final bytes = png(12);
      final ref = refFor(bytes, 'png');
      final repo = FakeRepo(branches: {'main': 'c0'}, files: {});
      final out = await buildDeckRepoFiles(
        deckWith([textSlide('![x](mem:inline)')]),
        md: md,
        pool: poolFor(repo),
        deckDir: deckDir,
        resolveBytes: resolverFrom({'mem:inline': bytes}),
      );

      // referencesIn scant de ruwe tekst, dus een inline verwijzing komt daar
      // gratis in mee — zolang hij maar gepoold ís.
      expect(
        AssetIndex.referencesIn(utf8.decode(out.upserts['$deckDir/deck.md']!)),
        {ref},
      );
    });

    test('en komt bij het openen als mem: weer terug', () async {
      final bytes = png(13);
      final ref = refFor(bytes, 'png');
      final poolPath = GitRepoLayout.assetPathOf(ref)!;

      final repo = FakeRepo(
        branches: {'main': 'c0'},
        files: {poolPath: bytes},
      );
      final deck = await resolveRepoAssetsToMem(
        deckWith([textSlide('tekst ![alt]($ref) tekst')]),
        poolFor(repo),
        sourceName: 'test',
      );

      final markdown = deck.slides.single.customMarkdown;
      expect(markdown, isNot(contains(ref)));
      final mem = RegExp(r'!\[alt\]\(([^)]+)\)').firstMatch(markdown)!.group(1)!;
      expect(WebAssetStore.isMemPath(mem), isTrue);
      expect(WebAssetStore.bytesFor(mem), bytes);
    });
  });
}
