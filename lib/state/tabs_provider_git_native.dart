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

    /// De verbinding waar dit deck bij hoort. Reist mee de [GitOrigin] in, zodat
    /// een volgende opslag terug kan naar dezelfde opdrachtgever zonder opnieuw
    /// te vragen. Leeg is toegestaan: dan valt de app terug op het vergelijken
    /// van de configuratie.
    String connectionId = '',
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
    // Een deckmap is meer dan `deck.md`: de cijfers van een gekoppelde grafiek
    // en de notities staan in eigen bestanden ernaast. Zonder ze hier terug te
    // hangen opent er een deck dat ze niet kent — en omdat elke schrijfweg de
    // deckmap vervángt door wat de app samenstelt, ruimt de eerstvolgende
    // opslag ze op. Geen botsing, geen melding, en het deck ziet er heel uit:
    // de verwijzing staat er nog, alleen de cijfers zijn weg (#670).
    //
    // `readDeck` gaf ze hierboven al mee, dus dit kost geen tweede leesronde.
    final sidecars = await withRepoSidecars(
      deck,
      deckDir: deckDir,
      read: (path) async => files[path],
    );
    if (!mounted) return OpenResult.unreadable;
    if (sidecars.missingChartData.isNotEmpty) {
      _ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
        sidecars.missingChartData,
      );
    }

    _placeDeckInTab(sidecars.deck, remoteOrigin: label);
    currentState.current?.gitOrigin = GitOrigin(
      config: config,
      branch: branch,
      deckDir: deckDir,
      baseSha: baseSha ?? '',
      connectionId: connectionId,
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

    /// De verbinding waar dit deck bij hoort. Reist mee de [GitOrigin] in, zodat
    /// een volgende opslag terug kan naar dezelfde opdrachtgever zonder opnieuw
    /// te vragen. Leeg is toegestaan: dan valt de app terug op het vergelijken
    /// van de configuratie.
    String connectionId = '',
    DateTime? now,
  }) async {
    final deckName = GitRepoLayout.deckNameOf(deckDir);
    if (deckName == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Pad is geen deckmap volgens de repo-layout',
      );
    }
    // Tabblad vastzetten vóór het eerste wachtpunt — zie [saveToGit] in
    // tabs_provider_git.dart: een tabwissel tijdens commit/push mag het
    // resultaat niet bij een ander deck laten landen.
    final tab = currentState.current;
    final deck = tab?.deckNotifier.currentState.deck;
    if (deck == null) {
      return const GitSaveResult(status: GitSaveStatus.failed);
    }

    // D3: dezelfde werkbranch-logica als het REST-pad. Al midden in een ronde op
    // een werkbranch? Blijf daar; anders start (of hervat) de ronde van vandaag
    // op `decks/<naam>/<datum>`. De clone checkt hem uit en commit erop.
    final origin = tab?.gitOrigin;
    final String workBranch;
    if (origin != null &&
        origin.matchesRepo(config) &&
        origin.deckDir == deckDir &&
        origin.branch != branch) {
      workBranch = origin.branch;
    } else {
      final generated = GitRepoLayout.workBranch(
        deckName,
        now ?? DateTime.now(),
      );
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

    // De push is geweigerd: iemand anders verzette de branch. De commit staat
    // lokaal (dus niets is weg), maar we laten het daar niet bij — samenvoegen
    // (§8.6), net als op het REST-pad.
    if (result.outcome == GitCommitOutcome.committedConflict) {
      final merged = await _mergeNative(
        mirror,
        tab: tab,
        config: config,
        deckDir: deckDir,
        branch: workBranch,
        message: message,
        warnings: files.warnings,
      );
      if (merged != null) return merged;
    }

    // De lokale HEAD is de nieuwe basis waarop de volgende opslag voortbouwt.
    if (result.sha != null) {
      tab?.gitOrigin = GitOrigin(
        config: config,
        branch: workBranch,
        deckDir: deckDir,
        baseSha: result.sha!,
        connectionId: connectionId,
      );
      refreshTabs();
    }
    return _mapCommitOutcome(result, files.warnings);
  }

  /// Voeg samen wat de ander op deze branch deed met wat wij lokaal committen
  /// (§8.6). Geeft null wanneer er niets te mergen viel en de gewone afhandeling
  /// het overneemt.
  ///
  /// De git-kant zit in [NativeGitMirror.mergeRemote]; hier zit alleen het deck:
  /// de drie versies door dezelfde fail-closed importpoort (P5 — de branch van
  /// een ander is niet vertrouwder dan welke andere invoer ook), dan
  /// [mergeDeckVersions], en het resultaat terug als bestandenset.
  Future<GitSaveResult?> _mergeNative(
    NativeGitMirror mirror, {

    /// Het tabblad waar dit deck in staat, vastgezet vóór het eerste wachtpunt.
    required TabInfo? tab,
    required GitRepoConfig config,
    required String deckDir,
    required String branch,
    required String message,
    required List<String> warnings,
  }) async {
    final deckFile = '$deckDir/${TabsNotifierGit.deckFileName}';
    final label = '${config.slug} · $deckDir';
    Deck? mergedDeck;
    var conflicts = const <SlideConflict>[];

    Deck? gated(Uint8List? bytes) {
      if (bytes == null) return null;
      try {
        return _gateAndParseContent(utf8.decode(bytes), sourceName: label).deck;
      } on FormatException {
        return null;
      }
    }

    final outcome = await mirror.mergeRemote(
      branch: branch,
      deckDir: deckDir,
      deckFile: deckFile,
      message: message,
      resolve: (baseBytes, ourBytes, theirBytes, read) async {
        final image = ImageService();
        final outcome = await resolveRepoDeckMerge(
          deckDir: deckDir,
          deckFile: deckFile,
          baseBytes: baseBytes,
          ourBytes: ourBytes,
          theirBytes: theirBytes,
          read: read,
          gate: gated,
          md: _md,
          resolveBytes: (path) async => WebAssetStore.isMemPath(path)
              ? WebAssetStore.bytesFor(path)
              : image.readSlideImageBytes(
                  path,
                  projectPath: tab?.deckNotifier.currentState.deck?.projectPath,
                ),
        );
        mergedDeck = outcome.merge?.merged;
        conflicts = outcome.merge?.conflicts ?? const [];
        if (outcome.missingChartData.isNotEmpty) {
          _ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
            outcome.missingChartData,
          );
        }
        return (
          files: outcome.files,
          deletes: outcome.deletes,
          clean: outcome.clean,
        );
      },
    );

    // Niets samengevoegd (offline, of geen voorouder): de gewone afhandeling
    // hierboven neemt het over — de commit staat dan nog steeds lokaal.
    if (mergedDeck == null) return null;
    if (!mounted) return const GitSaveResult(status: GitSaveStatus.failed);

    // Het samengevoegde deck in het tabblad, met de nieuwe lokale kop als basis.
    tab?.deckNotifier.loadDeck(mergedDeck!);
    if (outcome.sha != null) {
      tab?.gitOrigin = GitOrigin(
        config: config,
        branch: branch,
        deckDir: deckDir,
        baseSha: outcome.sha!,
      );
    }
    refreshTabs();

    if (conflicts.isNotEmpty) {
      return GitSaveResult(
        status: GitSaveStatus.conflict,
        conflicts: conflicts,
        warnings: warnings,
      );
    }
    return GitSaveResult(
      status: outcome.outcome == GitCommitOutcome.pushed
          ? GitSaveStatus.merged
          : GitSaveStatus.queued,
      sha: outcome.sha,
      warnings: warnings,
    );
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
