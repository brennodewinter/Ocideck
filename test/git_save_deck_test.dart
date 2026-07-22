import 'dart:async';
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
import 'package:ocideck/services/git/deck_mirror.dart';
import 'package:ocideck/services/git/draft_store.dart';
import 'package:ocideck/services/git/draft_store_web.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/outbox.dart';
import 'package:ocideck/services/git/sync_engine.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// Een werkkopie die het deck weigert, zoals de webwerkkopie doet bij een te
/// groot of niet-tekstueel deck ([DraftStoreUnsupported]).
class _RejectingMirror implements DeckMirror {
  const _RejectingMirror(this.reason);
  final String reason;

  @override
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files) async =>
      throw DraftStoreUnsupported(reason);

  @override
  Future<Map<String, Uint8List>> readDeck(String deckDir) async => {};
  @override
  Future<bool> hasDeck(String deckDir) async => false;
  @override
  Future<void> discardDeck(String deckDir) async {}
  @override
  Future<List<String>> deckDirs() async => const [];
  @override
  bool get hasRealHistory => false;
  @override
  bool get isDurable => true;
  @override
  bool get discardsLandedWork => true;
}

/// Een forge die je op scherp kunt zetten: online tot [online] op false gaat,
/// waarna een commit een netwerkfout gooit — het vliegtuig, tijdens het opslaan.
class _FlakyForge extends FakeForge {
  _FlakyForge(super.repo);
  bool online = true;

  @override
  Future<CommitResult> commitFiles({
    required String branch,
    required String message,
    required Map<String, Uint8List> upserts,
    required List<String> deletes,
    required String baseSha,
  }) {
    if (!online) {
      throw const GitForgeException(
        GitForgeError.network,
        'Netwerkfout: geen verbinding',
      );
    }
    return super.commitFiles(
      branch: branch,
      message: message,
      upserts: upserts,
      deletes: deletes,
      baseSha: baseSha,
    );
  }
}

/// Een forge die zijn commit ophoudt tot [gate] klaarstaat — het net dat traag
/// is, terwijl de gebruiker doorklikt naar een ander tabblad.
class _BlockingForge extends FakeForge {
  _BlockingForge(super.repo, this.gate);
  final Completer<void> gate;

  @override
  Future<CommitResult> commitFiles({
    required String branch,
    required String message,
    required Map<String, Uint8List> upserts,
    required List<String> deletes,
    required String baseSha,
  }) async {
    await gate.future;
    return super.commitFiles(
      branch: branch,
      message: message,
      upserts: upserts,
      deletes: deletes,
      baseSha: baseSha,
    );
  }
}

