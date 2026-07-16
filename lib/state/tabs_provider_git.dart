part of 'tabs_provider.dart';

/// Het open-pad van de git-opslag (§9.2). Apart bestand omdat `tabs_provider`
/// tegen de regelratchet aan zit; de extensie zit in dezelfde library, dus de
/// gedeelde security-poort blijft bereikbaar.
///
/// Fase 0 is read-only. Terugschrijven (commit + push) komt in Fase 2, samen
/// met de DeckMirror en de SyncEngine.
extension TabsNotifierGit on TabsNotifier {
  /// Standaardnaam van het markdown-bestand binnen een deckmap (§6).
  static const String deckFileName = 'deck.md';

  /// Open het deck in [deckDir] op [branch] read-only in het huidige tabblad.
  ///
  /// Volgt bewust dezelfde route als elk ander bytes-open: de `.md` gaat door
  /// [openDeckFromBytes], en dus door dezelfde `MarkdownSafetyScanner`-poort als
  /// een URL-import of een gesleept bestand (P5). Een forge is niet vertrouwder
  /// dan WebDAV — clonen of ophalen is een import, geen zegen.
  ///
  /// Het tabblad krijgt geen `filePath`: er is lokaal niets. Opslaan is in Fase
  /// 0 dus een download, precies zoals bij een URL-import.
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

    final label = '${config.slug} · $deckName';
    final result = await openDeckFromBytes(bytes, label, remoteOrigin: label);
    if (result != OpenResult.opened) return result;
    if (!mounted) return OpenResult.unreadable;

    // De zojuist geopende deck zit in het huidige tabblad (zie openFileByPath).
    currentState.current?.gitOrigin = GitOrigin(
      config: config,
      branch: branch,
      deckDir: deckDir,
      baseSha: baseSha,
    );
    refreshTabs();
    return OpenResult.opened;
  }
}
