part of 'tabs_provider.dart';

/// Het open- én opslaan-pad van de git-opslag (§9.1–9.2). Apart bestand omdat
/// `tabs_provider` tegen de regelratchet aan zit; de extensie zit in dezelfde
/// library, dus de gedeelde security-poort blijft bereikbaar.
///
/// Opslaan schrijft rechtstreeks naar de forge; is er geen verbinding, dan gaat
/// de tekst naar de werkkopie ([DeckMirror]) en het deck in de wachtrij
/// ([Outbox]), die [flushGit] via de [SyncEngine] leegloopt zodra het kan (§8.5).
extension TabsNotifierGit on TabsNotifier {
  /// Standaardnaam van het markdown-bestand binnen een deckmap (§6).
  static const String deckFileName = 'deck.md';

  /// Open het deck in [deckDir] op [branch] read-only in het huidige tabblad.
  ///
  /// Volgt bewust dezelfde route als elk ander bytes-open: de `.md` gaat door
  /// [_gateAndParseContent] — de gedeelde `MarkdownSafetyScanner`-poort die ook
  /// een URL-import en een gesleept bestand passeren (P5). Een forge is niet
  /// vertrouwder dan WebDAV; ophalen is een import, geen zegen.
  ///
  /// Het tabblad krijgt geen `filePath`: er staat lokaal niets. Opslaan is dus
  /// een download, precies zoals bij een URL-import.
  ///
  /// Gooit [GitForgeException] bij een netwerk-, auth- of vormfout; die hoort de
  /// aanroeper te vertalen naar een melding.
  Future<OpenResult> openDeckFromGit(
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

    // Eerst de sha, dan de inhoud: zo draagt de tab de commit waar dit werk
    // daadwerkelijk tegenaan is gelezen. Andersom zou er tussen beide een
    // commit kunnen landen en zou de baseSha nieuwer zijn dan de bytes.
    final baseSha = await forge.headSha(branch);
    final bytes = await forge.readBlob(branch, '$deckDir/$deckFileName');
    if (bytes.length > FileService.maxDeckMarkdownBytes) {
      return OpenResult.unreadable;
    }

    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException catch (e) {
      logWarning('openDeckFromGit: deck.md is geen geldige UTF-8', e);
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
      baseSha: baseSha,
    );
    refreshTabs();
    return OpenResult.opened;
  }

  /// Haal de `repo:`-afbeeldingen van [deck] uit de pool en geef het deck terug
  /// met de slidepaden herschreven naar hun `mem:`-pad (§9.2).
  ///
  /// Zelfde kern als de pakket-import: bytes de [WebAssetStore] in, paden
  /// herschreven. Dat werkt op desktop én web, want die store is in-memory en
  /// niet web-only.
  ///
  /// De `repo:`-verwijzing gaat daarbij niet verloren waar het op aankomt: hij
  /// ís de hash van de inhoud, dus bij het terugschrijven (Fase 2) levert
  /// opnieuw hashen dezelfde verwijzing op en ziet `AssetPool.existing` dat de
  /// blob er al staat. Content-adressering maakt de heenweg omkeerbaar.
  ///
  /// Een asset die niet op te halen is of geen afbeelding blijkt wordt
  /// overgeslagen, niet fataal: het deck opent met een placeholder waar het
  /// plaatje hoort, net als een pakket met een kapotte verwijzing. Het hele deck
  /// weigeren omdat één plaatje ontbreekt zou een slechtere ruil zijn.
  Future<Deck> _withRepoAssets(
    Deck deck,
    AssetPool pool, {
    required String sourceName,
  }) async {
    final memFor = <String, String>{};
    Future<String?> memPath(String reference) async {
      if (!GitRepoLayout.isRepoAsset(reference)) return null;
      final cached = memFor[reference];
      if (cached != null) return cached;
      try {
        final bytes = await pool.resolve(reference);
        // Een forge is onvertrouwd (P5): een blob onder een .png-naam hoeft geen
        // afbeelding te zijn. Dezelfde controle als bij de pakket-import.
        if (bytes.isEmpty ||
            bytes.length > ImageService.maxImageBytes ||
            !ImageService.looksLikeImage(bytes)) {
          return null;
        }
        final path = GitRepoLayout.assetPathOf(reference);
        final mem = WebAssetStore.put(
          bytes,
          name: path == null ? 'asset' : p.posix.basename(path),
        );
        memFor[reference] = mem;
        return mem;
      } on GitForgeException catch (e) {
        logWarning('openDeckFromGit: asset onbereikbaar ($sourceName)', e);
        return null;
      }
    }

    final slides = <Slide>[];
    for (final slide in deck.slides) {
      slides.add(
        slide.copyWith(
          imagePath: await memPath(slide.imagePath) ?? slide.imagePath,
          imagePath2: await memPath(slide.imagePath2) ?? slide.imagePath2,
        ),
      );
    }
    return memFor.isEmpty ? deck : deck.copyWith(slides: slides);
  }

