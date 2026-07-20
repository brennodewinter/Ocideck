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
    // Hetzelfde deck in dezelfde repo: dan is [GitOrigin.baseSha] de commit waar
    // dít werk tegenaan gelezen is, en dus de gemeenschappelijke voorouder.
    final sameDeck =
        origin != null &&
        origin.matchesRepo(config) &&
        origin.deckDir == deckDir;
    final midRound = sameDeck && origin.branch != branch;
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
      // De gelezen basis reist óók bij een verse ronde mee. De werkbranch draagt
      // alleen een datum, dus die van vandaag kán al bestaan — een tweede ronde
      // op dezelfde dag, of een collega die eerder was. Dan is dit de voorouder
      // waar de guard op botst en waarmee de driewegs-merge kan werken. Leeg
      // blijft het alleen voor een deck dat nog nooit uit deze repo is gelezen.
      baseSha: sameDeck ? origin.baseSha : '',
    );
  }

  /// De commit waar deze opslag tegenaan botst — de kern van de guard.
  ///
  /// Midden in een ronde is dat de gelezen basis. Bij een verse ronde takken we
  /// de werkbranch net af, en dan ís zijn kop onze basis. Bestaat die branch al
  /// — de werkbranchnaam draagt alleen een datum, dus een tweede ronde op
  /// dezelfde dag of een collega die eerder was — dan nemen we zijn kop juist
  /// **niet** over: de guard zou dan per definitie tevreden zijn en we schreven
  /// weg wat daar staat. De gelezen basis is dan de gemeenschappelijke
  /// voorouder, zodat het botst en de driewegs-merge zijn werk kan doen.
  ///
  /// Is er geen gelezen basis én bestaat de branch al, dan valt er niets te
  /// botsen en niets samen te voegen; `baseSha` is dan null en [blocked] legt
  /// uit waarom de opslag niet doorgaat.
  Future<({String? baseSha, String? blocked})> _roundBaseSha(
    GitForge forge, {
    required bool midRound,
    required String roundBase,
    required String workBranch,
    required String branch,
  }) async {
    if (midRound) return (baseSha: roundBase, blocked: null);
    final branches = await forge.listBranches();
    if (branches.every((b) => b.name != workBranch)) {
      final created = await forge.createBranch(workBranch, fromRef: branch);
      return (baseSha: created.sha, blocked: null);
    }
    if (roundBase.isNotEmpty) return (baseSha: roundBase, blocked: null);
    return (
      baseSha: null,
      blocked:
          'Er staat al een concept van vandaag op $workBranch, en dit deck '
          'komt daar niet uit voort. Open dat concept eerst, of geef dit deck '
          'een andere naam.',
    );
  }

  /// De bestanden die deze opslag naar de repo schrijft.
  ///
  /// Gaat het netwerk op: `AssetPool.existing` vraagt de forge welke blobs er al
  /// staan. Dat is de reden dat de aanroeper hem in een `try` zet — stond deze
  /// stap erbuiten, dan vloog een netwerkfout langs de afhandeling heen en kwam
  /// het werk nooit in de wachtrij, precies het geval waarvoor die bestaat. En
  /// dat trof élk uit git geopend deck, want [_withRepoAssets] zet bij het
  /// openen alle verwijzingen om naar `mem:`, dus de pool wordt altijd geraadpleegd.
  ///
  /// Een uit git geopend deck houdt zijn afbeeldingen als `mem:` op élk platform;
  /// [ImageService.readSlideImageBytes] leest `mem:` alleen op web. Dus `mem:`
  /// eerst zelf, en pas daarna het bestandspad-pad. De pool leest van [branch]:
  /// de werkbranch takt daarvan af en deelt dus zijn boom, en daarmee de blobs.
  Future<RepoDeckFiles> _repoFilesFor(
    Deck deck,
    GitForge forge, {
    required String branch,
    required String deckDir,
  }) {
    final image = ImageService();
    return buildDeckRepoFiles(
      deck,
      md: _md,
      pool: AssetPool(forge: forge, branch: branch),
      deckDir: deckDir,
      resolveBytes: (path) async => WebAssetStore.isMemPath(path)
          ? WebAssetStore.bytesFor(path)
          : image.readSlideImageBytes(path, projectPath: deck.projectPath),
    );
  }

  /// Parkeert het werk in de wachtrij wanneer [e] een netwerkfout is en er een
  /// wachtrij ís; anders null, en dan hoort de aanroeper de fout te laten staan.
  ///
  /// Verbinding kwijt is uitstel, geen mislukking (§8.5). Auth- en vormfouten
  /// zijn dat wél: opnieuw proberen lost die niet op.
  Future<GitSaveResult?> _queueIfOffline(
    GitForgeException e,
    DeckMirror? mirror,
    Outbox? outbox,
    ({
      Deck deck,
      String deckDir,
      String branch,
      String message,
      String baseSha,
      String? forkFrom,
    })
    queue, {
    List<String> warnings = const [],
  }) {
    if (e.kind != GitForgeError.network || mirror == null || outbox == null) {
      return Future.value(null);
    }
    return _queueGitSave(
      mirror,
      outbox,
      deck: queue.deck,
      deckDir: queue.deckDir,
      branch: queue.branch,
      message: queue.message,
      baseSha: queue.baseSha,
      forkFrom: queue.forkFrom,
      warnings: warnings,
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
    // Vóór het eerste wachtpunt vastzetten — zie [_mergeOnConflict] voor waarom.
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
    // Wat het parkeren nodig heeft; het pad komt tweemaal langs.
    final queue = (
      deck: deck,
      deckDir: deckDir,
      branch: workBranch,
      message: message,
      baseSha: round.baseSha,
      forkFrom: forkFrom,
    );
    final RepoDeckFiles files;
    try {
      files = await _repoFilesFor(
        deck,
        forge,
        branch: branch,
        deckDir: deckDir,
      );
    } on GitForgeException catch (e) {
      // Het bouwen gaat zélf het netwerk op; zie [_repoFilesFor].
      final queued = await _queueIfOffline(e, mirror, outbox, queue);
      if (queued != null) return queued;
      rethrow;
    }

    try {
      final resolved = await _roundBaseSha(
        forge,
        midRound: midRound,
        roundBase: round.baseSha,
        workBranch: workBranch,
        branch: branch,
      );
      final baseSha = resolved.baseSha;
      if (baseSha == null) {
        return GitSaveResult(
          status: GitSaveStatus.conflict,
          message: resolved.blocked,
          warnings: files.warnings,
        );
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
      final queued = await _queueIfOffline(
        e,
        mirror,
        outbox,
        queue,
        warnings: files.warnings,
      );
      if (queued != null) return queued;
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
    ///
    /// Een commit gaat over het netwerk en duurt; wisselt de gebruiker
    /// ondertussen van tabblad, dan wijst `currentState.current` daarna een
    /// ánder deck aan en landt de nieuwe [GitOrigin] — of, hier, een
    /// samengevoegd deck — bij het verkeerde tabblad. Dat tabblad committeert
    /// bij de volgende opslag zijn eigen inhoud over de deckmap van dit deck
    /// heen. [saveToWebdav] en [saveToS3] krijgen hun tabblad niet voor niets
    /// als parameter mee; het git-pad was de uitzondering.
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
