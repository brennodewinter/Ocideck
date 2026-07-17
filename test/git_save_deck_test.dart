import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/asset_pool.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

// Het git-opslaanpad (§9.1): het deck van het tabblad wordt één commit. Deze
// suite legt vast dat het commit landt, dat het tabblad daarna de nieuwe commit
// als baseSha draagt, dat een nieuw deck zonder herkomst ook publiceert, en dat
// een verplaatste branch als conflict terugkomt in plaats van stil te falen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssetPool.clearCache();
    WebAssetStore.clear();
  });

  const config = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'librekat',
    repo: 'decks',
  );
  const deckDir = 'decks/kwartaalcijfers';

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  FakeRepo repoWith(String deckMarkdown) => FakeRepo(
    branches: {'main': 'commit-main'},
    files: {'$deckDir/deck.md': bytes(deckMarkdown)},
  );

  (ProviderContainer, TabsNotifier) build() {
    final container = ProviderContainer(
      overrides: [
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, container.read(tabsProvider.notifier));
  }

  void seedDeck(ProviderContainer container, Deck deck) {
    container.read(tabsProvider).current!.deckNotifier.loadDeck(deck);
  }

  Deck deckWith(List<Slide> slides, {String title = 'Kwartaal'}) =>
      Deck(title: title, slides: slides);

  group('saveToGit', () {
    test('schrijft het deck terug en landt als één commit', () async {
      final (container, tabs) = build();
      final repo = repoWith('# oud');
      final forge = FakeForge(repo);

      // Open eerst, zodat het tabblad een herkomst + baseSha draagt.
      final validDeck = '''
---
marp: true
theme: ocideck
---

# Kwartaalcijfers
''';
      repo.files['$deckDir/deck.md'] = bytes(validDeck);
      await tabs.openDeckFromGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
      );
      final baseBefore = container
          .read(tabsProvider)
          .current!
          .gitOrigin!
          .baseSha;

      final result = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'wijziging',
      );

      expect(result.status, GitSaveStatus.committed);
      expect(result.warnings, isEmpty);
      // De branchkop is verzet en het tabblad draagt de nieuwe basis.
      final originAfter = container.read(tabsProvider).current!.gitOrigin!;
      expect(originAfter.baseSha, result.sha);
      expect(originAfter.baseSha, isNot(baseBefore));
      expect(repo.branches['main'], result.sha);
      // deck.md staat op de forge en is geldige markdown.
      expect(repo.files['$deckDir/deck.md'], isNotNull);
      expect(utf8.decode(repo.files['$deckDir/deck.md']!), contains('#'));
    });

    test('poolt een mem:-afbeelding en verwijst ernaar in deck.md', () async {
      final (container, tabs) = build();
      final repo = repoWith('# start');
      final forge = FakeForge(repo);

      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
      final memPath = WebAssetStore.put(png, name: 'grafiek.png');
      final ref = GitRepoLayout.assetRef(
        sha256.convert(png).toString(),
        'png',
      )!;
      final poolPath = GitRepoLayout.assetPathOf(ref)!;

      seedDeck(
        container,
        deckWith([
          Slide.create(
            SlideType.bulletsImage,
          ).copyWith(title: 'Beeld', bullets: const ['x'], imagePath: memPath),
        ]),
      );

      final result = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'met beeld',
      );

      expect(result.status, GitSaveStatus.committed);
      expect(repo.files[poolPath], png); // blob gepoold
      expect(utf8.decode(repo.files['$deckDir/deck.md']!), contains(ref));
    });

    test('publiceert een nieuw deck zonder herkomst op de branchkop', () async {
      final (container, tabs) = build();
      // Repo zonder dit deck; alleen een branch.
      final repo = FakeRepo(branches: {'main': 'commit-main'}, files: {});
      final forge = FakeForge(repo);

      seedDeck(
        container,
        deckWith([
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Nieuw', bullets: const ['punt']),
        ]),
      );

      final result = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: 'decks/nieuwplan',
        branch: 'main',
        message: 'eerste versie',
      );

      expect(result.status, GitSaveStatus.committed);
      expect(repo.files['decks/nieuwplan/deck.md'], isNotNull);
      final origin = container.read(tabsProvider).current!.gitOrigin!;
      expect(origin.deckDir, 'decks/nieuwplan');
      expect(origin.baseSha, result.sha);
    });

    test(
      'een verzette branch komt terug als conflict, niet als fout',
      () async {
        final (container, tabs) = build();
        final repo = repoWith('''
---
marp: true
theme: ocideck
---

# Kwartaalcijfers
''');
        final forge = FakeForge(repo);
        await tabs.openDeckFromGit(
          forge,
          config: config,
          deckDir: deckDir,
          branch: 'main',
        );

        // Iemand anders committeert intussen: de branchkop verschuift.
        repo.branches['main'] = 'iemand-anders';

        final result = await tabs.saveToGit(
          forge,
          config: config,
          deckDir: deckDir,
          branch: 'main',
          message: 'botsing',
        );

        expect(result.status, GitSaveStatus.conflict);
        expect(result.message, isNotNull);
        // De commit van de ander staat er nog; wij hebben niets overschreven.
        expect(repo.branches['main'], 'iemand-anders');
      },
    );

    test(
      'opslaan en heropenen levert dezelfde slide met dezelfde afbeelding',
      () async {
        final (container, tabs) = build();
        final repo = FakeRepo(branches: {'main': 'commit-main'}, files: {});
        final forge = FakeForge(repo);

        final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 9, 8, 7, 6]);
        final memPath = WebAssetStore.put(png, name: 'plaat.png');
        seedDeck(
          container,
          deckWith([
            Slide.create(SlideType.bulletsImage).copyWith(
              title: 'Titel hier',
              bullets: const ['een punt'],
              imagePath: memPath,
            ),
          ], title: 'Rondrit'),
        );

        final saved = await tabs.saveToGit(
          forge,
          config: config,
          deckDir: 'decks/rondrit',
          branch: 'main',
          message: 'v1',
        );
        expect(saved.status, GitSaveStatus.committed);

        // Heropen vanaf de forge: het deck komt terug met een mem:-afbeelding die
        // exact dezelfde bytes draagt — de heenweg was omkeerbaar.
        final open = await tabs.openDeckFromGit(
          forge,
          config: config,
          deckDir: 'decks/rondrit',
          branch: 'main',
        );
        expect(open, OpenResult.opened);
        final deck = container
            .read(tabsProvider)
            .current!
            .deckNotifier
            .currentState
            .deck!;
        expect(deck.slides, hasLength(1));
        final reopened = deck.slides.single;
        expect(reopened.title, 'Titel hier');
        expect(WebAssetStore.isMemPath(reopened.imagePath), isTrue);
        expect(WebAssetStore.bytesFor(reopened.imagePath), png);
      },
    );

    test('een pad dat geen deckmap is wordt geweigerd', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repoWith('# x'));
      seedDeck(container, deckWith([Slide.create(SlideType.bullets)]));

      await expectLater(
        tabs.saveToGit(
          forge,
          config: config,
          deckDir: 'nietdecks/ergens',
          branch: 'main',
          message: 'm',
        ),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });
  });
}
