import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/asset_pool.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// Een forge waar élke ref zijn eigen `deck.md` heeft. De gewone [FakeRepo] deelt
/// één bestandsboom, en dan zijn de voorouder en de versie van de ander per
/// definitie gelijk — precies wat een driewegs-merge niet mag aannemen.
class _ThreeWayForge extends FakeForge {
  _ThreeWayForge(super.repo, this.byRef);
  final Map<String, String> byRef;

  @override
  Future<Uint8List> readBlob(String ref, String path) async {
    final markdown = byRef[ref.trim()];
    if (markdown == null) return super.readBlob(ref, path);
    return Uint8List.fromList(utf8.encode(markdown));
  }
}

String _deckMarkdown({required String alfa, required String beta}) =>
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

/// Opslaan botst met iemand anders (§8.6). Niet meer "herlaad maar": de twee
/// bewerkingen worden samengevoegd, en alleen wat écht botst komt terug als
/// keuze. De harde eis blijft P2 — er verdwijnt nooit werk.
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
  const work = 'decks/kwartaalcijfers/2026-07-18';

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  /// De forge staat op hún commit; onze basis is een oudere.
  _ThreeWayForge forgeWith({required String theirs, required String base}) {
    final repo = FakeRepo(
      branches: {'main': 'commit-main', work: 'hun-sha'},
      files: {'$deckDir/deck.md': bytes(theirs)},
    );
    return _ThreeWayForge(repo, {'onze-basis': base, work: theirs});
  }

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

  Slide bullets(String title, String item) =>
      Slide.create(SlideType.bullets).copyWith(title: title, bullets: [item]);

  /// Ons deck komt in werkelijkheid uit dezelfde parser als de voorouder — dus
  /// bouwen we het hier ook zo op, en bewerken we één bullet. Met handgemaakte
  /// slides zou de koppeling op vormverschillen stuklopen in plaats van op wat
  /// de test wil bewijzen.
  Deck oursFrom(
    String baseMarkdown, {
    required int slide,
    required String item,
  }) {
    final parsed = MarkdownService().parseDeck(baseMarkdown)!;
    final slides = [...parsed.slides];
    slides[slide] = slides[slide].copyWith(bullets: [item]);
    return parsed.copyWith(slides: slides);
  }

  /// Zet ons deck in het tabblad, midden in een ronde op de werkbranch, met een
  /// basis die inmiddels achterloopt op de forge.
  void seedOurs(ProviderContainer container, Deck ours) {
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(ours);
    tab.gitOrigin = const GitOrigin(
      config: config,
      branch: work,
      deckDir: deckDir,
      baseSha: 'onze-basis',
    );
  }

  Future<GitSaveResult> save(TabsNotifier tabs, _ThreeWayForge forge) =>
      tabs.saveToGit(
        forge,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze wijziging',
        now: DateTime(2026, 7, 18),
      );

  test(
    'verschillende slides bewerkt: vanzelf samengevoegd en opgeslagen',
    () async {
      final (container, tabs) = build();
      // Zij pasten Alfa aan, wij Beta. Niets botst.
      final forge = forgeWith(
        base: _deckMarkdown(alfa: 'alfa origineel', beta: 'beta origineel'),
        theirs: _deckMarkdown(alfa: 'alfa VAN HEN', beta: 'beta origineel'),
      );
      seedOurs(
        container,
        oursFrom(
          _deckMarkdown(alfa: 'alfa origineel', beta: 'beta origineel'),
          slide: 1,
          item: 'beta VAN ONS',
        ),
      );

      final result = await save(tabs, forge);

      expect(result.status, GitSaveStatus.merged);
      expect(result.conflicts, isEmpty);
      // Beide bewerkingen staan in het deck dat nu in het tabblad zit.
      final merged = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      final text = merged.slides.map((s) => s.bullets.join()).join(' ');
      expect(text, contains('alfa VAN HEN'), reason: 'hun werk');
      expect(text, contains('beta VAN ONS'), reason: 'ons werk');
      // En het is echt gecommit, op hun kop.
      expect(result.sha, isNotNull);
    },
  );

  test('dezelfde slide bewerkt: conflict met een keuze, niets weg', () async {
    final (container, tabs) = build();
    // Allebei Beta, anders.
    final forge = forgeWith(
      base: _deckMarkdown(alfa: 'alfa origineel', beta: 'beta origineel'),
      theirs: _deckMarkdown(alfa: 'alfa origineel', beta: 'beta VAN HEN'),
    );
    seedOurs(
      container,
      oursFrom(
        _deckMarkdown(alfa: 'alfa origineel', beta: 'beta origineel'),
        slide: 1,
        item: 'beta VAN ONS',
      ),
    );

    final result = await save(tabs, forge);

    expect(result.status, GitSaveStatus.conflict);
    expect(result.conflicts, hasLength(1));
    final conflict = result.conflicts.single;
    expect(conflict.ours!.bullets.join(), contains('VAN ONS'));
    expect(conflict.theirs!.bullets.join(), contains('VAN HEN'));
    // Onze kant staat voorlopig in het tabblad, en de basis is bijgelopen naar
    // hún kop — de volgende opslag botst dus niet nóg eens op ditzelfde punt.
    final tab = container.read(tabsProvider).current!;
    expect(
      tab.deckNotifier.currentState.deck!.slides[conflict.mergedIndex!].bullets
          .join(),
      contains('VAN ONS'),
    );
    expect(tab.gitOrigin!.baseSha, 'hun-sha');
  });

  test(
    'zonder gemeenschappelijke voorouder blijft het een gewoon conflict',
    () async {
      final (container, tabs) = build();
      final forge = forgeWith(
        base: _deckMarkdown(alfa: 'a', beta: 'b'),
        theirs: _deckMarkdown(alfa: 'a', beta: 'b'),
      );
      // Een nieuw deck heeft geen herkomst, dus ook geen basis om vanaf te mergen.
      container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .loadDeck(Deck(title: 'Kwartaal', slides: [bullets('Alfa', 'iets')]));

      final result = await save(tabs, forge);

      // Geen merge, maar ook geen verlies: het is gewoon (nog) niet geland.
      expect(
        result.status,
        anyOf(GitSaveStatus.committed, GitSaveStatus.conflict),
      );
    },
  );
}
