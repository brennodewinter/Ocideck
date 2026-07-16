part of 'tabs_provider.dart';

/// Het open-pad van de git-opslag (§9.2). Apart bestand omdat `tabs_provider`
/// tegen de regelratchet aan zit; de extensie zit in dezelfde library, dus de
/// gedeelde security-poort blijft bereikbaar.
///
/// Read-only. Terugschrijven (commit + push) komt in Fase 2, samen met de
/// DeckMirror en de SyncEngine.
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
}
