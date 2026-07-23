import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/asset_index.dart';
import 'package:ocideck/services/git/asset_pool.dart';
import 'package:ocideck/services/git/deck_repo_serializer.dart';
import 'package:ocideck/services/git/repo_asset_resolver.dart';
import 'package:ocideck/services/annotation_codec.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/miauw_codec.dart';
import 'package:ocideck/services/privacy/dismissal_codec.dart';
import 'package:ocideck/services/user_notes_codec.dart';
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

      final repo = FakeRepo(branches: {'main': 'c0'}, files: {poolPath: bytes});
      final deck = await resolveRepoAssetsToMem(
        deckWith([textSlide('tekst ![alt]($ref) tekst')]),
        poolFor(repo),
        sourceName: 'test',
      );

      final markdown = deck.slides.single.customMarkdown;
      expect(markdown, isNot(contains(ref)));
      final mem = RegExp(
        r'!\[alt\]\(([^)]+)\)',
      ).firstMatch(markdown)!.group(1)!;
      expect(WebAssetStore.isMemPath(mem), isTrue);
      expect(WebAssetStore.bytesFor(mem), bytes);
    });
  });

  group('notities', () {
    const notesPath = '$deckDir/deck.user-notes.json';

    /// Bouwt met een lezer die [inRepo] naspeelt — wat er nú in de deckmap
    /// ligt. Dat is wat bepaalt of het notitiebestand weg mág.
    Future<RepoDeckFiles> build(
      Deck deck, {
      Map<String, Uint8List> inRepo = const {},
    }) async => buildDeckRepoFiles(
      deck,
      md: md,
      pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
      deckDir: deckDir,
      resolveBytes: resolverFrom({}),
      read: (path) async => inRepo[path],
    );

    Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

    /// Een geldig notitiebestand zoals wíj het schrijven.
    Uint8List onzeNotities() {
      final slide = Slide.create(SlideType.title).copyWith(title: 'Eén');
      return bytesOf(
        UserNotesCodec.encode([slide], {slide.id: 'iets'}, forTextMerge: true)!,
      );
    }

    /// Het deck zoals het uit de repo terugkomt: `deck.md` opnieuw geparsed
    /// (de dia-id's zijn dan andere), en daarna de notities eraan gehangen.
    /// Dat is de volgorde die de app ook aanhoudt.
    Future<Deck> reopen(RepoDeckFiles out) async {
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoUserNotes(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );
      return terug.deck;
    }

    /// Een deck zonder enige notitie — de andere kant van elke toets hieronder.
    Deck deckZonderNotities() =>
        deckWith([Slide.create(SlideType.title).copyWith(title: 'Eén')]);

    Deck deckWithNote(String note, {String title = 'Eén'}) {
      final slide = Slide.create(SlideType.title).copyWith(title: title);
      return Deck(
        title: 'Kwartaal',
        slides: [slide],
        userNotes: {slide.id: note},
      );
    }

    test('krijgen een eigen bestand naast deck.md, niet in de pool', () async {
      final out = await build(deckWithNote('Noem het budget'));

      // Een stabiel pad onder de deckmap. In de content-geadresseerde pool zou
      // elk getypt teken een nieuw bestand minten en het vorige laten
      // wegkwijnen — dat levert precies geen leesbare diff op.
      expect(out.upserts.containsKey(notesPath), isTrue);
      expect(out.upserts.keys.where((k) => k.startsWith('assets/')), isEmpty);
      expect(utf8.decode(out.upserts[notesPath]!), contains('Noem het budget'));
    });

    test('komen er bij het openen weer aan, op de juiste dia', () async {
      final out = await build(deckWithNote('Noem het budget'));
      final deck = await reopen(out);

      // Niet op id vergeleken: die worden bij elk parsen opnieuw uitgedeeld.
      // Dát is precies waarom de codec op vingerafdruk werkt.
      expect(deck.userNotes.values.single, 'Noem het budget');
      expect(deck.userNotes.keys.single, deck.slides.single.id);
    });

    test('de tweede dia krijgt zijn eigen notitie terug', () async {
      final a = Slide.create(SlideType.title).copyWith(title: 'Eén');
      final b = Slide.create(SlideType.title).copyWith(title: 'Twee');
      final out = await build(
        Deck(
          title: 'Kwartaal',
          slides: [a, b],
          userNotes: {a.id: 'bij één', b.id: 'bij twee'},
        ),
      );
      final deck = await reopen(out);

      expect(deck.userNotes[deck.slides[0].id], 'bij één');
      expect(deck.userNotes[deck.slides[1].id], 'bij twee');
    });

    test('staan per regel in het bestand, zodat git ze kan mergen', () async {
      // Dit is de toets achter D7. Die zegt dat dit bestand door git's gewone
      // tekst-merge gaat en dat twee auteurs op verschillende dia's schoon
      // samenvoegen. Op één regel — wat jsonEncode oplevert en wat de sidecar
      // op schijf is — botst élke wijziging met élke andere en klopt die
      // belofte niet.
      final a = Slide.create(SlideType.title).copyWith(title: 'Eén');
      final b = Slide.create(SlideType.title).copyWith(title: 'Twee');
      final out = await build(
        Deck(
          title: 'Kwartaal',
          slides: [a, b],
          userNotes: {a.id: 'bij één', b.id: 'bij twee'},
        ),
      );

      final regels = const LineSplitter().convert(
        utf8.decode(out.upserts[notesPath]!),
      );
      expect(regels.length, greaterThan(4));
      // De twee notities staan niet op dezelfde regel; anders zou een wijziging
      // aan de ene de andere raken.
      final eerste = regels.indexWhere((r) => r.contains('bij één'));
      final tweede = regels.indexWhere((r) => r.contains('bij twee'));
      expect(eerste, isNot(-1));
      expect(tweede, isNot(eerste));
    });

    test('een deck zonder notities schrijft geen bestand', () async {
      final out = await build(deckZonderNotities());

      expect(out.upserts.containsKey(notesPath), isFalse);
    });

    test('de laatste notitie wissen haalt het bestand wég', () async {
      // Zonder dit zou de commit het oude bestand laten staan en hing de
      // notitie er bij de volgende open gewoon weer aan. Een wissing die
      // terugkomt is erger dan een die niet werkt: de gebruiker dacht dat het
      // weg was.
      final out = await build(
        deckZonderNotities(),
        inRepo: {notesPath: onzeNotities()},
      );

      expect(out.deletes, contains(notesPath));
      expect(out.upserts.containsKey(notesPath), isFalse);
    });

    test('een deck mét notities verwijdert het bestand niet', () async {
      final out = await build(deckWithNote('blijft staan'));

      expect(out.deletes, isEmpty);
    });

    test('een lege notitie telt als geen notitie', () async {
      final out = await build(
        deckWithNote('   '),
        inRepo: {notesPath: onzeNotities()},
      );

      expect(out.upserts.containsKey(notesPath), isFalse);
      expect(out.deletes, contains(notesPath));
    });

    group('een bestand dat we niet konden lezen blijft staan', () {
      // De asymmetrie: ten onrechte laten staan kost een verweesd bestand dat
      // vanzelf overschreven wordt. Ten onrechte verwijderen kost werk van een
      // mede-auteur, en die merkt het pas als hij het zoekt.
      Future<List<String>> deletesMet(Uint8List? inhoud) async {
        final out = await build(
          deckZonderNotities(),
          inRepo: {notesPath: ?inhoud},
        );
        return out.deletes;
      }

      test('conflictmarkeringen uit een merge buiten OciDeck', () async {
        // Het meest waarschijnlijke geval: iemand voegde de takken samen in de
        // webinterface van de forge. Markeringen zijn geen geldige JSON.
        expect(
          await deletesMet(
            bytesOf('<<<<<<< HEAD\n{"version":2}\n=======\n{}\n>>>>>>> x\n'),
          ),
          isEmpty,
        );
      });

      test('een sidecar van een nieuwere build', () async {
        // Die leest deze build bewust niet; hem daarna wissen zou weggooien wat
        // we juist met rust lieten.
        expect(
          await deletesMet(bytesOf('{"version":99,"slides":[]}')),
          isEmpty,
        );
      });

      test('geen geldige UTF-8', () async {
        expect(await deletesMet(Uint8List.fromList([0xff, 0xfe])), isEmpty);
      });

      test('boven de bytegrens', () async {
        expect(await deletesMet(Uint8List(maxRepoUserNotesBytes + 1)), isEmpty);
      });

      test('een leesfout', () async {
        final out = await buildDeckRepoFiles(
          deckZonderNotities(),
          md: md,
          pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
          deckDir: deckDir,
          resolveBytes: resolverFrom({}),
          read: (_) async => throw StateError('netwerk weg'),
        );
        expect(out.deletes, isEmpty);
      });

      test('zonder lezer wordt er nooit verwijderd', () async {
        // Niet weten is geen reden om te wissen. De native paden geven geen
        // lezer mee.
        final out = await buildDeckRepoFiles(
          deckZonderNotities(),
          md: md,
          pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
          deckDir: deckDir,
          resolveBytes: resolverFrom({}),
        );
        expect(out.deletes, isEmpty);
      });

      test('maar een leesbaar bestand mag wél weg', () async {
        // De tegenproef: zonder deze zou de hele groep hierboven ook slagen als
        // er nooit iets verwijderd werd.
        expect(await deletesMet(onzeNotities()), contains(notesPath));
      });
    });

    group('en wordt ook niet overschreven', () {
      // De spiegel van de groep hierboven, en de nare helft: overschrijven is
      // net zo goed half inlezen als verwijderen dat is, maar het resultaat
      // ziet er daarna gezónd uit. Niemand gaat dan in de historie zoeken.
      //
      // Op schijf staat `_sidecarUntouchable` daarom vóór de vertakking en dekt
      // hij beide richtingen; hier moest dat nog gelijkgetrokken.
      Future<RepoDeckFiles> schrijfMet(Uint8List inhoud) =>
          build(deckWithNote('mijn ene notitie'), inRepo: {notesPath: inhoud});

      test('een sidecar van een nieuwere build blijft ongemoeid', () async {
        // Het scenario: een collega op een nieuwere build schreef version 3.
        // Jij ziet terecht geen notities, typt er één, slaat op — en zonder
        // deze poort ging jouw ene v2-notitie over hun hele bestand heen.
        final out = await schrijfMet(
          Uint8List.fromList(utf8.encode('{"version":99,"slides":[]}')),
        );

        expect(out.upserts.containsKey(notesPath), isFalse);
        expect(out.deletes, isEmpty);
      });

      test('conflictmarkeringen blijven staan voor een mens', () async {
        final out = await schrijfMet(
          Uint8List.fromList(
            utf8.encode('<<<<<<< HEAD\n{"version":2}\n=======\n{}\n>>>>>>> x'),
          ),
        );

        expect(out.upserts.containsKey(notesPath), isFalse);
        expect(out.deletes, isEmpty);
      });

      test('maar over ons eigen bestand schrijven mag gewoon', () async {
        // Tegenproef: anders zou deze groep ook slagen als er nooit meer iets
        // geschreven werd, en dan reisde er niets.
        final out = await schrijfMet(onzeNotities());

        expect(out.upserts.containsKey(notesPath), isTrue);
        expect(
          utf8.decode(out.upserts[notesPath]!),
          contains('mijn ene notitie'),
        );
      });

      test('en zonder lezer ook — anders reist er op native niets', () async {
        // Het native pad geeft geen lezer mee. Niet weten mag daar het
        // schrijven niet blokkeren; het blokkeert alleen het verwijderen.
        final out = await buildDeckRepoFiles(
          deckWithNote('op native'),
          md: md,
          pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
          deckDir: deckDir,
          resolveBytes: resolverFrom({}),
        );

        expect(out.upserts.containsKey(notesPath), isTrue);
      });
    });

    group('de werkkopie voor de wachtrij', () {
      // mirrorDeckFiles bepaalt wat er offline wordt weggeschreven, en dat is
      // scherper dan het lijkt: SyncEngine leidt zijn `deletes` af uit wat er
      // in de repo staat maar hier NIET. Een laag die hier ontbreekt wordt bij
      // het legen van de wachtrij dus van de tak verwijderd — een vergissing
      // die als "opgeslagen, gaat mee zodra je weer verbinding hebt" oogt.
      test('de notities gaan mee, naast deck.md', () {
        final files = mirrorDeckFiles(
          deckWithNote('bij Eén'),
          deckDir: deckDir,
          md: md,
        );

        expect(files.keys, contains('$deckDir/deck.md'));
        expect(files.keys, contains(notesPath));
        expect(utf8.decode(files[notesPath]!), contains('bij Eén'));
      });

      test('zonder notities staat het bestand er niet in', () {
        // En dát is dan de bedoelde verwijdering: je wíste je laatste notitie.
        final files = mirrorDeckFiles(
          deckZonderNotities(),
          deckDir: deckDir,
          md: md,
        );

        expect(files.keys, isNot(contains(notesPath)));
      });

      test('ook hier per regel, zodat de merge later klopt', () {
        final a = Slide.create(SlideType.title).copyWith(title: 'Eén');
        final b = Slide.create(SlideType.title).copyWith(title: 'Twee');
        final files = mirrorDeckFiles(
          Deck(
            title: 'Kwartaal',
            slides: [a, b],
            userNotes: {a.id: 'bij één', b.id: 'bij twee'},
          ),
          deckDir: deckDir,
          md: md,
        );

        final regels = const LineSplitter().convert(
          utf8.decode(files[notesPath]!),
        );
        expect(regels.length, greaterThan(4));
      });
    });

    group('een bestand dat niet deugt laat het deck gewoon openen', () {
      Future<Deck> openMet(Uint8List? bytes) async {
        final slide = Slide.create(SlideType.title).copyWith(title: 'Eén');
        final terug = await withRepoUserNotes(
          Deck(title: 'Kwartaal', slides: [slide]),
          deckDir: deckDir,
          read: (path) async => path == notesPath ? bytes : null,
        );
        return terug.deck;
      }

      test('geen bestand', () async {
        expect((await openMet(null)).userNotes, isEmpty);
      });

      test('leeg bestand', () async {
        expect((await openMet(Uint8List(0))).userNotes, isEmpty);
      });

      test('geen geldige JSON', () async {
        final deck = await openMet(
          Uint8List.fromList(utf8.encode('dit is geen json')),
        );
        expect(deck.userNotes, isEmpty);
      });

      test('geen geldige UTF-8', () async {
        expect(
          (await openMet(Uint8List.fromList([0xff, 0xfe]))).userNotes,
          isEmpty,
        );
      });

      test('boven de bytegrens wordt niet ingelezen', () async {
        // Het bestand komt van buiten en jsonDecode legt er nog een kopie
        // bovenop. Een repo waarin dit tientallen megabytes is, is geen deck
        // met veel notities maar iets anders.
        final groot = Uint8List(maxRepoUserNotesBytes + 1);
        expect((await openMet(groot)).userNotes, isEmpty);
      });

      test('een leesfout is geen mislukte open', () async {
        final slide = Slide.create(SlideType.title).copyWith(title: 'Eén');
        final terug = await withRepoUserNotes(
          Deck(title: 'Kwartaal', slides: [slide]),
          deckDir: deckDir,
          read: (_) async => throw StateError('netwerk weg'),
        );
        expect(terug.deck.userNotes, isEmpty);
        expect(terug.onleesbaar, isTrue);
      });
    });
  });

  group('tekeningen', () {
    // De ink-sidecar volgt het spoor van de notities (#541 deel 2): een eigen
    // bestand op een stabiel pad, dezelfde aanraak- en verwijderregels (de
    // groepen hierboven bewijzen die machinerie al — gedeeld via
    // `_repoSidecarState`), plus wat alleen voor ink geldt: de grafsteen moet
    // het bestand ín, anders overleeft een wissing de reis niet.
    const inkPath = '$deckDir/deck.ink.json';

    InkStroke streek(String id, {bool erased = false}) => InkStroke(
      tool: InkTool.pen,
      color: 0xFFEF4444,
      width: 0.004,
      points: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
      id: id,
      erased: erased,
    );

    Future<RepoDeckFiles> build(
      Deck deck, {
      Map<String, Uint8List> inRepo = const {},
    }) async => buildDeckRepoFiles(
      deck,
      md: md,
      pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
      deckDir: deckDir,
      resolveBytes: resolverFrom({}),
      read: (path) async => inRepo[path],
    );

    Deck deckMetInk(List<InkStroke> strokes, {String title = 'Eén'}) {
      final slide = Slide.create(SlideType.title).copyWith(title: title);
      return Deck(
        title: 'Kwartaal',
        slides: [slide],
        annotations: {slide.id: strokes},
      );
    }

    Deck deckZonderInk() =>
        deckWith([Slide.create(SlideType.title).copyWith(title: 'Eén')]);

    /// Een geldig inkbestand zoals wíj het schrijven.
    Uint8List onzeInk() {
      final slide = Slide.create(SlideType.title).copyWith(title: 'Eén');
      return Uint8List.fromList(
        utf8.encode(
          AnnotationCodec.encode(
            [slide],
            {
              slide.id: [streek('s1')],
            },
            forTextMerge: true,
          )!,
        ),
      );
    }

    test('krijgen een eigen bestand naast deck.md, niet in de pool', () async {
      final out = await build(deckMetInk([streek('s1')]));

      expect(out.upserts.containsKey(inkPath), isTrue);
      expect(utf8.decode(out.upserts[inkPath]!), contains('"s1"'));
    });

    test('komen er bij het openen weer aan, op de juiste dia', () async {
      final out = await build(deckMetInk([streek('s1')]));
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoInk(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      // Niet op id vergeleken: die worden bij elk parsen opnieuw uitgedeeld.
      final deck = terug.deck;
      expect(deck.annotations.keys.single, deck.slides.single.id);
      expect(deck.annotations.values.single.single.id, 's1');
    });

    test(
      'een grafsteen reist mee — anders overleeft wissen de reis niet',
      () async {
        // Een dia waarvan álle streken gewist zijn is niet "geen tekeningen":
        // gooi de grafstenen weg en de andere kant van de eerstvolgende merge
        // brengt de streek terug.
        final out = await build(deckMetInk([streek('s1', erased: true)]));

        expect(out.upserts.containsKey(inkPath), isTrue);
        expect(utf8.decode(out.upserts[inkPath]!), contains('"erased"'));
      },
    );

    test('per regel in het bestand, voor kloons zonder driver', () async {
      // In de kloon van de app merged de resolver; een kloon van een ander
      // werktuig valt terug op git's tekst-merge (gemeten: een onbekende
      // driver tekst-merged gewoon). Op één regel botst dáár elke wijziging
      // met elke andere.
      final out = await build(deckMetInk([streek('s1'), streek('s2')]));

      final regels = const LineSplitter().convert(
        utf8.decode(out.upserts[inkPath]!),
      );
      expect(regels.length, greaterThan(4));
    });

    test('een deck zonder tekeningen schrijft geen bestand', () async {
      final out = await build(deckZonderInk());

      expect(out.upserts.containsKey(inkPath), isFalse);
    });

    test('de tekenlaag verdwenen: het bestand gaat wég', () async {
      final out = await build(deckZonderInk(), inRepo: {inkPath: onzeInk()});

      expect(out.deletes, contains(inkPath));
    });

    test('maar niet wanneer het bestand niet van ons is', () async {
      // Zelfde asymmetrie als bij de notities: een sidecar van een nieuwere
      // build met rust laten kost een verweesd bestand; hem wissen kost
      // andermans werk.
      final out = await build(
        deckZonderInk(),
        inRepo: {
          inkPath: Uint8List.fromList(
            utf8.encode('{"version":99,"slides":[]}'),
          ),
        },
      );

      expect(out.deletes, isEmpty);
      expect(out.upserts.containsKey(inkPath), isFalse);
    });

    test('de werkkopie voor de wachtrij draagt de ink ook', () {
      // Ontbreekt de laag in mirrorDeckFiles, dan leidt SyncEngine er een
      // verwijdering uit af bij het legen van de wachtrij.
      final files = mirrorDeckFiles(
        deckMetInk([streek('s1')]),
        deckDir: deckDir,
        md: md,
      );

      expect(files.keys, contains(inkPath));
      expect(utf8.decode(files[inkPath]!), contains('"s1"'));
    });

    test('een onleesbaar bestand laat het deck gewoon openen', () async {
      final slide = Slide.create(SlideType.title).copyWith(title: 'Eén');
      final terug = await withRepoInk(
        Deck(title: 'Kwartaal', slides: [slide]),
        deckDir: deckDir,
        read: (path) async =>
            Uint8List.fromList(utf8.encode('dit is geen json')),
      );

      expect(terug.deck.annotations, isEmpty);
      expect(terug.onleesbaar, isTrue);
    });

    test('withRepoSidecars hangt alle drie de lagen aan', () async {
      final out = await build(deckMetInk([streek('s1')]));
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoSidecars(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      expect(terug.deck.annotations.values.single.single.id, 's1');
      expect(terug.inkUnreadable, isFalse);
    });
  });

  group('terzijdeleggingen', () {
    // #651, het laatste deel: een terzijdelegging is een reviewbesluit over
    // het rapport en reist dus mee. Zelfde machinerie als de notities en de
    // ink (_repoSidecarState/_writeRepoSidecar — daar al bewezen); hier de
    // dismissals-eigen randen: grafstenen zijn inhoud, en het bestand draagt
    // commitments, nooit de gevonden waarde.
    const dPath = '$deckDir/deck.dismissals.json';

    PrivacyDismissal oordeel(String rule, String commitment) =>
        PrivacyDismissal(
          ruleId: rule,
          commitment: commitment,
          at: DateTime.utc(2026, 7, 23, 10),
        );

    Future<RepoDeckFiles> build(
      Deck deck, {
      Map<String, Uint8List> inRepo = const {},
    }) async => buildDeckRepoFiles(
      deck,
      md: md,
      pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
      deckDir: deckDir,
      resolveBytes: resolverFrom({}),
      read: (path) async => inRepo[path],
    );

    Deck deckMet(DeckDismissals? d) => Deck(
      title: 'Kwartaal',
      slides: [Slide.create(SlideType.title).copyWith(title: 'Eén')],
      dismissals: d,
    );

    test('krijgen een eigen bestand naast deck.md, zonder de waarde', () async {
      final c = commitmentFor('zout', 'Jan Jansen');
      final out = await build(
        deckMet(
          DeckDismissals(salt: 'zout', dismissals: [oordeel('nl.naam', c)]),
        ),
      );

      expect(out.upserts.containsKey(dPath), isTrue);
      final inhoud = utf8.decode(out.upserts[dPath]!);
      expect(inhoud, contains('nl.naam'));
      expect(
        inhoud,
        isNot(contains('Jan Jansen')),
        reason: 'de sidecar draagt een commitment, nooit de gevonden waarde',
      );
    });

    test('komen er bij het openen weer aan, met werkend verbergen', () async {
      final c = commitmentFor('zout', 'Jan Jansen');
      final out = await build(
        deckMet(
          DeckDismissals(salt: 'zout', dismissals: [oordeel('nl.naam', c)]),
        ),
      );
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoDismissals(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      expect(terug.deck.dismissals!.hides('nl.naam', 'Jan Jansen'), isTrue);
      expect(terug.deck.dismissals!.salt, 'zout');
    });

    test('alleen grafstenen is nog steeds een bestand', () async {
      // "Alles herroepen" ruimt de sidecar bewust niet op: weggooien laat de
      // terzijdelegging bij de eerstvolgende samenvoeging terugkeren van de
      // andere kant, en dan is de bevinding weer verborgen zonder keuze.
      final out = await build(
        deckMet(
          DeckDismissals(
            salt: 'zout',
            revocations: [oordeel('nl.naam', 'cafe01')],
          ),
        ),
      );

      expect(out.upserts.containsKey(dPath), isTrue);
      expect(utf8.decode(out.upserts[dPath]!), contains('revocations'));
    });

    test('zonder oordelen gaat een eigen bestand wél weg', () async {
      final c = commitmentFor('zout', 'x');
      final bestaand = DismissalCodec.encode(
        DeckDismissals(salt: 'zout', dismissals: [oordeel('nl.naam', c)]),
        forTextMerge: true,
      )!;
      final out = await build(
        deckMet(null),
        inRepo: {dPath: Uint8List.fromList(utf8.encode(bestaand))},
      );

      expect(out.deletes, contains(dPath));
    });

    test('maar niet wanneer het bestand niet van ons is', () async {
      final out = await build(
        deckMet(null),
        inRepo: {
          dPath: Uint8List.fromList(utf8.encode('{"version":99,"salt":"z"}')),
        },
      );

      expect(out.deletes, isEmpty);
      expect(out.upserts.containsKey(dPath), isFalse);
    });

    test('de werkkopie voor de wachtrij draagt ze ook', () {
      final c = commitmentFor('zout', 'x');
      final files = mirrorDeckFiles(
        deckMet(
          DeckDismissals(salt: 'zout', dismissals: [oordeel('nl.naam', c)]),
        ),
        deckDir: deckDir,
        md: md,
      );

      expect(files.keys, contains(dPath));
    });

    test('withRepoSidecars hangt ook deze laag aan', () async {
      final c = commitmentFor('zout', 'Jan Jansen');
      final out = await build(
        deckMet(
          DeckDismissals(salt: 'zout', dismissals: [oordeel('nl.naam', c)]),
        ),
      );
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoSidecars(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      expect(terug.deck.dismissals, isNotNull);
      expect(terug.dismissalsUnreadable, isFalse);
    });
  });

  group('MIAUW-dispositie', () {
    // #756, de laatste achterblijvende laag: een waiver of bevestiging is een
    // reviewbesluit over het rapport en reist dus mee. Zelfde machinerie als
    // de andere sidecars; hier de MIAUW-eigen randen: grafstenen zijn inhoud
    // (een ingetrokken waiver mag niet herrijzen), en v1-bestanden blijven
    // leesbaar maar de app schrijft v2.
    const mPath = '$deckDir/deck.miauw.json';

    MiauwEntry item(String text) =>
        MiauwEntry(text: text, at: '2026-07-23T10:00:00.000Z');

    Future<RepoDeckFiles> build(
      Deck deck, {
      Map<String, Uint8List> inRepo = const {},
    }) async => buildDeckRepoFiles(
      deck,
      md: md,
      pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
      deckDir: deckDir,
      resolveBytes: resolverFrom({}),
      read: (path) async => inRepo[path],
    );

    Deck deckMet(MiauwDisposition m) => Deck(
      title: 'Pentest',
      slides: [Slide.create(SlideType.title).copyWith(title: 'Eén')],
      miauw: m,
    );

    test('krijgt een eigen bestand naast deck.md', () async {
      final out = await build(
        deckMet(MiauwDisposition(waivers: {'1.3': item('Niet in scope')})),
      );

      expect(out.upserts.containsKey(mPath), isTrue);
      final inhoud = utf8.decode(out.upserts[mPath]!);
      expect(inhoud, contains('1.3'));
      expect(inhoud, contains('Niet in scope'));
    });

    test('komt er bij het openen weer aan', () async {
      final out = await build(
        deckMet(
          MiauwDisposition(
            waivers: {'1.3': item('Niet in scope')},
            confirmations: {'2.1': item('Intake gehouden')},
          ),
        ),
      );
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoMiauw(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      expect(terug.deck.miauwWaivers['1.3'], 'Niet in scope');
      expect(terug.deck.miauwConfirmations['2.1'], 'Intake gehouden');
      expect(terug.onleesbaar, isFalse);
    });

    test('alleen grafstenen is nog steeds een bestand', () async {
      // "Waiver ingetrokken" ruimt de sidecar bewust niet op: zonder de
      // grafsteen keert de uitsluiting bij de eerstvolgende samenvoeging
      // terug van de andere kant, en dan is een eis weer weggewuifd zonder
      // dat iemand dat besloot.
      final out = await build(
        deckMet(
          const MiauwDisposition(
            revokedWaivers: {'1.6': '2026-07-23T11:00:00.000Z'},
          ),
        ),
      );

      expect(out.upserts.containsKey(mPath), isTrue);
      expect(utf8.decode(out.upserts[mPath]!), contains('revoked'));
    });

    test('zonder dispositie gaat een eigen bestand wél weg', () async {
      final bestaand = MiauwCodec.encodeDisposition(
        MiauwDisposition(waivers: {'1.3': item('x')}),
      )!;
      final out = await build(
        deckMet(const MiauwDisposition()),
        inRepo: {mPath: Uint8List.fromList(utf8.encode(bestaand))},
      );

      expect(out.deletes, contains(mPath));
    });

    test('maar niet wanneer het bestand niet van ons is', () async {
      final out = await build(
        deckMet(const MiauwDisposition()),
        inRepo: {mPath: Uint8List.fromList(utf8.encode('{"version":99}'))},
      );

      expect(out.deletes, isEmpty);
      expect(out.upserts.containsKey(mPath), isFalse);
    });

    test('de werkkopie voor de wachtrij draagt hem ook', () {
      // Wat hier ontbreekt wordt bij het legen van de wachtrij op de tak
      // verwijderd — dezelfde valkuil als bij de notities en de ink.
      final files = mirrorDeckFiles(
        deckMet(MiauwDisposition(waivers: {'1.3': item('x')})),
        deckDir: deckDir,
        md: md,
      );

      expect(files.keys, contains(mPath));
    });

    test('withRepoSidecars hangt ook deze laag aan', () async {
      final out = await build(
        deckMet(MiauwDisposition(waivers: {'1.3': item('Niet in scope')})),
      );
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoSidecars(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      expect(terug.deck.miauwWaivers['1.3'], 'Niet in scope');
      expect(terug.miauwUnreadable, isFalse);
    });

    test('een v1-bestand in de repo blijft leesbaar', () async {
      const v1 = '{"version":1,"waivers":{"1.3":"Oude reden"}}';
      final parsed = Deck(
        title: 'Pentest',
        slides: [Slide.create(SlideType.title).copyWith(title: 'Eén')],
      );
      final terug = await withRepoMiauw(
        parsed,
        deckDir: deckDir,
        read: (path) async =>
            path == mPath ? Uint8List.fromList(utf8.encode(v1)) : null,
      );

      expect(terug.deck.miauwWaivers['1.3'], 'Oude reden');
      expect(terug.onleesbaar, isFalse);
    });
  });

  group('zegel', () {
    // #541, het sluitstuk: de weigering (D13) is ingetrokken — git is een
    // bestandssysteem, geen enforcer — en het zegel reist als sidecar mee.
    // Zelfde machinerie als de andere lagen; de zegel-eigen rand: de hash gaat
    // over de bytes van de oorspronkelijke `.md` en is tegen de repo-kopie
    // niet na te rekenen, dus het zegel is hier metadata die terug moet komen,
    // geen controle die hier moet slagen.
    const sPath = '$deckDir/deck.seal.json';

    Future<RepoDeckFiles> build(
      Deck deck, {
      Map<String, Uint8List> inRepo = const {},
    }) async => buildDeckRepoFiles(
      deck,
      md: md,
      pool: poolFor(FakeRepo(branches: {'main': 'c0'}, files: {})),
      deckDir: deckDir,
      resolveBytes: resolverFrom({}),
      read: (path) async => inRepo[path],
    );

    Deck verzegeld() => Deck(
      title: 'Rapport',
      slides: [Slide.create(SlideType.title).copyWith(title: 'Eén')],
      finalized: true,
      sealAlgo: 'sha-512',
      sealHash: 'a' * 128,
      sealAt: '2026-07-10T12:00:00.000Z',
      signature: const DocumentSignature(name: 'B. de Winter'),
    );

    test('krijgt een eigen bestand naast deck.md', () async {
      final out = await build(verzegeld());

      expect(out.upserts.containsKey(sPath), isTrue);
      final inhoud = utf8.decode(out.upserts[sPath]!);
      expect(inhoud, contains('a' * 128));
      expect(inhoud, contains('B. de Winter'));
    });

    test('komt er bij het openen weer aan', () async {
      // Zonder dit leest een verzegeld rapport dat uit de repo terugkomt als
      // een rapport dat nooit verzegeld is.
      final out = await build(verzegeld());
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoSeal(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      expect(terug.deck.finalized, isTrue);
      expect(terug.deck.sealHash, 'a' * 128);
      expect(terug.deck.signature?.name, 'B. de Winter');
      expect(terug.onleesbaar, isFalse);
    });

    test('zonder zegel gaat een eigen bestand wél weg', () async {
      const bestaand = '{"version":1,"finalized":true}';
      final out = await build(
        Deck(
          title: 'Rapport',
          slides: [Slide.create(SlideType.title).copyWith(title: 'Eén')],
        ),
        inRepo: {sPath: Uint8List.fromList(utf8.encode(bestaand))},
      );

      expect(out.deletes, contains(sPath));
    });

    test('maar niet wanneer het bestand niet van ons is', () async {
      final out = await build(
        Deck(
          title: 'Rapport',
          slides: [Slide.create(SlideType.title).copyWith(title: 'Eén')],
        ),
        inRepo: {sPath: Uint8List.fromList(utf8.encode('{"version":99}'))},
      );

      expect(out.deletes, isEmpty);
      expect(out.upserts.containsKey(sPath), isFalse);
    });

    test('de werkkopie voor de wachtrij draagt hem ook', () {
      // Wat hier ontbreekt wordt bij het legen van de wachtrij op de tak
      // verwijderd — dezelfde valkuil als bij de notities en de ink.
      final files = mirrorDeckFiles(verzegeld(), deckDir: deckDir, md: md);

      expect(files.keys, contains(sPath));
    });

    test('withRepoSidecars hangt ook deze laag aan', () async {
      final out = await build(verzegeld());
      final parsed = md.parseDeck(
        utf8.decode(out.upserts['$deckDir/deck.md']!),
      )!;
      final terug = await withRepoSidecars(
        parsed,
        deckDir: deckDir,
        read: (path) async => out.upserts[path],
      );

      expect(terug.deck.finalized, isTrue);
      expect(terug.sealUnreadable, isFalse);
    });
  });
}
