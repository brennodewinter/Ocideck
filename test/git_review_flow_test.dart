import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// "Uitbrengen ter review" (§9.4) opent een pull request van de werkbranch naar
/// de standaardbranch — maar alleen als de classificatiepoort groen geeft. Die
/// poort is fail-closed en kijkt naar de máx effective TLP van het hele deck,
/// niet alleen `deck.tlp`: één TLP:RED-slide in een TLP:none-deck hoort een
/// release tegen te houden. Deze suite legt dat vast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const config = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'librekat',
    repo: 'decks',
  );
  const deckDir = 'decks/kwartaalcijfers';
  const workBranch = 'decks/kwartaalcijfers/2026-07-18';

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  FakeRepo repo() => FakeRepo(
    branches: {'main': 'commit-main', workBranch: 'commit-work'},
    files: {
      '$deckDir/deck.md': bytes('---\nmarp: true\ntlp: green\n---\n# start'),
    },
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

  /// Zet een deck in het tabblad en plak er een werkbranch-herkomst op, zodat het
  /// tabblad "midden in een ronde" staat — de staat waarin uitbrengen mag.
  void seedOnWorkBranch(ProviderContainer container, Deck deck) {
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(deck);
    tab.gitOrigin = const GitOrigin(
      config: config,
      branch: workBranch,
      deckDir: deckDir,
      baseSha: 'commit-work',
    );
  }

  Deck deckWith({
    required TlpLevel deckTlp,
    List<TlpLevel> slideTlps = const [],
  }) => Deck(
    title: 'Kwartaal',
    tlp: deckTlp,
    slides: [
      for (final t in slideTlps)
        Slide.create(SlideType.bullets).copyWith(tlp: t),
    ],
  );

  group('openForReview classification gate (fail-closed)', () {
    test('opens a PR from the work branch when the gate is green', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));

      final result = await tabs.openForReview(
        forge,
        config: config,
        settings: const AppSettings(maxReleaseExportTlpKey: 'amber'),
        title: 'Concept kwartaalcijfers',
        body: 'graag review',
      );

      expect(result.status, ReviewStatus.opened);
      expect(result.pr, isNotNull);
      // De PR loopt van de werkbranch naar de standaardbranch.
      final pr = forge.repo.pulls.single;
      expect(pr.head, workBranch);
      expect(pr.base, 'main');
    });

    test('a deck over the ceiling is blocked, and no PR is opened', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.red));

      final result = await tabs.openForReview(
        forge,
        config: config,
        settings: const AppSettings(maxReleaseExportTlpKey: 'amber'),
        title: 't',
        body: 'b',
      );

      expect(result.status, ReviewStatus.blocked);
      expect(result.classificationDecision, isNotNull);
      expect(forge.repo.pulls, isEmpty); // fail-closed: niets naar de forge
    });

    test(
      'a single RED slide in a none-deck is caught (max effective TLP)',
      () async {
        // Dit is het venijn: de export-gate kijkt naar deck.tlp (none → altijd
        // toegestaan). De release-gate moet de RED-slide vangen.
        final (container, tabs) = build();
        final forge = FakeForge(repo());
        seedOnWorkBranch(
          container,
          deckWith(
            deckTlp: TlpLevel.none,
            slideTlps: const [TlpLevel.none, TlpLevel.red],
          ),
        );

        final result = await tabs.openForReview(
          forge,
          config: config,
          settings: const AppSettings(maxReleaseExportTlpKey: 'amber'),
          title: 't',
          body: 'b',
        );

        expect(result.status, ReviewStatus.blocked);
        expect(forge.repo.pulls, isEmpty);
      },
    );

    test('no gate configured: any deck may be released', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.red));

      final result = await tabs.openForReview(
        forge,
        config: config,
        settings: const AppSettings(), // geen plafond
        title: 't',
        body: 'b',
      );

      expect(result.status, ReviewStatus.opened);
    });
  });

  group('openForReview guards', () {
    test(
      'a tab still on the default branch has no concept to release',
      () async {
        final (container, tabs) = build();
        final forge = FakeForge(repo());
        final tab = container.read(tabsProvider).current!;
        tab.deckNotifier.loadDeck(deckWith(deckTlp: TlpLevel.green));
        tab.gitOrigin = const GitOrigin(
          config: config,
          branch: 'main', // niet op een werkbranch
          deckDir: deckDir,
          baseSha: 'commit-main',
        );

        final result = await tabs.openForReview(
          forge,
          config: config,
          settings: const AppSettings(),
          title: 't',
          body: 'b',
        );

        expect(result.status, ReviewStatus.notOnWorkBranch);
        expect(forge.repo.pulls, isEmpty);
      },
    );
  });

  group('mergeConcept', () {
    test(
      'merges the work branch PR onto main, prunes, re-bases the tab',
      () async {
        final (container, tabs) = build();
        final forge = FakeForge(repo());
        seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));
        // A review PR is open for the work branch.
        await forge.openPullRequest(
          head: workBranch,
          base: 'main',
          title: 'Review',
        );

        final result = await tabs.mergeConcept(
          forge,
          config: config,
          settings: const AppSettings(),
        );

        expect(result.status, MergeStatus.merged);
        // main now points at the work branch's commit; the branch is pruned.
        expect(forge.repo.branches['main'], 'commit-work');
        expect(forge.repo.branches.containsKey(workBranch), isFalse);
        // The tab re-bases onto main: a next save starts a fresh round.
        final origin = container.read(tabsProvider).current!.gitOrigin!;
        expect(origin.branch, 'main');
        expect(origin.baseSha, 'commit-work');
      },
    );

    test('no open PR for the branch is reported, not merged', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));

      final result = await tabs.mergeConcept(
        forge,
        config: config,
        settings: const AppSettings(),
      );

      expect(result.status, MergeStatus.noPullRequest);
      expect(forge.repo.branches['main'], 'commit-main'); // untouched
    });

    test('a tab on the default branch has nothing to merge', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      final tab = container.read(tabsProvider).current!;
      tab.deckNotifier.loadDeck(deckWith(deckTlp: TlpLevel.green));
      tab.gitOrigin = const GitOrigin(
        config: config,
        branch: 'main',
        deckDir: deckDir,
        baseSha: 'commit-main',
      );

      final result = await tabs.mergeConcept(
        forge,
        config: config,
        settings: const AppSettings(),
      );
      expect(result.status, MergeStatus.notOnWorkBranch);
    });

    test('rechecks the branch deck before merging', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));
      forge.repo.files['$deckDir/deck.md'] = bytes(
        '---\nmarp: true\ntheme: ocideck\ntlp: red\ntitle: Verhoogd\n---\n'
        '# Verhoogd',
      );
      await forge.openPullRequest(
        head: workBranch,
        base: 'main',
        title: 'Review',
      );

      final result = await tabs.mergeConcept(
        forge,
        config: config,
        settings: const AppSettings(maxReleaseExportTlpKey: 'amber'),
      );

      expect(result.status, MergeStatus.blocked);
      expect(forge.repo.branches['main'], 'commit-main');
    });

    test('refuses a branch that changes during the merge request', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));
      await forge.openPullRequest(
        head: workBranch,
        base: 'main',
        title: 'Review',
      );
      forge.beforeMerge = () => forge.repo.branches[workBranch] = 'commit-race';

      final result = await tabs.mergeConcept(
        forge,
        config: config,
        settings: const AppSettings(),
      );

      expect(result.status, MergeStatus.failed);
      expect(forge.repo.branches['main'], 'commit-main');
    });

    test('refuses a review aimed at another target branch', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));
      await forge.openPullRequest(
        head: workBranch,
        base: 'staging',
        title: 'Review',
      );

      final result = await tabs.mergeConcept(
        forge,
        config: config,
        settings: const AppSettings(),
      );

      expect(result.status, MergeStatus.failed);
      expect(forge.repo.branches['main'], 'commit-main');
    });

    test('refuses a review retargeted during the final merge check', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));
      await forge.openPullRequest(
        head: workBranch,
        base: 'main',
        title: 'Review',
      );
      forge.beforeSecondPullRequestLookup = () {
        forge.repo.pulls.single.base = 'staging';
      };

      final result = await tabs.mergeConcept(
        forge,
        config: config,
        settings: const AppSettings(),
      );

      expect(result.status, MergeStatus.failed);
      expect(forge.repo.branches['main'], 'commit-main');
    });

    test('refuses a review retargeted while the provider merges', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));
      await forge.openPullRequest(
        head: workBranch,
        base: 'main',
        title: 'Review',
      );
      forge.beforeMerge = () {
        forge.repo.pulls.single.base = 'staging';
      };

      final result = await tabs.mergeConcept(
        forge,
        config: config,
        settings: const AppSettings(),
      );

      expect(result.status, MergeStatus.failed);
      expect(forge.repo.branches['main'], 'commit-main');
      expect(forge.repo.branches['staging'], isNull);
    });
  });

  group('tagRelease (gated)', () {
    test('tags main with decks/<naam>/vX when the gate is green', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));

      final result = await tabs.tagRelease(
        forge,
        config: config,
        settings: const AppSettings(maxReleaseExportTlpKey: 'amber'),
        version: 'v1.0',
        message: 'eerste release',
      );

      expect(result.status, ReleaseStatus.tagged);
      expect(result.tag!.name, 'decks/kwartaalcijfers/v1.0');
      // The tag sits on the main head.
      expect(forge.repo.tags['decks/kwartaalcijfers/v1.0'], 'commit-main');
    });

    test('a deck over the ceiling is blocked, and no tag is created', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repo());
      seedOnWorkBranch(
        container,
        deckWith(
          deckTlp: TlpLevel.none,
          slideTlps: const [TlpLevel.red], // caught by max effective TLP
        ),
      );

      final result = await tabs.tagRelease(
        forge,
        config: config,
        settings: const AppSettings(maxReleaseExportTlpKey: 'amber'),
        version: 'v1.0',
        message: 'm',
      );

      expect(result.status, ReleaseStatus.blocked);
      expect(forge.repo.tags, isEmpty);
    });

    test(
      'an invalid version is refused before the gate or the forge',
      () async {
        final (container, tabs) = build();
        final forge = FakeForge(repo());
        seedOnWorkBranch(container, deckWith(deckTlp: TlpLevel.green));

        final result = await tabs.tagRelease(
          forge,
          config: config,
          settings: const AppSettings(),
          version: '1.0', // no leading v
          message: 'm',
        );

        expect(result.status, ReleaseStatus.invalidVersion);
        expect(forge.repo.tags, isEmpty);
      },
    );
  });
}
