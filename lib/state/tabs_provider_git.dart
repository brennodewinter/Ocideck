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

    final withAssets = await _withRepoAssets(
      parsed,
      AssetPool(forge: forge, branch: branch),
      sourceName: label,
    );
    final charts = await withRepoChartData(
      withAssets,
      deckDir: deckDir,
      read: (path) => forge.readBlob(branch, path),
    );
    final deck = charts.deck;
    if (!mounted) return OpenResult.unreadable;
    if (charts.missing.isNotEmpty) {
      _ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
        charts.missing,
      );
    }

    _placeDeckInTab(deck, remoteOrigin: label);
    currentState.current?.gitOrigin = GitOrigin(
      config: config,
      branch: branch,
      deckDir: deckDir,
      baseSha: baseSha,
      connectionId: connectionId,
    );
    refreshTabs();
    return OpenResult.opened;
  }

  /// Open release-versie [tag] van het deck in [deckDir] **read-only** (§9.4).
  /// Leest `deck.md` op de tag-ref, door dezelfde import-poort (P5) als elk
  /// ander open, en zet géén [GitOrigin]: een uitgebrachte versie is een
  /// momentopname om te bekijken, geen doel om overheen op te slaan. Wie hem wil
  /// herzien takt er een nieuwe ronde vanaf (dat is de gewone save-flow).
  Future<OpenResult> openVersionFromGit(
    GitForge forge, {
    required GitRepoConfig config,
    required String deckDir,
    required String tag,
  }) async {
    final read = await readVersionDeck(
      forge,
      config: config,
      deckDir: deckDir,
      tag: tag,
    );
    final deck = read.deck;
    if (deck == null) return read.failure;
    if (!mounted) return OpenResult.unreadable;

    _placeDeckInTab(deck, remoteOrigin: read.label);
    refreshTabs();
    return OpenResult.opened;
  }

  /// Lees het deck van een uitgebrachte versie, zónder het in een tabblad te
  /// plaatsen — de leeskant onder [openVersionFromGit] en onder het vergelijken
  /// van twee versies (§9.5).
  ///
  /// Loopt door dezelfde fail-closed importpoort als elk ander open uit een
  /// forge (P5): een versie is niet vertrouwder omdat er een tag op zit. Bij een
  /// blokkade is `deck` null en vertelt `failure` waarom.
  Future<({Deck? deck, OpenResult failure, String label})> readVersionDeck(
    GitForge forge, {
    required GitRepoConfig config,
    required String deckDir,
    required String tag,
  }) async {
    final deckName = GitRepoLayout.deckNameOf(deckDir);
    if (deckName == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Pad is geen deckmap volgens de repo-layout',
      );
    }
    final version = GitRepoLayout.versionOfTag(tag, deckName) ?? tag;
    final label = '${config.slug} · $deckName · $version';

    final bytes = await forge.readBlob(tag, '$deckDir/$deckFileName');
    if (bytes.length > FileService.maxDeckMarkdownBytes) {
      return (deck: null, failure: OpenResult.unreadable, label: label);
    }
    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException catch (e) {
      logWarning('readVersionDeck: deck.md is geen geldige UTF-8', e);
      return (deck: null, failure: OpenResult.unreadable, label: label);
    }

    final gated = _gateAndParseContent(raw, sourceName: label);
    final parsed = gated.deck;
    if (parsed == null) {
      return (deck: null, failure: gated.failure, label: label);
    }
    if (!mounted) {
      return (deck: null, failure: OpenResult.unreadable, label: label);
    }

    final withAssets = await _withRepoAssets(
      parsed,
      AssetPool(forge: forge, branch: tag),
      sourceName: label,
    );
    // Ook een uitgebrachte versie moet zijn cijfers meekrijgen: zonder dit
    // vergelijk je straks twee versies waarvan de grafieken allebei leeg zijn.
    final charts = await withRepoChartData(
      withAssets,
      deckDir: deckDir,
      read: (path) => forge.readBlob(tag, path),
    );
    return (deck: charts.deck, failure: OpenResult.opened, label: label);
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
  /// Op welke branch deze opslag landt, en of hij daar zelf van aftakt.
  ///
  /// D3: bewerken gebeurt op een werkbranch, nooit rechtstreeks op de
  /// standaardbranch. Zit dit tabblad al midden in een ronde op zo'n branch —
  /// zelfde repo, zelfde deck, andere branch — dan blijft het daar en is er
  /// niets af te takken. Anders start (of hervat) het de ronde van vandaag op
  /// `decks/<naam>/<datum>`. De naam wordt gegenereerd, niet getypt; de UI
  /// spreekt van "concept".
  ({String workBranch, String? forkFrom, bool midRound, String baseSha})
  _workBranchFor({
    required GitOrigin? origin,
    required GitRepoConfig config,
    required String deckDir,
    required String deckName,
    required String branch,
    required DateTime? now,
  }) {
    final midRound =
        origin != null &&
        origin.matchesRepo(config) &&
        origin.deckDir == deckDir &&
        origin.branch != branch;
    if (midRound) {
      return (
        workBranch: origin.branch,
        forkFrom: null,
        midRound: true,
        // Alleen midden in een ronde is er een basis om tegen te botsen; bij een
        // verse ronde bestaat de branch nog niet.
        baseSha: origin.baseSha,
      );
    }
    final generated = GitRepoLayout.workBranch(deckName, now ?? DateTime.now());
    if (generated == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Kon geen geldige werkbranch-naam maken',
      );
    }
    return (
      workBranch: generated,
      forkFrom: branch,
      midRound: false,
      baseSha: '',
    );
  }

  Future<GitSaveResult> saveToGit(
    GitForge forge, {
    required GitRepoConfig config,
    required String deckDir,
    required String branch,
    required String message,
    DeckMirror? mirror,
    Outbox? outbox,

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
    // Zet het tabblad vást vóór het eerste wachtpunt. Een commit gaat over het
    // netwerk en duurt; wisselt de gebruiker ondertussen van tabblad, dan zou
    // `currentState.current` daarna een ánder deck aanwijzen en landde de nieuwe
    // [GitOrigin] — of een samengevoegd deck — bij het verkeerde tabblad. Dat
    // tabblad committeert bij de volgende opslag zijn eigen inhoud over de
    // deckmap van dit deck heen. [saveToWebdav] en [saveToS3] krijgen hun
    // tabblad niet voor niets als parameter mee.
    final tab = currentState.current;
    final deck = tab?.deckNotifier.currentState.deck;
    if (deck == null) {
      return const GitSaveResult(status: GitSaveStatus.failed);
    }

    // Welke branch dit wordt, en of we ervan aftakken: zie [_workBranchFor].
    final origin = tab?.gitOrigin;
    final round = _workBranchFor(
      origin: origin,
      config: config,
      deckDir: deckDir,
      deckName: deckName,
      branch: branch,
      now: now,
    );
    final workBranch = round.workBranch;
    final forkFrom = round.forkFrom;
    final midRound = round.midRound;

    // Een uit-git-geopend deck houdt zijn afbeeldingen als mem: op élk platform
    // (zie [_withRepoAssets]); [ImageService.readSlideImageBytes] leest mem:
    // alleen op web. Dus mem: eerst zelf, en pas daarna het bestandspad-pad. De
    // pool leest van [branch]: de werkbranch takt daarvan af en deelt dus zijn
    // boom, dus dezelfde blobs.
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
      // Zorg dat de werkbranch bestaat en bepaal de basis. Midden in een ronde
      // is dat de gelezen basis (conflictdetectie blijft heel); de eerste commit
      // van een ronde landt op de kop van de werkbranch — hij tákt net af, dus er
      // is nog geen basis om tegen te botsen.
      final String baseSha;
      if (midRound) {
        baseSha = round.baseSha;
      } else {
        final branches = await forge.listBranches();
        final match = branches.where((b) => b.name == workBranch);
        baseSha = match.isNotEmpty
            ? match.first.sha
            : (await forge.createBranch(workBranch, fromRef: branch)).sha;
      }

      final result = await forge.commitFiles(
        branch: workBranch,
        message: message,
        upserts: files.upserts,
        deletes: const [],
        baseSha: baseSha,
      );
      tab?.gitOrigin = GitOrigin(
        config: config,
        branch: workBranch,
        deckDir: deckDir,
        baseSha: result.sha,
        connectionId: connectionId,
      );
      refreshTabs();
      return GitSaveResult(
        status: GitSaveStatus.committed,
        sha: result.sha,
        warnings: files.warnings,
      );
    } on GitConflictException catch (e) {
      // Geen fout maar een uitkomst: iemand anders verzette de branch. Probeer
      // samen te voegen in plaats van de gebruiker terug te sturen met "herlaad
      // maar" (§8.6). Lukt dat niet, dan is het alsnog een conflict — maar het
      // werk is nooit weg.
      return _mergeOnConflict(
        forge,
        tab: tab,
        config: config,
        deckDir: deckDir,
        branch: workBranch,
        baseSha: round.baseSha,
        ours: deck,
        message: message,
        fallback: e.message,
        warnings: files.warnings,
        connectionId: connectionId,
      );
    } on GitForgeException catch (e) {
      // Verbinding kwijt is uitstel, geen mislukking: parkeer het werk als er
      // een wachtrij is (§8.5). De werkbranch bestaat dan misschien nog niet —
      // [forkFrom] reist mee zodat het flushen hem alsnog aanmaakt (D3). Auth- of
      // vormfouten blijven een echte mislukking; opnieuw proberen lost ze niet op.
      if (e.kind == GitForgeError.network && mirror != null && outbox != null) {
        return _queueGitSave(
          mirror,
          outbox,
          deck: deck,
          deckDir: deckDir,
          branch: workBranch,
          message: message,
          baseSha: round.baseSha,
          forkFrom: forkFrom,
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

  /// Een opslag botste: iemand anders verzette de branch sinds wij hem lazen.
  /// Voeg de twee samen in plaats van de gebruiker terug te sturen (§8.6).
  ///
  /// Drie punten: [baseSha] is de gemeenschappelijke voorouder (waar wij op
  /// begonnen), de branchkop is wat de ander ervan maakte, en [ours] is wat er
  /// in de editor staat. Wat de merge zelf kan beslissen beslist hij; de rest
  /// komt als [SlideConflict] terug.
  ///
  /// Hoe het afloopt, loopt het tabblad hoe dan ook bij naar hún staat als
  /// nieuwe basis: of de merge nu schoon was of niet, de volgende opslag botst
  /// niet meer op ditzelfde punt. Bij een schone merge slaat hij meteen door
  /// (de melding vertelt wat er van de ander bij kwam); bij een conflict blijft
  /// het samengevoegde deck in het tabblad staan met ónze kant voorop, zodat de
  /// gebruiker kan kiezen en daarna gewoon opnieuw opslaat.
  Future<GitSaveResult> _mergeOnConflict(
    GitForge forge, {
    /// Het tabblad waar dit deck in staat, vastgezet vóór het eerste wachtpunt.
    /// Zie [saveToGit]: de merge doet drie netwerkrondes, en het resultaat moet
    /// bij dít deck landen, niet bij wat er dan toevallig vooraan staat.
    required TabInfo? tab,
    required GitRepoConfig config,
    required String deckDir,
    required String branch,
    required String baseSha,
    required Deck ours,
    required String message,
    required String fallback,
    required List<String> warnings,
    String connectionId = '',
  }) async {
    // Zonder gemeenschappelijke voorouder valt er niets driewegs te doen.
    if (baseSha.isEmpty) {
      return GitSaveResult(
        status: GitSaveStatus.conflict,
        message: fallback,
        warnings: warnings,
      );
    }
    try {
      final base = await readVersionDeck(
        forge,
        config: config,
        deckDir: deckDir,
        tag: baseSha,
      );
      final theirs = await readVersionDeck(
        forge,
        config: config,
        deckDir: deckDir,
        tag: branch,
      );
      if (base.deck == null || theirs.deck == null) {
        return GitSaveResult(
          status: GitSaveStatus.conflict,
          message: fallback,
          warnings: warnings,
        );
      }

      final merge = mergeDeckVersions(base.deck!, ours, theirs.deck!);
      final head = await forge.headSha(branch);
      if (!mounted) {
        return GitSaveResult(status: GitSaveStatus.failed, warnings: warnings);
      }

      // Het samengevoegde deck ín het tabblad, met hún kop als nieuwe basis.
      tab?.deckNotifier.loadDeck(merge.merged);
      tab?.gitOrigin = GitOrigin(
        config: config,
        branch: branch,
        deckDir: deckDir,
        baseSha: head,
        connectionId: connectionId,
      );
      refreshTabs();

      if (!merge.isClean) {
        // Kiezen is aan de gebruiker; opslaan gebeurt daarna gewoon opnieuw.
        return GitSaveResult(
          status: GitSaveStatus.conflict,
          conflicts: merge.conflicts,
          warnings: warnings,
        );
      }

      // Schoon samengevoegd: doorgaan met opslaan, en achteraf melden wat er van
      // de ander bij kwam.
      final image = ImageService();
      final mergedFiles = await buildDeckRepoFiles(
        merge.merged,
        md: _md,
        pool: AssetPool(forge: forge, branch: branch),
        deckDir: deckDir,
        resolveBytes: (path) async => WebAssetStore.isMemPath(path)
            ? WebAssetStore.bytesFor(path)
            : image.readSlideImageBytes(
                path,
                projectPath: merge.merged.projectPath,
              ),
      );
      final result = await forge.commitFiles(
        branch: branch,
        message: message,
        upserts: mergedFiles.upserts,
        deletes: const [],
        baseSha: head,
      );
      if (!mounted) {
        return GitSaveResult(status: GitSaveStatus.failed, warnings: warnings);
      }
      tab?.gitOrigin = GitOrigin(
        config: config,
        branch: branch,
        deckDir: deckDir,
        baseSha: result.sha,
        connectionId: connectionId,
      );
      refreshTabs();
      return GitSaveResult(
        status: GitSaveStatus.merged,
        sha: result.sha,
        warnings: [...warnings, ...mergedFiles.warnings],
      );
    } on GitConflictException {
      // De branch bewoog opnieuw terwijl we aan het samenvoegen waren.
      return GitSaveResult(
        status: GitSaveStatus.conflict,
        message: fallback,
        warnings: warnings,
      );
    } on GitForgeException catch (e) {
      logWarning('_mergeOnConflict: samenvoegen mislukt', e);
      return GitSaveResult(
        status: GitSaveStatus.conflict,
        message: e.message,
        warnings: warnings,
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
    String? forkFrom,
  }) async {
    final deckFiles = <String, Uint8List>{
      p.posix.join(deckDir, deckRepoFileName): Uint8List.fromList(
        utf8.encode(_md.generateDeck(deck)),
      ),
      // De databestanden moeten mee de werkkopie in, niet alleen deck.md: de
      // markdown draagt straks alleen nog de verwijzing, en bij het legen van
      // de wachtrij wordt het deck hiervandaan opnieuw gelezen. Zonder deze
      // bestanden zou daar een grafiek zonder cijfers uit komen.
      for (final entry in chartDataFilesOf(deck).entries)
        ?repoChartDataPath(deckDir, entry.key): Uint8List.fromList(
          utf8.encode(entry.value),
        ),
    };
    await mirror.writeDeck(deckDir, deckFiles);
    await outbox.enqueue(
      PendingCommit(
        deckDir: deckDir,
        branch: branch,
        message: message,
        baseSha: baseSha,
        forkFrom: forkFrom,
      ),
    );
    _ref.invalidate(gitQueueCountProvider);
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

    // deck.md draagt alleen de verwijzing naar de grafiekdata, dus die eerst
    // terughalen uit de werkkopie. Zonder dit ziet buildDeckRepoFiles een deck
    // zonder cijfers en laat het de databestanden uit de commit weg.
    final charts = await withRepoChartData(
      deck,
      deckDir: commit.deckDir,
      read: (path) async => stored[path],
    );

    final image = ImageService();
    final files = await buildDeckRepoFiles(
      charts.deck,
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

  /// Breng het concept van het huidige tabblad uit ter review (§9.4): open een
  /// pull request van de werkbranch naar de standaardbranch.
  ///
  /// Eerst de classificatiepoort, fail-closed en vóór élke netwerk-bijwerking —
  /// net als [ExportService.export] (export_service.dart:142), maar op de máx
  /// effective TLP van het hele deck ([deckReleaseTlp]), want een release is
  /// duurzaam en geadverteerd: één TLP:RED-slide in een TLP:none-deck hoort hem
  /// tegen te houden. Pas als de poort groen geeft gaat er iets naar de forge.
  ///
  /// Vereist dat het tabblad op een werkbranch staat (een lopende ronde) en dat
  /// die branch al op de forge staat — een gewone opslag pusht hem. Staat hij er
  /// nog niet (offline gecommit), dan komt dat als [ReviewStatus.failed] terug;
  /// synchroniseer dan eerst.
  Future<ReviewResult> openForReview(
    GitForge forge, {
    required GitRepoConfig config,
    required AppSettings settings,
    required String title,
    required String body,
  }) async {
    final tab = currentState.current;
    final origin = tab?.gitOrigin;
    final deck = tab?.deckNotifier.currentState.deck;
    if (origin == null || deck == null || !origin.matchesRepo(config)) {
      return const ReviewResult(status: ReviewStatus.notOnWorkBranch);
    }
    // Een review hoort bij een concept-ronde, niet bij de standaardbranch zelf.
    if (origin.branch == config.defaultBranch) {
      return const ReviewResult(status: ReviewStatus.notOnWorkBranch);
    }

    final decision = ClassificationEnforcementPolicy.fromAppSettings(
      settings,
    ).evaluate(deckReleaseTlp(deck));
    if (!decision.allowed) {
      return ReviewResult(
        status: ReviewStatus.blocked,
        message: decision.reason,
      );
    }

    try {
      final pr = await forge.openPullRequest(
        head: origin.branch,
        base: config.defaultBranch,
        title: title,
        body: body,
      );
      return ReviewResult(status: ReviewStatus.opened, pr: pr);
    } on GitForgeException catch (e) {
      logWarning('openForReview: PR openen mislukt', e);
      return ReviewResult(status: ReviewStatus.failed, message: e.message);
    }
  }

  /// Merge het concept van het huidige tabblad: vind de open pull request van de
  /// werkbranch, merge hem naar de standaardbranch, en — als [prune] — laat de
  /// forge de gemergede branch opruimen (§9.4). Daarna takt het tabblad terug op
  /// de standaardbranch: het concept ís nu de gepubliceerde versie, en een
  /// volgende opslag begint een nieuwe ronde.
  Future<MergeResult> mergeConcept(
    GitForge forge, {
    required GitRepoConfig config,
    bool prune = true,
  }) async {
    final tab = currentState.current;
    final origin = tab?.gitOrigin;
    if (origin == null || !origin.matchesRepo(config)) {
      return const MergeResult(status: MergeStatus.notOnWorkBranch);
    }
    if (origin.branch == config.defaultBranch) {
      return const MergeResult(status: MergeStatus.notOnWorkBranch);
    }

    try {
      final pr = await forge.pullRequestForBranch(origin.branch);
      if (pr == null) {
        return const MergeResult(status: MergeStatus.noPullRequest);
      }
      await forge.mergePullRequest(pr.number, deleteBranch: prune);
      // Het concept is nu deel van de standaardbranch: takt daar weer op vast.
      final head = await forge.headSha(config.defaultBranch);
      tab!.gitOrigin = GitOrigin(
        config: config,
        branch: config.defaultBranch,
        deckDir: origin.deckDir,
        baseSha: head,
        connectionId: origin.connectionId,
      );
      refreshTabs();
      return const MergeResult(status: MergeStatus.merged);
    } on GitForgeException catch (e) {
      logWarning('mergeConcept: mergen mislukt', e);
      return MergeResult(status: MergeStatus.failed, message: e.message);
    }
  }

  /// Leg de huidige versie van dit deck vast als release-tag `decks/<naam>/vX`
  /// op de kop van de standaardbranch (§9.4/D9). Achter dezelfde fail-closed
  /// classificatiepoort als [openForReview] (op de máx effective TLP): een tag is
  /// een blijvende, geadverteerde verwijzing en mag een deck niet voorbij zijn
  /// plafond publiceren.
  Future<ReleaseResult> tagRelease(
    GitForge forge, {
    required GitRepoConfig config,
    required AppSettings settings,
    required String version,
    required String message,
  }) async {
    final tab = currentState.current;
    final origin = tab?.gitOrigin;
    final deck = tab?.deckNotifier.currentState.deck;
    if (origin == null || deck == null || !origin.matchesRepo(config)) {
      return const ReleaseResult(status: ReleaseStatus.noDeck);
    }
    final deckName = origin.deckName;
    final tagName = deckName == null
        ? null
        : GitRepoLayout.releaseTag(deckName, version);
    if (tagName == null) {
      return const ReleaseResult(status: ReleaseStatus.invalidVersion);
    }

    final decision = ClassificationEnforcementPolicy.fromAppSettings(
      settings,
    ).evaluate(deckReleaseTlp(deck));
    if (!decision.allowed) {
      return ReleaseResult(
        status: ReleaseStatus.blocked,
        message: decision.reason,
      );
    }

    try {
      final tag = await forge.createTag(
        tagName,
        target: config.defaultBranch,
        message: message,
      );
      return ReleaseResult(status: ReleaseStatus.tagged, tag: tag);
    } on GitForgeException catch (e) {
      logWarning('tagRelease: tag maken mislukt', e);
      return ReleaseResult(status: ReleaseStatus.failed, message: e.message);
    }
  }
}

/// Hoe een [TabsNotifierGit.saveToGit] afliep.
enum GitSaveStatus {
  /// Gecommit; [GitSaveResult.sha] is de nieuwe basis.
  committed,

  /// Geen verbinding: de tekst staat in de werkkopie en het deck in de
  /// wachtrij, en gaat mee bij de volgende synchronisatie (§8.5).
  queued,

  /// Iemand anders verzette de branch én de twee waren niet vanzelf samen te
  /// voegen. [GitSaveResult.conflicts] vertelt per slide wat er botst; het
  /// tabblad draagt intussen het samengevoegde deck met ónze kant voorop.
  conflict,

  /// Iemand anders had de branch verzet, maar de twee bewerkingen vielen samen
  /// te voegen — dat is gebeurd en meteen gecommit (§8.6).
  merged,

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

  /// Bij [GitSaveStatus.conflict]: de slides waar beide kanten iets anders mee
  /// deden. Leeg wanneer er niet eens een driewegs-merge geprobeerd kon worden.
  final List<SlideConflict> conflicts;

  const GitSaveResult({
    required this.status,
    this.sha,
    this.message,
    this.warnings = const [],
    this.conflicts = const [],
  });
}

/// Hoe een [TabsNotifierGit.openForReview] afliep.
enum ReviewStatus {
  /// De pull request is geopend; [ReviewResult.pr] draagt het nummer + de link.
  opened,

  /// De classificatiepoort weigerde: het deck mag niet uitgebracht worden.
  /// [ReviewResult.message] draagt de uitlegbare reden.
  blocked,

  /// Er was geen concept om uit te brengen (geen tabblad, of het staat niet op
  /// een werkbranch).
  notOnWorkBranch,

  /// De forge deed het niet (netwerk, auth, of de branch staat er nog niet).
  failed,
}

class ReviewResult {
  final ReviewStatus status;

  /// De geopende pull request bij [ReviewStatus.opened].
  final PullRequestRef? pr;

  /// Uitlegbare tekst bij [ReviewStatus.blocked] en [ReviewStatus.failed].
  final String? message;

  const ReviewResult({required this.status, this.pr, this.message});
}

/// Hoe een [TabsNotifierGit.mergeConcept] afliep.
enum MergeStatus {
  /// Gemerged naar de standaardbranch; het tabblad takt daar nu op vast.
  merged,

  /// Er stond geen open pull request open voor deze werkbranch — nog niet
  /// uitgebracht ter review.
  noPullRequest,

  /// Er was geen concept om te mergen (geen tabblad, of het staat niet op een
  /// werkbranch).
  notOnWorkBranch,

  /// De forge deed het niet — bv. de PR kan (nog) niet gemerged worden.
  failed,
}

class MergeResult {
  final MergeStatus status;

  /// Uitlegbare tekst bij [MergeStatus.failed].
  final String? message;

  const MergeResult({required this.status, this.message});
}

/// Hoe een [TabsNotifierGit.tagRelease] afliep.
enum ReleaseStatus {
  /// De release-tag is gezet; [ReleaseResult.tag] draagt hem.
  tagged,

  /// De classificatiepoort weigerde: dit deck mag niet vastgelegd worden.
  /// [ReleaseResult.message] draagt de reden.
  blocked,

  /// De versie was geen geldige `vX` (of de deknaam deugde niet).
  invalidVersion,

  /// Er was geen deck om vast te leggen.
  noDeck,

  /// De forge deed het niet (netwerk, auth, of de tag bestond al).
  failed,
}

class ReleaseResult {
  final ReleaseStatus status;

  /// De gezette release-tag bij [ReleaseStatus.tagged].
  final TagRef? tag;

  /// Uitlegbare tekst bij [ReleaseStatus.blocked] en [ReleaseStatus.failed].
  final String? message;

  const ReleaseResult({required this.status, this.tag, this.message});
}
