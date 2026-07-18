part of 'tabs_provider.dart';

/// Het native-git-pad (§8.2): openen, opslaan en synchroniseren via een échte
/// lokale clone, met echte historie. Apart bestand om de regelratchet te
/// respecteren; dezelfde library als [TabsNotifierGit], dus het deelt de
/// import-poort, de asset-resolutie en de GitOrigin.
///
/// Openen, opslaan én synchroniseren lopen hier bewust allemaal via de clone.
/// Zo draagt de tab de clone-HEAD als basis: een latere opslag commit dáárop, en
/// een verzette branch wordt bij het pushen betrapt — geen stille overschrijving
/// van andermans werk (P2).
extension TabsNotifierGitNative on TabsNotifier {
  /// Open een deck uit de lokale clone. De afbeeldingen komen — net als op het
  /// REST-pad — uit de gedeelde pool via [forge]; de tekst en de basis-sha uit
  /// de clone.
  Future<OpenResult> openDeckFromGitNative(
    NativeGitMirror mirror,
    GitForge forge, {
    required GitRepoConfig config,
    required String deckDir,
    required String branch,
  }) async {
    final deckName = GitRepoLayout.deckNameOf(deckDir);
    if (deckName == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Pad is geen deckmap volgens de repo-layout',
      );
    }

    await mirror.prepareForOpen();
    final baseSha = await mirror.headSha();
    final files = await mirror.readDeck(deckDir);
    final bytes = files['$deckDir/${TabsNotifierGit.deckFileName}'];
    if (bytes == null) return OpenResult.notAPresentation;
    if (bytes.length > FileService.maxDeckMarkdownBytes) {
      return OpenResult.unreadable;
    }

    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException catch (e) {
      logWarning('openDeckFromGitNative: deck.md is geen geldige UTF-8', e);
      return OpenResult.unreadable;
    }

    final label = '${config.slug} · $deckName';
    final gated = _gateAndParseContent(raw, sourceName: label);
    final parsed = gated.deck;
    if (parsed == null) return gated.failure;
    if (!mounted) return OpenResult.unreadable;

    final deck = await _withRepoAssets(
      parsed,
      AssetPool(forge: forge, branch: branch),
      sourceName: label,
    );
    if (!mounted) return OpenResult.unreadable;

    _placeDeckInTab(deck, remoteOrigin: label);
    currentState.current?.gitOrigin = GitOrigin(
      config: config,
      branch: branch,
      deckDir: deckDir,
      baseSha: baseSha ?? '',
    );
    refreshTabs();
    return OpenResult.opened;
  }

  /// Sla het deck van het huidige tabblad op als een echte commit in de clone,
  /// en push die best-effort. De commit is altijd duurzaam (P2): geen verbinding
  /// betekent lokaal bewaard, niet verloren.
  Future<GitSaveResult> saveToGitNative(
    NativeGitMirror mirror, {
    required GitRepoConfig config,
    required String deckDir,
    required String branch,
    required String message,
    DateTime? now,
  }) async {
    final deckName = GitRepoLayout.deckNameOf(deckDir);
    if (deckName == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Pad is geen deckmap volgens de repo-layout',
      );
    }
    final deck = currentState.current?.deckNotifier.currentState.deck;
    if (deck == null) {
      return const GitSaveResult(status: GitSaveStatus.failed);
    }

    // D3: dezelfde werkbranch-logica als het REST-pad. Al midden in een ronde op
    // een werkbranch? Blijf daar; anders start (of hervat) de ronde van vandaag
    // op `decks/<naam>/<datum>`. De clone checkt hem uit en commit erop.
    final origin = currentState.current?.gitOrigin;
    final String workBranch;
    if (origin != null &&
        origin.matchesRepo(config) &&
        origin.deckDir == deckDir &&
        origin.branch != branch) {
      workBranch = origin.branch;
    } else {
      final generated = GitRepoLayout.workBranch(deckName, now ?? DateTime.now());
      if (generated == null) {
        throw const GitForgeException(
          GitForgeError.malformed,
          'Kon geen geldige werkbranch-naam maken',
        );
      }
      workBranch = generated;
    }

    final image = ImageService();
    final files = await buildDeckRepoFiles(
      deck,
      md: _md,
      pool: null, // native: git ontdubbelt zelf, dus alle blobs mee
      deckDir: deckDir,
      resolveBytes: (path) async => WebAssetStore.isMemPath(path)
          ? WebAssetStore.bytesFor(path)
          : image.readSlideImageBytes(path, projectPath: deck.projectPath),
    );

    final result = await mirror.commitDeck(
      deckDir,
      files.upserts,
      message,
      workBranch: workBranch,
      forkFrom: branch,
    );
    // De lokale HEAD is de nieuwe basis waarop de volgende opslag voortbouwt.
    if (result.sha != null) {
      currentState.current?.gitOrigin = GitOrigin(
        config: config,
        branch: workBranch,
        deckDir: deckDir,
        baseSha: result.sha!,
      );
      refreshTabs();
    }
    return _mapCommitOutcome(result, files.warnings);
  }

  /// Duw wat nog lokaal wacht alsnog naar de forge.
  Future<GitSaveResult> syncGitNative(NativeGitMirror mirror) async =>
      _mapCommitOutcome(await mirror.sync(), const []);

  GitSaveResult _mapCommitOutcome(
    GitCommitResult result,
    List<String> warnings,
  ) {
    switch (result.outcome) {
      case GitCommitOutcome.pushed:
      case GitCommitOutcome.unchanged:
        return GitSaveResult(
          status: GitSaveStatus.committed,
          sha: result.sha,
          warnings: warnings,
        );
      case GitCommitOutcome.committedOffline:
        return GitSaveResult(status: GitSaveStatus.queued, warnings: warnings);
      case GitCommitOutcome.committedConflict:
        return GitSaveResult(
          status: GitSaveStatus.conflict,
          message: 'De branch is verzet; je commit staat lokaal klaar.',
          warnings: warnings,
        );
    }
  }
}
