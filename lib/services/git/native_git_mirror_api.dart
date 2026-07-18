import 'dart:typed_data';

import 'deck_mirror.dart';

/// Hoe een native commit + push afliep (§8.2).
enum GitCommitOutcome {
  /// Gecommit én op de forge geland.
  pushed,

  /// Lokaal gecommit, maar niet gepusht omdat er geen verbinding was. De commit
  /// is duurzaam (het is echte git-historie); hij gaat mee bij de volgende sync.
  committedOffline,

  /// Lokaal gecommit, maar de push is geweigerd omdat de branch is verzet. Het
  /// werk is niet weg — het staat als echte commit klaar — maar samenvoegen
  /// vergt een merge (een latere fase). Tot dan blijft het lokaal.
  committedConflict,

  /// Er was niets veranderd sinds de vorige commit, en niets ongepusht.
  unchanged,
}

/// Eén regel uit de historie van een deck (§9.5): een commit die de deckmap
/// raakte.
class GitLogEntry {
  final String sha;
  final String subject;
  final String author;
  final DateTime? date;

  /// Of deze commit al op de forge staat, of nog lokaal wacht om gepusht te
  /// worden — de UI toont dat verschil (§9.6: een badge op de historie-regel,
  /// nooit een claim over "het deck").
  final bool pushed;

  const GitLogEntry({
    required this.sha,
    required this.subject,
    required this.author,
    required this.date,
    required this.pushed,
  });

  String get shortSha => sha.length >= 7 ? sha.substring(0, 7) : sha;
}

/// De uitkomst van een native opslag: de afloop plus de nieuwe HEAD-sha.
class GitCommitResult {
  final GitCommitOutcome outcome;

  /// De HEAD-commit na afloop — de nieuwe basis van de tab. Null wanneer er nog
  /// geen enkele commit is.
  final String? sha;

  const GitCommitResult(this.outcome, {this.sha});
}

/// De werkkopie als een échte lokale clone (§8.2): opslaan is een `git commit`,
/// duurzaam en offline, en synchroniseren is `git push`/`fetch`. Bovenop de
/// gewone [DeckMirror]-opslagcontract voegt hij de versiebeheer-bewerkingen toe.
///
/// Alleen op desktop met bruikbaar `git`; de fabriek geeft elders `null` en de
/// app valt dan terug op de REST-[DeckMirror] van Fase 2.
abstract class NativeGitMirror implements DeckMirror {
  /// Zorg dat de clone bestaat en, indien mogelijk, bijgewerkt is (`fetch`).
  /// Falen op de fetch is geen fout: offline openen mag.
  Future<void> prepareForOpen();

  /// De huidige HEAD-commit, of null als er nog niet gekloond/gecommit is. Dit
  /// is de basis waartegen een geopend deck is gelezen.
  Future<String?> headSha();

  /// Zet de bestandenset van een deck in de werkkopie, commit als er iets
  /// veranderd is, en probeer te pushen. De commit is altijd duurzaam; de push
  /// is best-effort (zie [GitCommitOutcome]).
  ///
  /// Geef [workBranch] mee om de commit op een werkbranch te laten landen in
  /// plaats van op de standaardbranch (D3): de clone checkt die branch uit (of
  /// maakt hem, afgetakt van [forkFrom]), commit erop en pusht hem. Zonder
  /// [workBranch] is het gedrag ongewijzigd — commit op de uitgecheckte branch.
  Future<GitCommitResult> commitDeck(
    String deckDir,
    Map<String, Uint8List> repoFiles,
    String message, {
    String? workBranch,
    String? forkFrom,
  });

  /// Push wat nog niet gepusht is (drain de lokale historie naar de forge).
  Future<GitCommitResult> sync();

  /// De commits die de deckmap raakten, nieuwste eerst (§9.5). Leeg wanneer er
  /// nog geen clone/historie is.
  Future<List<GitLogEntry>> history(String deckDir, {int limit = 50});
}
