@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/git_cli_io.dart';
import 'package:ocideck/services/git/native_git_mirror_api.dart';
import 'package:ocideck/services/git/native_git_mirror_io.dart';
import 'package:ocideck/services/annotation_codec.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/miauw_codec.dart';
import 'package:ocideck/services/user_notes_codec.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

// Samenvoegen op het native pad (§8.6), tegen een échte bare origin op schijf.
// De push wordt geweigerd omdat iemand anders de werkbranch verzette; daarna
// hoort er samengevoegd te worden in plaats van de commit lokaal te laten
// stranden. Wat de merge zelf beslist ligt vast in git_deck_merge_test.dart —
// hier gaat het om de git-kant: fetch, merge-base, merge-commit, push.

Future<void> _rawGit(List<String> args, String cwd) async {
  final r = await Process.run(
    'git',
    [
      '-c',
      'user.name=Test',
      '-c',
      'user.email=t@example.org',
      '-c',
      'commit.gpgsign=false',
      ...args,
    ],
    workingDirectory: cwd,
    environment: {
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
    },
  );
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')} → ${r.stderr}');
}

String _deck({required String alfa, required String beta}) =>
    '''
---
marp: true
theme: ocideck
---

## Alfa

- $alfa

---

## Beta

- $beta
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const deckDir = 'decks/kwartaalcijfers';
  const work = 'decks/kwartaalcijfers/2026-07-18';

  late Directory temp;
  late String bare;
  late GitRepoConfig config;
  late NativeGitMirror mirror;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('ngm_merge');
    Directory('${temp.path}/x').createSync(recursive: true);
    bare = '${temp.path}/x/origin.git';
    await _rawGit(['init', '--bare', '--initial-branch=main', bare], temp.path);

    // Seed: main met het deck, plus een werkbranch met dezelfde inhoud — dat is
    // de gemeenschappelijke voorouder van beide kanten.
    final seed = '${temp.path}/seed';
    await _rawGit(['clone', bare, seed], temp.path);
    File('$seed/$deckDir/deck.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        _deck(alfa: 'alfa origineel', beta: 'beta origineel'),
      );
    await _rawGit(['add', '-A'], seed);
    await _rawGit(['commit', '-m', 'init'], seed);
    await _rawGit(['push', 'origin', 'main'], seed);
    await _rawGit(['branch', work], seed);
    await _rawGit(['push', 'origin', work], seed);

    config = GitRepoConfig(
      baseUrl: 'file://${temp.path}',
      owner: 'x',
      repo: 'origin',
    );
    mirror = (await createNativeGitMirror(
      git: NativeGitCli(),
      config: config,
      token: '',
      baseDir: '${temp.path}/clone',
    ))!;
  });
  tearDown(() => temp.deleteSync(recursive: true));

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

  /// Iemand anders pusht een eigen wijziging naar de werkbranch.
  Future<void> theyPush(
    String markdown, {
    String? notesJson,
    String? inkJson,
    String? miauwJson,
  }) async {
    final other = '${temp.path}/other${DateTime(2026).microsecond}';
    await _rawGit(['clone', '--branch', work, bare, other], temp.path);
    File('$other/$deckDir/deck.md').writeAsStringSync(markdown);
    if (notesJson != null) {
      File('$other/$deckDir/deck.user-notes.json').writeAsStringSync(notesJson);
    }
    if (inkJson != null) {
      File('$other/$deckDir/deck.ink.json').writeAsStringSync(inkJson);
    }
    if (miauwJson != null) {
      File('$other/$deckDir/deck.miauw.json').writeAsStringSync(miauwJson);
    }
    await _rawGit(['add', '-A'], other);
    await _rawGit(['commit', '-m', 'hun wijziging'], other);
    await _rawGit(['push', 'origin', work], other);
  }

  /// Open het deck uit de clone en zet ons tabblad op de werkbranch, zodat een
  /// opslag daar landt (en dus botst met wat de ander pushte).
  Future<void> openOnWorkBranch(
    ProviderContainer container,
    TabsNotifier tabs,
  ) async {
    await tabs.openDeckFromGitNative(
      mirror,
      FakeForge(FakeRepo(branches: {}, files: {})),
      config: config,
      deckDir: deckDir,
      branch: 'main',
    );
    final tab = container.read(tabsProvider).current!;
    tab.gitOrigin = GitOrigin(
      config: config,
      branch: work,
      deckDir: deckDir,
      baseSha: tab.gitOrigin!.baseSha,
    );
  }

  /// Een notitiebestand zoals OciDeck het schrijft: verankerd op de
  /// vingerafdruk van een dia, niet op haar id.
  String notesFor({required int index, required String text}) => jsonEncode({
    'version': UserNotesCodec.version,
    'slides': [
      {
        'index': index,
        'fp': AnnotationCodec.fingerprint(
          MarkdownService()
              .parseDeck(_deck(alfa: 'alfa origineel', beta: 'beta origineel'))!
              .slides[index],
        ),
        'text': text,
      },
    ],
  });

  /// Bewerk één bullet van het geopende deck.
  void editBeta(ProviderContainer container, String item) {
    final tab = container.read(tabsProvider).current!;
    final deck = tab.deckNotifier.currentState.deck!;
    final slides = [...deck.slides];
    slides[1] = slides[1].copyWith(bullets: [item]);
    tab.deckNotifier.loadDeck(deck.copyWith(slides: slides));
  }

  test('andere slide bewerkt: samengevoegd en gepusht', () async {
    final (container, tabs) = build();
    await openOnWorkBranch(container, tabs);

    // Zij pasten Alfa aan; wij Beta. Niets botst.
    await theyPush(_deck(alfa: 'alfa VAN HEN', beta: 'beta origineel'));
    editBeta(container, 'beta VAN ONS');

    final result = await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'onze wijziging',
      now: DateTime(2026, 7, 18),
    );

    expect(result.status, GitSaveStatus.merged);
    expect(result.conflicts, isEmpty);

    // Op de origin staat nu één werkbranch met beide bewerkingen erin.
    final verify = '${temp.path}/verify';
    await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
    final landed = File('$verify/$deckDir/deck.md').readAsStringSync();
    expect(landed, contains('alfa VAN HEN'), reason: 'hun werk');
    expect(landed, contains('beta VAN ONS'), reason: 'ons werk');

    // En het is een échte merge-commit: twee ouders, dus de historie van de
    // ander is niet weggegooid maar samengevoegd.
    final parents = await Process.run('git', [
      'rev-list',
      '--parents',
      '-n',
      '1',
      'HEAD',
    ], workingDirectory: verify);
    expect(
      (parents.stdout as String).trim().split(' ').length,
      3,
      reason: 'commit + twee ouders',
    );
  });

  test(
    'dezelfde slide bewerkt: conflict, lokaal gehouden, niets gepusht',
    () async {
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      // Allebei Beta, anders.
      await theyPush(_deck(alfa: 'alfa origineel', beta: 'beta VAN HEN'));
      editBeta(container, 'beta VAN ONS');

      final result = await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze wijziging',
        now: DateTime(2026, 7, 18),
      );

      expect(result.status, GitSaveStatus.conflict);
      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.ours!.bullets.join(), contains('VAN ONS'));
      expect(conflict.theirs!.bullets.join(), contains('VAN HEN'));

      // Niet gepubliceerd: op de origin staat nog steeds hún versie.
      final verify = '${temp.path}/verify2';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final onOrigin = File('$verify/$deckDir/deck.md').readAsStringSync();
      expect(onOrigin, contains('beta VAN HEN'));
      expect(onOrigin, isNot(contains('beta VAN ONS')));

      // Maar hun werk is wél al binnengehaald: het samengevoegde deck staat in het
      // tabblad met onze kant voorop, en de volgende opslag botst niet opnieuw.
      final deck = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      expect(
        deck.slides[conflict.mergedIndex!].bullets.join(),
        contains('VAN ONS'),
      );
    },
  );

  test('na het kiezen landt de opslag alsnog', () async {
    final (container, tabs) = build();
    await openOnWorkBranch(container, tabs);
    await theyPush(_deck(alfa: 'alfa origineel', beta: 'beta VAN HEN'));
    editBeta(container, 'beta VAN ONS');

    // Eerste poging botst.
    final first = await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'onze wijziging',
      now: DateTime(2026, 7, 18),
    );
    expect(first.status, GitSaveStatus.conflict);

    // De gebruiker kiest (hier: hun kant) en slaat opnieuw op.
    final conflict = first.conflicts.single;
    final tab = container.read(tabsProvider).current!;
    final deck = tab.deckNotifier.currentState.deck!;
    final slides = [...deck.slides];
    slides[conflict.mergedIndex!] = conflict.theirs!;
    tab.deckNotifier.loadDeck(deck.copyWith(slides: slides));

    final second = await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'keuze gemaakt',
      now: DateTime(2026, 7, 18),
    );

    // De branch bevat hun werk inmiddels, dus dit landt gewoon.
    expect(
      second.status,
      anyOf(GitSaveStatus.committed, GitSaveStatus.merged),
      reason: 'geen tweede botsing op hetzelfde punt',
    );
    final verify = '${temp.path}/verify3';
    await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
    expect(
      File('$verify/$deckDir/deck.md').readAsStringSync(),
      contains('beta VAN HEN'),
    );
  });

  // De notities staan in een eigen bestand naast deck.md. Het native pad kreeg
  // van `mergeRemote` alleen de deck.md-bytes van de drie kanten, dus alle drie
  // de decks leken notitieloos — en omdat de deckmap wordt vervángen door wat de
  // resolver teruggeeft, verdween het bestand uit de merge-commit. Op precies
  // het pad dat de app kiest zodra git geïnstalleerd is, en bij het gewoonste
  // scenario dat er is.
  group('notities overleven de native merge', () {
    test('van beide kanten, op verschillende dia\'s', () async {
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      // Zij: notitie bij Alfa, gepusht. Wij: notitie bij Beta, in de editor.
      await theyPush(
        _deck(alfa: 'alfa origineel', beta: 'beta origineel'),
        notesJson: notesFor(index: 0, text: 'van hen bij alfa'),
      );
      final tab = container.read(tabsProvider).current!;
      final deck = tab.deckNotifier.currentState.deck!;
      tab.deckNotifier.loadDeck(
        deck.copyWith(userNotes: {deck.slides[1].id: 'van ons bij beta'}),
      );

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze notitie',
        now: DateTime(2026, 7, 18),
      );

      final verify = '${temp.path}/verify-notities';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final notes = File('$verify/$deckDir/deck.user-notes.json');
      expect(
        notes.existsSync(),
        isTrue,
        reason: 'het bestand mag niet uit de merge-commit verdwijnen',
      );
      final inhoud = notes.readAsStringSync();
      expect(inhoud, contains('van ons bij beta'), reason: 'ons werk');
      expect(inhoud, contains('van hen bij alfa'), reason: 'hun werk');
    });

    test('ook als alleen de ander er een had', () async {
      // Wij typten geen notitie, alleen tekst. Zonder het hydrateren van hún
      // kant zou onze opslag hun notitie wegpoetsen zonder dat er ooit een
      // conflict was — de stilste vorm van verlies die er is.
      //
      // Zij laten Alfa met rust: een notitie hangt aan de dia zoals die was,
      // dus wie zijn eigen dia herschrijft laat zijn eigen notitie los. Dat is
      // de codecregel en niet iets wat deze merge repareert; zie GIT_STORAGE
      // §9.7.
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      await theyPush(
        _deck(alfa: 'alfa origineel', beta: 'beta origineel'),
        notesJson: notesFor(index: 0, text: 'alleen van hen'),
      );
      editBeta(container, 'beta VAN ONS');

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze wijziging',
        now: DateTime(2026, 7, 18),
      );

      final verify = '${temp.path}/verify-notities2';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final notes = File('$verify/$deckDir/deck.user-notes.json');
      expect(notes.existsSync(), isTrue);
      expect(notes.readAsStringSync(), contains('alleen van hen'));
    });
  });

  group('de tekeningen overleven de native merge', () {
    // D7 eind-tot-eind, tegen échte git: de driver-override houdt de
    // tekst-merge van `deck.ink.json` af, en de resolver schrijft er de
    // unie-met-grafstenen overheen. Wat de unie zelf beslist ligt vast in
    // git_deck_merge_test.dart; hier gaat het om wat er werkelijk landt.

    Deck seedDeck() => MarkdownService().parseDeck(
      _deck(alfa: 'alfa origineel', beta: 'beta origineel'),
    )!;

    InkStroke stroke(String id, {bool erased = false}) => InkStroke(
      tool: InkTool.pen,
      color: 0xFFEF4444,
      width: 0.004,
      points: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
      id: id,
      erased: erased,
    );

    /// Een inkbestand zoals OciDeck het schrijft, verankerd op de
    /// vingerafdrukken van het seed-deck.
    String inkJson(Map<int, List<InkStroke>> byIndex) {
      final d = seedDeck();
      return AnnotationCodec.encode(d.slides, {
        for (final e in byIndex.entries) d.slides[e.key].id: e.value,
      })!;
    }

    /// Zet [json] als ink-sidecar op main én op de werkbranch, vóór de app
    /// kloont — zo kennen de voorouder en beide kanten de streek.
    Future<void> seedInk(String json) async {
      final s = '${temp.path}/seed-ink';
      await _rawGit(['clone', bare, s], temp.path);
      for (final branch in ['main', work]) {
        await _rawGit(['checkout', branch], s);
        File('$s/$deckDir/deck.ink.json').writeAsStringSync(json);
        await _rawGit(['add', '-A'], s);
        await _rawGit(['commit', '-m', 'ink op $branch'], s);
        await _rawGit(['push', 'origin', branch], s);
      }
    }

    test('van beide kanten, op verschillende dia\'s: de unie landt', () async {
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      // Zij: een streek bij Alfa, gepusht. Wij: een streek bij Beta.
      await theyPush(
        _deck(alfa: 'alfa origineel', beta: 'beta origineel'),
        inkJson: inkJson({
          0: [stroke('van-hen')],
        }),
      );
      final tab = container.read(tabsProvider).current!;
      final deck = tab.deckNotifier.currentState.deck!;
      tab.deckNotifier.loadDeck(
        deck.copyWith(
          annotations: {
            deck.slides[1].id: [stroke('van-ons')],
          },
        ),
      );

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze streek',
        now: DateTime(2026, 7, 18),
      );

      final verify = '${temp.path}/verify-ink';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final ink = File('$verify/$deckDir/deck.ink.json');
      expect(ink.existsSync(), isTrue);
      final inhoud = ink.readAsStringSync();
      expect(inhoud, contains('van-ons'), reason: 'ons werk');
      expect(inhoud, contains('van-hen'), reason: 'hun werk');
      expect(inhoud, isNot(contains('<<<<<<<')));
    });

    test('wij gumden, zij niet: de grafsteen wint en landt', () async {
      // Dít is waarom pure vereniging fout was. De voorouder en beide kanten
      // kennen s1; wij markeren hem gewist, de ander raakt alleen de tekst
      // van Alfa aan. Zonder grafsteen bracht de unie de streek terug terwijl
      // de gebruiker hem zág verdwijnen.
      await seedInk(
        inkJson({
          1: [stroke('s1')],
        }),
      );
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      await theyPush(_deck(alfa: 'alfa VAN HEN', beta: 'beta origineel'));

      final tab = container.read(tabsProvider).current!;
      final deck = tab.deckNotifier.currentState.deck!;
      final betaId = deck.slides[1].id;
      final s1 = deck.annotations[betaId]!.single;
      expect(s1.id, 's1', reason: 'de streek moet uit de kloon geladen zijn');
      tab.deckNotifier.loadDeck(
        deck.copyWith(
          annotations: {
            betaId: [s1.copyWith(erased: true)],
          },
        ),
      );

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'gewist',
        now: DateTime(2026, 7, 18),
      );

      final verify = '${temp.path}/verify-ink2';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final inhoud = File('$verify/$deckDir/deck.ink.json').readAsStringSync();
      expect(inhoud, contains('"s1"'));
      expect(
        inhoud,
        contains('"erased": true'),
        reason:
            'de grafsteen moet de merge overleven, anders komt de streek '
            'bij de volgende unie terug',
      );
      expect(inhoud, isNot(contains('<<<<<<<')));
    });
  });

  test('de merge laat een geldig deck achter, geen conflictmarkers', () async {
    final (container, tabs) = build();
    await openOnWorkBranch(container, tabs);
    await theyPush(_deck(alfa: 'alfa VAN HEN', beta: 'beta origineel'));
    editBeta(container, 'beta VAN ONS');

    await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'onze wijziging',
      now: DateTime(2026, 7, 18),
    );

    final verify = '${temp.path}/verify4';
    await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
    final landed = File('$verify/$deckDir/deck.md').readAsStringSync();
    // Dít is waarom de merge per slide gaat en niet per regel: git zou hier
    // markers achterlaten en dan parseert het deck niet meer.
    expect(landed, isNot(contains('<<<<<<<')));
    expect(landed, isNot(contains('>>>>>>>')));
    expect(MarkdownService().parseDeck(landed), isNotNull);
  });


  // #756: de MIAUW-dispositie is de laatste laag die naar git meereist, en
  // haar merge heeft één geval dat pure vereniging stukmaakt: een intrekking.
  // Hier het bewijs tegen echte git dat de grafsteen de samenvoeging overleeft
  // terwijl het nieuwe besluit van de ander gewoon meekomt.
  group('de MIAUW-dispositie overleeft het native pad', () {
    String dispositie(MiauwDisposition d) =>
        MiauwCodec.encodeDisposition(d, forTextMerge: true)!;

    Future<void> seedMiauw() async {
      final her = '${temp.path}/herseed-miauw';
      await _rawGit(['clone', bare, her], temp.path);
      File('$her/$deckDir/deck.miauw.json').writeAsStringSync(
        dispositie(
          const MiauwDisposition(
            waivers: {
              '1.3': MiauwEntry(
                text: 'Niet in scope',
                at: '2026-07-20T10:00:00.000Z',
              ),
            },
          ),
        ),
      );
      await _rawGit(['add', '-A'], her);
      await _rawGit(['commit', '-m', 'dispositie erbij'], her);
      await _rawGit(['push', 'origin', 'main'], her);
      await _rawGit(['push', 'origin', 'HEAD:$work'], her);
    }

    test('een intrekking overleeft, hun nieuwe besluit komt mee', () async {
      await seedMiauw();
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      // Zij trekken niets in maar nemen een éigen besluit erbij.
      await theyPush(
        _deck(alfa: 'alfa VAN HEN', beta: 'beta origineel'),
        miauwJson: dispositie(
          const MiauwDisposition(
            waivers: {
              '1.3': MiauwEntry(
                text: 'Niet in scope',
                at: '2026-07-20T10:00:00.000Z',
              ),
              '2.2': MiauwEntry(
                text: 'Door klant bevestigd buiten dit rapport',
                at: '2026-07-21T09:00:00.000Z',
              ),
            },
          ),
        ),
      );

      // Wij trekken de waiver op 1.3 in — het besluit dat zonder grafsteen
      // door hun kant heen zou worden teruggedraaid.
      final tab = container.read(tabsProvider).current!;
      expect(
        tab.deckNotifier.currentState.deck!.miauwWaivers.containsKey('1.3'),
        isTrue,
        reason: 'het openen hoort de dispositie uit de repo mee te nemen',
      );
      tab.deckNotifier.removeMiauwWaiver('1.3');

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'waiver 1.3 ingetrokken',
        now: DateTime(2026, 7, 23),
      );

      final verify = '${temp.path}/verify-miauw';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final geland = MiauwCodec.decode(
        File('$verify/$deckDir/deck.miauw.json').readAsStringSync(),
      );
      expect(
        geland.waiverTexts.containsKey('1.3'),
        isFalse,
        reason: 'de ingetrokken waiver mag niet herrijzen',
      );
      expect(geland.revokedWaivers.containsKey('1.3'), isTrue);
      expect(
        geland.waiverTexts['2.2'],
        'Door klant bevestigd buiten dit rapport',
        reason: 'het besluit van de andere reviewer reist gewoon mee',
      );
    });
  });

  // Een deckmap is meer dan `deck.md`: de cijfers van een gekoppelde grafiek
  // staan in `data/*.json` ernaast, en de notities in `deck.user-notes.json`.
  // Het native pad las die bestanden bij het openen niet in, dus stond er een
  // deck in de editor dat ze niet kende — en omdat elke schrijfweg de deckmap
  // *vervangt* door wat hij zelf samenstelde, ruimde de eerstvolgende opslag ze
  // op. Zonder botsing, zonder melding, en zonder dat het deck er kapot uitzag:
  // de verwijzing bleef staan, alleen de cijfers waren weg. Issue #670.
  group('de lagen naast deck.md overleven het native pad', () {
    const dataPath = 'data/omzet.json';
    const cijfers = ChartSpec(
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: '2025', data: [10, 14]),
      ],
    );

    /// Hetzelfde deck als [_deck], plus een grafiekdia die haar cijfers uit
    /// [dataPath] haalt in plaats van ze inline te dragen — de vorm waarin een
    /// deck in de repo staat.
    String deckMetGrafiek({required String alfa, required String beta}) {
      final md = MarkdownService();
      final basis = md.parseDeck(_deck(alfa: alfa, beta: beta))!;
      return md.generateDeck(
        basis.copyWith(
          slides: [
            ...basis.slides,
            Slide.create(SlideType.chart).copyWith(
              title: 'Omzet',
              customMarkdown: const ChartSpec(
                type: ChartType.line,
                title: 'Omzet',
                source: dataPath,
                x: ['Q1', 'Q2'],
                series: [
                  ChartSeries(name: '2025', data: [10, 14]),
                ],
              ).toBlock(forStorage: true),
            ),
          ],
        ),
      );
    }

    /// Zet de deckmap in de origin op een deck mét grafiekdata en een notitie,
    /// op main én op de werkbranch — zodat wat de app straks opent precies is
    /// wat een echte repo draagt.
    Future<void> seedLagen() async {
      final her = '${temp.path}/herseed';
      await _rawGit(['clone', bare, her], temp.path);
      File('$her/$deckDir/deck.md').writeAsStringSync(
        deckMetGrafiek(alfa: 'alfa origineel', beta: 'beta origineel'),
      );
      File('$her/$deckDir/$dataPath')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(cijfers.dataToJson());
      File(
        '$her/$deckDir/deck.user-notes.json',
      ).writeAsStringSync(notesFor(index: 0, text: 'onze eerdere notitie'));
      await _rawGit(['add', '-A'], her);
      await _rawGit(['commit', '-m', 'grafiekdata erbij'], her);
      await _rawGit(['push', 'origin', 'main'], her);
      await _rawGit(['push', 'origin', 'HEAD:$work'], her);
    }

    /// De cijfers zoals ze na afloop in de origin staan.
    Future<String> geland(String naam) async {
      final verify = '${temp.path}/$naam';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final file = File('$verify/$deckDir/$dataPath');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'het databestand mag niet uit de deckmap verdwijnen',
      );
      return file.readAsStringSync();
    }

    test('een gewone opslag laat de grafiekdata staan', () async {
      // Geen botsing, geen merge — de kortste weg die er is, en precies daar
      // ging het mis: openen hydrateerde niet, dus de opslag stelde een deckmap
      // samen waar het databestand niet in zat.
      await seedLagen();
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);
      editBeta(container, 'beta VAN ONS');

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze wijziging',
        now: DateTime(2026, 7, 18),
      );

      expect(await geland('verify-data1'), contains('14'));

      // Dezelfde weg, dezelfde oorzaak: de notitie die er lag stond niet in het
      // deck dat we opsloegen, dus verdween ze. De bestaande tests hierboven
      // dekken alleen de merge — en die hydrateerde wél.
      final verify = '${temp.path}/verify-data1';
      expect(
        File('$verify/$deckDir/deck.user-notes.json').readAsStringSync(),
        contains('onze eerdere notitie'),
      );
    });

    test('een samengevoegde opslag laat de grafiekdata staan', () async {
      await seedLagen();
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      await theyPush(
        deckMetGrafiek(alfa: 'alfa VAN HEN', beta: 'beta origineel'),
      );
      editBeta(container, 'beta VAN ONS');

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze wijziging',
        now: DateTime(2026, 7, 18),
      );

      expect(await geland('verify-data2'), contains('14'));
    });

    test('een geweigerde kant kost je de rest van de deckmap niet', () async {
      // De ander pusht iets dat de importpoort niet doorlaat. Dan blijft ónze
      // kant staan — en "onze kant" is de hele deckmap, niet alleen `deck.md`.
      // Twee straffen voor één gebeurtenis is er één te veel.
      //
      // Hier wordt niets gepusht (`clean: false` houdt de merge lokaal), dus de
      // origin bewijst hier niets. Wat telt is de clone: dát is de werkkopie
      // waar de editor uit leest en waar de volgende geslaagde push vandaan
      // komt.
      await seedLagen();
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      await theyPush('dit is geen deck');
      editBeta(container, 'beta VAN ONS');

      await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze wijziging',
        now: DateTime(2026, 7, 18),
      );

      final inDeClone = await mirror.readDeck(deckDir);
      final data = inDeClone['$deckDir/$dataPath'];
      expect(
        data,
        isNotNull,
        reason: 'het databestand mag niet uit de werkkopie verdwijnen',
      );
      expect(utf8.decode(data!), contains('14'));
    });
  });
}