  /// Schrijf het deck van het huidige tabblad terug naar [deckDir] op [branch]
  /// als één commit (§9.1). Publiceert net zo goed een nieuw deck: dan is er nog
  /// geen [GitOrigin] en wordt [GitForge.headSha] de basis.
  ///
  /// De afbeeldingen gaan naar de gedeelde pool en `deck.md` verwijst ernaar
  /// (zie [buildDeckRepoFiles]) — de exacte omkering van [openDeckFromGit]. Bij
  /// succes draagt het tabblad de nieuwe commit als [GitOrigin.baseSha], zodat de
  /// volgende opslag een non-fast-forward kan detecteren.
  ///
  /// Gooit [GitForgeException] bij een onbruikbare [deckDir] (programmeerfout van
  /// de aanroeper). Netwerk-, auth- en conflict-uitkomsten komen als
  /// [GitSaveResult] terug — die hoort de UI te vertalen naar een melding.
  ///
  /// Krijgt het een [mirror] én een [outbox] mee, dan is verbinding kwijt geen
  /// verloren werk: bij een netwerkfout gaat de tekst naar de werkkopie en komt
  /// het deck in de wachtrij, die bij de volgende synchronisatie leegloopt (P2,
  /// §8.5). Zonder die twee is het pad online-only.
  Future<GitSaveResult> saveToGit(
    GitForge forge, {
    required GitRepoConfig config,
    required String deckDir,
    required String branch,
    required String message,
    DeckMirror? mirror,
    Outbox? outbox,
  }) async {
    if (GitRepoLayout.deckNameOf(deckDir) == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Pad is geen deckmap volgens de repo-layout',
      );
    }
    final deck = currentState.current?.deckNotifier.currentState.deck;
    if (deck == null) {
      return const GitSaveResult(status: GitSaveStatus.failed);
    }

    // Terugschrijven naar de eigen herkomst gebruikt de basis waarop dit werk is
    // gelezen; een nieuw of verplaatst deck valt terug op de huidige branchkop.
    final origin = currentState.current?.gitOrigin;
    final String baseSha;
    if (origin != null &&
        origin.matchesRepo(config) &&
        origin.branch == branch &&
        origin.deckDir == deckDir) {
      baseSha = origin.baseSha;
    } else {
      baseSha = await forge.headSha(branch);
    }

    // Een uit-git-geopend deck houdt zijn afbeeldingen als mem: op élk platform
    // (zie [_withRepoAssets]); [ImageService.readSlideImageBytes] leest mem:
    // alleen op web. Dus mem: eerst zelf, en pas daarna het bestandspad-pad.
    final image = ImageService();
    final files = await buildDeckRepoFiles(
      deck,
      md: _md,
      pool: AssetPool(forge: forge, branch: branch),
      deckDir: deckDir,
      resolveBytes: (path) async => WebAssetStore.isMemPath(path)
          ? WebAssetStore.bytesFor(path)
          : image.readSlideImageBytes(path, projectPath: deck.projectPath),
    );

