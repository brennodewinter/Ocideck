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
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// A real PNG signature plus filler — `ImageService.looksLikeImage` sniffs the
/// leading bytes, so anything the app must accept has to start like this.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  ...List<int>.filled(24, 0x00),
]);

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));
String _ref(Uint8List bytes, [String ext = 'png']) =>
    GitRepoLayout.assetRef(sha256.convert(bytes).toString(), ext)!;

/// The git open path must fetch pooled images and rewrite the slide paths, or a
/// deck from a repo opens with every picture broken (§9.2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssetPool.clearCache();
    WebAssetStore.clear();
    WebAssetStore.overrideTotalBudgetForTest(null);
  });
  tearDown(() {
    AssetPool.clearCache();
    WebAssetStore.clear();
    WebAssetStore.overrideTotalBudgetForTest(null);
  });

  const config = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'librekat',
    repo: 'decks',
  );

  /// Markdown met écht geparste image-slides. Met de hand getypte `![](…)`
  /// belandt niet in `Slide.imagePath` — alleen een image-slide draagt die —
  /// dus laten we de serialiser het schrijven.
  String deckMarkdown(List<String> references) =>
      MarkdownService().generateDeck(
        Deck(
          title: 'Kwartaalcijfers',
          slides: [
            for (var i = 0; i < references.length; i++)
              Slide(
                id: 's$i',
                type: SlideType.image,
                title: 'Slide $i',
                imagePath: references[i],
              ),
          ],
        ),
      );

  FakeRepo repoWith({
    required String markdown,
    Map<String, Uint8List> assets = const {},
  }) => FakeRepo(
    branches: {'main': 'commit-main'},
    files: {
      'decks/kwartaalcijfers/deck.md': _b(markdown),
      for (final e in assets.entries) e.key: e.value,
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

  Future<OpenResult> open(TabsNotifier tabs, FakeRepo repo) =>
      tabs.openDeckFromGit(
        FakeForge(repo),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
      );

  test('a pooled image is fetched and the slide points at its bytes', () async {
    final (container, tabs) = build();
    final ref = _ref(_png);

    final result = await open(
      tabs,
      repoWith(
        markdown: deckMarkdown([ref]),
        assets: {GitRepoLayout.assetPathOf(ref)!: _png},
      ),
    );

    expect(result, OpenResult.opened);
    final slide = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .currentState
        .deck!
        .slides
        .first;

    // The path is rewritten off repo: onto the in-memory store…
    expect(WebAssetStore.isMemPath(slide.imagePath), isTrue);
    // …and the bytes behind it are the ones from the pool.
    expect(WebAssetStore.bytesFor(slide.imagePath), _png);
  });

  test('two slides sharing one asset fetch it once', () async {
    // The dedup goal (P4) as the user meets it: one blob, one download, however
    // many slides point at it.
    final (container, tabs) = build();
    final ref = _ref(_png);
    final markdown = deckMarkdown([ref, ref]);

    await open(
      tabs,
      repoWith(
        markdown: markdown,
        assets: {GitRepoLayout.assetPathOf(ref)!: _png},
      ),
    );

    final slides = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .currentState
        .deck!
        .slides;
    final mems = slides.map((s) => s.imagePath).where(WebAssetStore.isMemPath);
    expect(mems.length, 2);
    expect(mems.toSet().length, 1, reason: 'one asset, one mem: path');
  });

  test('budget failure rolls back git assets and records its cause', () async {
    final otherPng = Uint8List.fromList([..._png]..last = 0x01);
    final firstRef = _ref(_png);
    final secondRef = _ref(otherPng);
    final (container, tabs) = build();
    WebAssetStore.overrideTotalBudgetForTest(_png.length);

    final result = await open(
      tabs,
      repoWith(
        markdown: deckMarkdown([firstRef, secondRef]),
        assets: {
          GitRepoLayout.assetPathOf(firstRef)!: _png,
          GitRepoLayout.assetPathOf(secondRef)!: otherPng,
        },
      ),
    );

    expect(result, OpenResult.unreadable);
    expect(
      container.read(openFailureProvider),
      OpenFailure.memoryBudgetExceeded,
    );
    expect(WebAssetStore.isEmpty, isTrue, reason: 'git-open is atomic');
    expect(WebAssetStore.totalBytes, 0);
  });

  test(
    'a missing asset leaves a placeholder, it does not sink the deck',
    () async {
      final (container, tabs) = build();
      // The reference is in the markdown, but the blob is not in the repo.
      final result = await open(
        tabs,
        repoWith(markdown: deckMarkdown([_ref(_png)])),
      );

      expect(result, OpenResult.opened);
      final slide = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!
          .slides
          .first;
      // Untouched, so the render layer draws its normal placeholder.
      expect(GitRepoLayout.isRepoAsset(slide.imagePath), isTrue);
    },
  );

  test('a blob that is not an image is refused, not rendered', () async {
    // A forge is untrusted (P5): a .png name proves nothing. The bytes must be
    // hashed to their name *and* sniffed as an image.
    final notAnImage = _b(r'<?php system($_GET["c"]); ?>');
    final ref = _ref(notAnImage);
    final (container, tabs) = build();

    final result = await open(
      tabs,
      repoWith(
        markdown: deckMarkdown([ref]),
        assets: {GitRepoLayout.assetPathOf(ref)!: notAnImage},
      ),
    );

    expect(result, OpenResult.opened);
    final slide = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .currentState
        .deck!
        .slides
        .first;
    expect(WebAssetStore.isMemPath(slide.imagePath), isFalse);
    expect(WebAssetStore.bytesFor(slide.imagePath), isNull);
  });

  test('an asset whose bytes betray its hash never reaches the deck', () async {
    // Cross-repo cache poisoning, seen from the top: the pool refuses it, and
    // the open path treats that as a broken link rather than a fatal error.
    final ref = _ref(_png);
    final (container, tabs) = build();

    final result = await open(
      tabs,
      repoWith(
        markdown: deckMarkdown([ref]),
        assets: {GitRepoLayout.assetPathOf(ref)!: _b('heel iets anders')},
      ),
    );

    expect(result, OpenResult.opened);
    final slide = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .currentState
        .deck!
        .slides
        .first;
    expect(WebAssetStore.isMemPath(slide.imagePath), isFalse);
  });

  test('a deck without pooled images opens unchanged', () async {
    final (container, tabs) = build();
    final result = await open(
      tabs,
      repoWith(markdown: deckMarkdown(['images/lokaal.png'])),
    );

    expect(result, OpenResult.opened);
    expect(
      container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!
          .slides
          .first
          .imagePath,
      'images/lokaal.png',
    );
  });
}