// Het git-opslaanpad (§9.1): het deck van het tabblad wordt één commit. Deze
// suite legt vast dat het commit landt, dat het tabblad daarna de nieuwe commit
// als baseSha draagt, dat een nieuw deck zonder herkomst ook publiceert, en dat
// een verplaatste branch wordt samengevoegd in plaats van stil te falen. Het
// botsen zelf — als de deckinhoud wél uiteenloopt — staat in
// git_merge_on_conflict_test.dart.
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

  /// Voeg een slide toe aan het deck dat nú in het tabblad staat, zodat de
  /// bewerking een echte afstammeling is van wat er geopend werd (gedeelde
  /// slide-ids) — precies zoals een gebruiker het zou doen.
  void addSlideTitled(ProviderContainer container, String title) {
    final notifier = container.read(tabsProvider).current!.deckNotifier;
    final deck = notifier.currentState.deck!;
    notifier.loadDeck(
      deck.copyWith(
        slides: [
          ...deck.slides,
          Slide.create(SlideType.title).copyWith(title: title),
        ],
      ),
    );
  }

  void seedDeck(ProviderContainer container, Deck deck) {
    container.read(tabsProvider).current!.deckNotifier.loadDeck(deck);
  }

  Deck deckWith(List<Slide> slides, {String title = 'Kwartaal'}) =>
      Deck(title: title, slides: slides);

  group('saveToGit', () {
    test('landt op een werkbranch, niet rechtstreeks op main (D3)', () async {
      final (container, tabs) = build();
      final repo = repoWith('# oud');
      final forge = FakeForge(repo);
      final when = DateTime(2026, 7, 18);
      const workBranch = 'decks/kwartaalcijfers/2026-07-18';

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

      final result = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'wijziging',
        now: when,
      );

      expect(result.status, GitSaveStatus.committed);
      expect(result.warnings, isEmpty);
      // Het werk landt op de gegenereerde werkbranch; main is niet aangeraakt.
      expect(repo.branches[workBranch], result.sha);
      expect(repo.branches['main'], 'commit-main');
      // Het tabblad volgt de werkbranch en draagt de nieuwe basis.
      final originAfter = container.read(tabsProvider).current!.gitOrigin!;
      expect(originAfter.branch, workBranch);
      expect(originAfter.baseSha, result.sha);
      // deck.md staat op de forge en is geldige markdown.
      expect(repo.files['$deckDir/deck.md'], isNotNull);
      expect(utf8.decode(repo.files['$deckDir/deck.md']!), contains('#'));
    });

    test('een tweede opslag blijft op dezelfde werkbranch', () async {
      final (container, tabs) = build();
      final repo = repoWith('''
---
marp: true
theme: ocideck
---

# Kwartaalcijfers
''');
      final forge = FakeForge(repo);
      const workBranch = 'decks/kwartaalcijfers/2026-07-18';
      await tabs.openDeckFromGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
      );

      final first = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'ronde 1a',
        now: DateTime(2026, 7, 18),
      );
      // Tweede opslag: het tabblad zit nu midden in de ronde. Ook al zeggen we
      // opnieuw 'main' (de fork-bron), hij blijft op de werkbranch — een andere
      // dag zou hem niet naar een nieuwe branch trekken.
      final second = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'ronde 1b',
        now: DateTime(2026, 7, 20),
      );

      expect(second.status, GitSaveStatus.committed);
      expect(
        container.read(tabsProvider).current!.gitOrigin!.branch,
        workBranch,
      );
      expect(repo.branches[workBranch], second.sha);
      expect(repo.branches[workBranch], isNot(first.sha));
      // Geen tweede werkbranch aangemaakt.
      expect(
        repo.branches.containsKey('decks/kwartaalcijfers/2026-07-20'),
        isFalse,
      );
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

    test(
      'een nieuw deck zonder herkomst start ook op een werkbranch',
      () async {
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
          now: DateTime(2026, 7, 18),
        );

        expect(result.status, GitSaveStatus.committed);
        expect(repo.files['decks/nieuwplan/deck.md'], isNotNull);
        // Ook een nieuw deck landt op een concept-branch, niet op main.
        expect(repo.branches['decks/nieuwplan/2026-07-18'], result.sha);
        expect(repo.branches['main'], 'commit-main');
        final origin = container.read(tabsProvider).current!.gitOrigin!;
        expect(origin.deckDir, 'decks/nieuwplan');
        expect(origin.branch, 'decks/nieuwplan/2026-07-18');
        expect(origin.baseSha, result.sha);
      },
    );

    test(
      'een verzette werkbranch wordt samengevoegd, niet teruggestuurd',
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
        const workBranch = 'decks/kwartaalcijfers/2026-07-18';
        await tabs.openDeckFromGit(
          forge,
          config: config,
          deckDir: deckDir,
          branch: 'main',
        );

        // Eerste opslag opent de ronde op de werkbranch.
        await tabs.saveToGit(
          forge,
          config: config,
          deckDir: deckDir,
          branch: 'main',
          message: 'ronde 1',
          now: DateTime(2026, 7, 18),
        );
        expect(
          container.read(tabsProvider).current!.gitOrigin!.branch,
          workBranch,
        );

        // Iemand anders verzet intussen de werkbranch (bv. een reviewer die
        // erop doorwerkt). De volgende opslag botst op de basis-sha.
        repo.branches[workBranch] = 'iemand-anders';

        final result = await tabs.saveToGit(
          forge,
          config: config,
          deckDir: deckDir,
          branch: 'main',
          message: 'botsing',
          now: DateTime(2026, 7, 18),
        );

        // Sinds §8.6 is een verzette branch geen doodlopende weg meer: er wordt
        // driewegs samengevoegd. Hier week de déckinhoud niet af (alleen de kop
        // verschoof), dus dat gaat vanzelf en het werk landt alsnog.
        expect(result.status, GitSaveStatus.merged);
        expect(result.conflicts, isEmpty);
        // En het landt óp hun commit, niet eroverheen: de branch is verzet naar
        // onze nieuwe commit, met die van de ander als basis.
        expect(repo.branches[workBranch], result.sha);
        expect(repo.branches[workBranch], isNot('iemand-anders'));
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

    test('offline belandt het werk in de wachtrij, niet in een fout', () async {
      final (container, tabs) = build();
      final repo = FakeRepo(
        branches: {'main': 'commit-main'},
        files: {'$deckDir/deck.md': bytes('# start')},
      );
      final forge = _FlakyForge(repo);
      final mirror = DraftMirror(store: PrefsDraftStore());
      final outbox = Outbox();

      seedDeck(
        container,
        deckWith([
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Werk', bullets: const ['offline gemaakt']),
        ]),
      );

      forge.online = false;
      final result = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'offline',
        mirror: mirror,
        outbox: outbox,
      );

      expect(result.status, GitSaveStatus.queued);
      // De tekst staat duurzaam in de werkkopie en het deck in de wachtrij.
      expect(await mirror.hasDeck(deckDir), isTrue);
      expect(await outbox.forDeck(deckDir), isNotNull);
      // De forge is niet aangeraakt: de branchkop staat er nog zoals hij stond.
      expect(repo.branches['main'], 'commit-main');
    });

    test(
      'een werkkopie die het deck weigert wordt een nette fout, geen crash',
      () async {
        // Web: een te groot of niet-tekstueel deck laat de werkkopie
        // DraftStoreUnsupported gooien. Dat is geen GitForgeException, dus zonder
        // vangst liep hij ongevangen door — geen melding, niets in de wachtrij.
        final (container, tabs) = build();
        final repo = FakeRepo(
          branches: {'main': 'commit-main'},
          files: {'$deckDir/deck.md': bytes('# start')},
        );
        final forge = _FlakyForge(repo);
        const reason = 'Deze presentatie is te groot voor de webversie.';
        const mirror = _RejectingMirror(reason);
        final outbox = Outbox();

        seedDeck(
          container,
          deckWith([
            Slide.create(SlideType.bullets).copyWith(title: 'Te groot'),
          ]),
        );

        forge.online = false;
        final result = await tabs.saveToGit(
          forge,
          config: config,
          deckDir: deckDir,
          branch: 'main',
          message: 'offline',
          mirror: mirror,
          outbox: outbox,
        );

        expect(result.status, GitSaveStatus.failed);
        expect(result.message, reason);
        // Niets in de wachtrij: de schrijf mislukte vóór het inrijen.
        expect(await outbox.forDeck(deckDir), isNull);
      },
    );

    test('bij verbinding loopt de wachtrij leeg en landt het werk', () async {
      final (container, tabs) = build();
      final repo = FakeRepo(
        branches: {'main': 'commit-main'},
        files: {'$deckDir/deck.md': bytes('# start')},
      );
      final forge = _FlakyForge(repo);
      final mirror = DraftMirror(store: PrefsDraftStore());
      final outbox = Outbox();

      seedDeck(
        container,
        deckWith([
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Werk', bullets: const ['offline gemaakt']),
        ]),
      );

      forge.online = false;
      await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'offline',
        mirror: mirror,
        outbox: outbox,
        now: DateTime(2026, 7, 18),
      );

      // Verbinding terug: de wachtrij loopt leeg.
      forge.online = true;
      final engine = SyncEngine(forge: forge, mirror: mirror, outbox: outbox);
      final outcomes = await tabs.flushGit(engine, config);

      expect(outcomes, hasLength(1));
      expect(outcomes.single.status, SyncStatus.committed);
      expect(await outbox.isEmpty, isTrue); // wachtrij leeg
      // Een ronde die offline begon: de flush maakt de werkbranch nu aan en de
      // commit landt daar — niet op main.
      const workBranch = 'decks/kwartaalcijfers/2026-07-18';
      expect(repo.branches[workBranch], outcomes.single.sha);
      expect(repo.branches['main'], 'commit-main');
    });

    test('een offline toegevoegde afbeelding wordt bij het synchroniseren '
        'alsnog gepoold', () async {
      final (container, tabs) = build();
      final repo = FakeRepo(branches: {'main': 'commit-main'}, files: {});
      final forge = _FlakyForge(repo);
      final mirror = DraftMirror(store: PrefsDraftStore());
      final outbox = Outbox();

      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 3, 1, 4, 1, 5]);
      final memPath = WebAssetStore.put(png, name: 'nieuw.png');
      final ref = GitRepoLayout.assetRef(
        sha256.convert(png).toString(),
        'png',
      )!;
      final poolPath = GitRepoLayout.assetPathOf(ref)!;

      seedDeck(
        container,
        deckWith([
          Slide.create(SlideType.bulletsImage).copyWith(
            title: 'Offline beeld',
            bullets: const ['x'],
            imagePath: memPath,
          ),
        ]),
      );

      // Offline opgeslagen: de blob kan nu niet omhoog.
      forge.online = false;
      final queued = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: 'decks/nieuwplan',
        branch: 'main',
        message: 'met offline beeld',
        mirror: mirror,
        outbox: outbox,
      );
      expect(queued.status, GitSaveStatus.queued);
      expect(repo.files[poolPath], isNull); // nog niets gepoold

      // Verbinding terug: de flush poolt de afbeelding alsnog en commit compleet.
      forge.online = true;
      final engine = SyncEngine(forge: forge, mirror: mirror, outbox: outbox);
      final outcomes = await tabs.flushGit(engine, config);

      expect(outcomes.single.status, SyncStatus.committed);
      // De blob staat nu in de pool en deck.md verwijst er met repo: naar.
      expect(repo.files[poolPath], png);
      expect(
        utf8.decode(repo.files['decks/nieuwplan/deck.md']!),
        contains(ref),
      );
    });

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

  group('tabwissel tijdens het opslaan', () {
    test('de commit landt bij het eigen tabblad, niet bij het nieuwe', () async {
      final (container, tabs) = build();
      final gate = Completer<void>();
      final repo = repoWith('# oud');
      final forge = _BlockingForge(repo, gate);
      final when = DateTime(2026, 7, 18);

      const validDeck = '''
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
      final owner = container.read(tabsProvider).current!;

      final saving = tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'opslag',
        now: when,
      );
      // De gebruiker klikt door naar een nieuw, leeg tabblad terwijl de commit
      // nog op de lijn staat.
      tabs.newEmptyTab();
      final other = container.read(tabsProvider).current!;
      expect(identical(owner, other), isFalse);

      gate.complete();
      final result = await saving;

      expect(result.status, GitSaveStatus.committed);
      expect(
        other.gitOrigin,
        isNull,
        reason: 'het lege tabblad mag geen herkomst erven van een ander deck',
      );
      expect(owner.gitOrigin?.deckDir, deckDir);
      expect(owner.gitOrigin?.baseSha, result.sha);
    });
  });

  group('een tweede ronde op dezelfde dag', () {
    test('overschrijft de kop van de werkbranch niet stilletjes', () async {
      final (container, tabs) = build();
      final repo = repoWith('# oud');
      final forge = FakeForge(repo);
      final when = DateTime(2026, 7, 18);
      const workBranch = 'decks/kwartaalcijfers/2026-07-18';

      const validDeck = '''
---
marp: true
theme: ocideck
---

# Kwartaalcijfers
''';
      repo.files['$deckDir/deck.md'] = bytes(validDeck);

      // Ochtend: openen vanaf main, bewerken, opslaan. De werkbranch ontstaat.
      await tabs.openDeckFromGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
      );
      addSlideTitled(container, 'Ochtend');
      final morning = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'ochtend',
        now: when,
      );
      expect(morning.status, GitSaveStatus.committed);
      expect(repo.branches[workBranch], isNotNull);

      // Middag: opnieuw vanaf main openen — het tabblad kent de ochtendcommit
      // niet. De werkbranch van vandaag bestaat al en staat verderop.
      await tabs.openDeckFromGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
      );
      addSlideTitled(container, 'Middag');
      final afternoon = await tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'middag',
        now: when,
      );

      // Zonder de guard was dit een schone fast-forward geweest en was de
      // ochtend van de kop verdwenen. Nu botst het en volgt de merge.
      expect(
        afternoon.status,
        isNot(GitSaveStatus.committed),
        reason: 'de ochtendcommit mag niet stil worden overschreven',
      );
      // ...en het is ook geen kale weigering. De gelezen basis maakt de
      // driewegs-merge mogelijk, dus beide kanten overleven: de ochtend blijft
      // op de branch staan en de middag komt erbij.
      expect(afternoon.status, GitSaveStatus.merged);
      // ...en het is ook geen kale weigering. De gelezen basis maakt de
      // driewegs-merge mogelijk, dus beide kanten overleven: wat de ochtend
      // toevoegde blijft staan en de middag komt erbij.
      expect(afternoon.status, GitSaveStatus.merged);
      final tip = utf8.decode(repo.files['$deckDir/deck.md']!);
      expect(tip, contains('Ochtend'));
      expect(tip, contains('Middag'));
    });
  });
}