    try {
      final result = await forge.commitFiles(
        branch: branch,
        message: message,
        upserts: files.upserts,
        deletes: const [],
        baseSha: baseSha,
      );
      currentState.current?.gitOrigin = GitOrigin(
        config: config,
        branch: branch,
        deckDir: deckDir,
        baseSha: result.sha,
      );
      refreshTabs();
      return GitSaveResult(
        status: GitSaveStatus.committed,
        sha: result.sha,
        warnings: files.warnings,
      );
    } on GitConflictException catch (e) {
      // Geen fout maar een uitkomst: het werk is niet weg, het kan alleen niet
      // zó landen. In Fase 2-vervolg wordt dit mergen; nu is het herladen.
      return GitSaveResult(
        status: GitSaveStatus.conflict,
        message: e.message,
        warnings: files.warnings,
      );
    } on GitForgeException catch (e) {
      // Verbinding kwijt is uitstel, geen mislukking: parkeer het werk als er
      // een wachtrij is (§8.5). Auth- of vormfouten zijn dat niet — die blijven
      // een echte mislukking, want opnieuw proberen lost ze niet op.
      if (e.kind == GitForgeError.network && mirror != null && outbox != null) {
        return _queueGitSave(
          mirror,
          outbox,
          deck: deck,
          deckDir: deckDir,
          branch: branch,
          message: message,
          baseSha: baseSha,
          warnings: files.warnings,
        );
      }
      logWarning('saveToGit: $deckDir niet opgeslagen', e);
      return GitSaveResult(
        status: GitSaveStatus.failed,
        message: e.message,
        warnings: files.warnings,
      );
    }
  }

  /// Parkeer een opslag in de wachtrij: de tekst gaat naar de werkkopie, de
  /// intentie in de outbox.
  ///
  /// De werkkopie bewaart `deck.md` ongepoold — met `mem:`-verwijzingen, zoals
  /// het deck nu in de editor staat. De afbeeldingen worden nog niet omgezet:
  /// offline kunnen de blobs toch niet omhoog, en hun bytes staan nu nog in het
  /// geheugen. Bij het synchroniseren pakt [flushGit] die op en poolt ze alsnog,
  /// zodat de commit compleet landt (§8.3). De tab houdt zijn herkomst zoals hij
  /// was: er is niets nieuws geland om de basis op te verzetten.
  Future<GitSaveResult> _queueGitSave(
    DeckMirror mirror,
    Outbox outbox, {
    required Deck deck,
    required String deckDir,
    required String branch,
    required String message,
    required String baseSha,
    required List<String> warnings,
  }) async {
    final deckFiles = <String, Uint8List>{
      p.posix.join(deckDir, deckRepoFileName): Uint8List.fromList(
        utf8.encode(_md.generateDeck(deck)),
      ),
    };
    await mirror.writeDeck(deckDir, deckFiles);
    await outbox.enqueue(
      PendingCommit(
        deckDir: deckDir,
        branch: branch,
        message: message,
        baseSha: baseSha,
      ),
    );
    return GitSaveResult(status: GitSaveStatus.queued, warnings: warnings);
  }

  /// Pool de afbeeldingen van een wachtend deck vlak vóór de commit: lees de
  /// bewaarde `deck.md`, en zet zijn `mem:`-afbeeldingen om naar `repo:` met de
  /// bijbehorende blobs (§8.3). Zo landt een offline gemaakte afbeelding alsnog,
  /// zolang de bytes nog in het geheugen staan; een afbeelding die na een
  /// herstart weg is houdt zijn verwijzing en toont een placeholder.
  Future<Map<String, Uint8List>> _poolPendingDeck(
    GitForge forge,
    PendingCommit commit,
    Map<String, Uint8List> stored,
  ) async {
    final raw = stored[p.posix.join(commit.deckDir, deckRepoFileName)];
    if (raw == null) return stored;
    final deck = _md.parseDeck(utf8.decode(raw));
    if (deck == null) return stored;

    final image = ImageService();
    final files = await buildDeckRepoFiles(
      deck,
      md: _md,
      pool: AssetPool(forge: forge, branch: commit.branch),
      deckDir: commit.deckDir,
      resolveBytes: (path) async => WebAssetStore.isMemPath(path)
          ? WebAssetStore.bytesFor(path)
          : image.readSlideImageBytes(path, projectPath: deck.projectPath),
    );
    return files.upserts;
  }

  /// Loop de wachtrij leeg tegen de forge (§8.5) en werk de basis bij van elk
  /// open tabblad waarvan het deck landde, zodat een volgende opslag daar niet
  /// meteen op een conflict loopt. Poolt onderweg de offline toegevoegde
  /// afbeeldingen. Geeft per deck terug hoe het afliep.
  Future<List<SyncOutcome>> flushGit(
    SyncEngine engine,
    GitRepoConfig config,
  ) async {
    final outcomes = await engine.flush(
      prepare: (commit, stored) =>
          _poolPendingDeck(engine.forge, commit, stored),
    );
    var changed = false;
    for (final outcome in outcomes) {
      if (outcome.sha == null) continue;
      for (final tab in currentState.tabs) {
        final origin = tab.gitOrigin;
        if (origin != null &&
            origin.matchesRepo(config) &&
            origin.deckDir == outcome.deckDir) {
          tab.gitOrigin = origin.copyWith(baseSha: outcome.sha);
          changed = true;
        }
      }
    }
    if (changed) refreshTabs();
    return outcomes;
  }
}

/// Hoe een [TabsNotifierGit.saveToGit] afliep.
enum GitSaveStatus {
  /// Gecommit; [GitSaveResult.sha] is de nieuwe basis.
  committed,

  /// Geen verbinding: de tekst staat in de werkkopie en het deck in de
  /// wachtrij, en gaat mee bij de volgende synchronisatie (§8.5).
  queued,

  /// Iemand anders heeft de branch verzet sinds de basis. Herladen (of, later,
  /// mergen).
  conflict,

  /// Auth of forge deed het niet — of er was geen deck om op te slaan.
  failed,
}

class GitSaveResult {
  final GitSaveStatus status;

  /// De nieuwe commit-sha bij [GitSaveStatus.committed].
  final String? sha;

  /// Uitlegbare tekst bij [GitSaveStatus.conflict] en [GitSaveStatus.failed].
  final String? message;

  /// Mediaverwijzingen die niet mee-gecommit zijn (video/audio, onleesbare
  /// afbeeldingen). Het deck sloeg wel op; de UI meldt wat er niet meeging.
  final List<String> warnings;

  const GitSaveResult({
    required this.status,
    this.sha,
    this.message,
    this.warnings = const [],
  });
}
