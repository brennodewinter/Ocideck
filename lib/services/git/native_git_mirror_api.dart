import 'dart:typed_data';

import 'deck_mirror.dart';
import 'deck_search.dart';
import 'git_forge.dart';

/// Welke van de drie kanten van een driewegs-merge bedoeld is.
enum MergeSide {
  /// De gemeenschappelijke voorouder.
  base,

  /// Onze lokale historie (`HEAD`).
  ours,

  /// Wat er op de forge staat (`origin/<branch>`).
  theirs,
}

/// Leest een bestand uit de deckmap zoals het op [side] stond.
///
/// Bestaat omdat een deckmap meer bevat dan `deck.md` — de notities, en straks
/// de tekenlaag — en die lagen per kant gelezen moeten kunnen worden vóór er
/// iets samen te voegen valt. Null wanneer het bestand op die kant niet bestond.
typedef MergeSideReader =
    Future<Uint8List?> Function(MergeSide side, String path);

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

  /// Lokaal gecommit (duurzaam, P2), maar de push mislukte om een reden die
  /// zichzelf níét oplost: een verkeerd token, geen rechten, een afgewezen
  /// certificaat. Anders dan [committedOffline] gaat dit niet vanzelf mee bij de
  /// volgende sync — de gebruiker moet eerst iets verhelpen. "Opgeslagen, gaat
  /// later mee" zou hier een loze belofte zijn; de UI meldt de verhelpbare
  /// reden. De reden staat in [GitCommitResult.pushError].
  committedButPushFailed,

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

  /// Waaróm de push mislukte — alleen gevuld bij
  /// [GitCommitOutcome.committedButPushFailed]. De commit staat lokaal; dit is
  /// de (geclassificeerde) reden dat publiceren niet lukte, zodat de UI een
  /// verhelpbare melding kan tonen (het token, het certificaat, de rechten).
  final GitForgeException? pushError;

  const GitCommitResult(this.outcome, {this.sha, this.pushError});
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

  /// Voeg `origin/[branch]` samen met de lokale historie na een geweigerde push
  /// (§8.6).
  ///
  /// De git-kant zit hier — ophalen, de gemeenschappelijke voorouder bepalen, de
  /// merge beginnen en er een echte merge-commit (twee ouders) van maken, zodat
  /// de volgende push gewoon fast-forward is. De *deckmap* lost de aanroeper op:
  /// [resolve] krijgt [deckFile] zoals hij in de voorouder, bij ons en bij hen
  /// staat, en geeft terug wat de deckmap moet worden. Zo blijft het samenvoegen
  /// van slides waar het thuishoort en weet dit bestand niets van decks.
  ///
  /// Naast die drie bytes krijgt [resolve] een [MergeSideReader], want een deck
  /// is meer dan zijn `deck.md`: de notities en de grafiekdata staan in eigen
  /// bestanden naast de markdown, en zonder een manier om díé per kant te lezen
  /// zou de aanroeper drie decks samenvoegen die alle drie leeg lijken.
  ///
  /// **`files` wordt geschreven, `deletes` wordt verwijderd, en de rest van de
  /// deckmap blijft staan.** Dat was ooit andersom: de map werd leeggemaakt en
  /// opnieuw gevuld, zodat elk bestand waar de resolver geen weet van had
  /// verdween — `data/*.json` bij élke merge, ook een geslaagde. De resolver
  /// kent de deckmap niet, alleen de drie `deck.md`'s, dus die volledigheid was
  /// niet waar te maken. Verwijderen gebeurt daarom alleen op verzoek (#670).
  ///
  /// `clean: false` betekent dat de aanroeper er niet uitkwam: de merge-commit
  /// wordt dan wél lokaal gemaakt — anders blijft de branch uiteenlopen en botst
  /// de volgende poging opnieuw — maar niet gepusht.
  Future<GitCommitResult> mergeRemote({
    required String branch,
    required String deckDir,
    required String deckFile,
    required String message,
    required Future<
      ({Map<String, Uint8List> files, List<String> deletes, bool clean})
    >
    Function(
      Uint8List? base,
      Uint8List? ours,
      Uint8List? theirs,
      MergeSideReader read,
    )
    resolve,
  });

  /// De commits die de deckmap raakten, nieuwste eerst (§9.5). Leeg wanneer er
  /// nog geen clone/historie is.
  Future<List<GitLogEntry>> history(String deckDir, {int limit = 50});

  /// Welke deckmappen bevatten [needle]? Snel en volledig via `git grep` over de
  /// werkboom van de uitgecheckte clone — de forge-onafhankelijke versneller die
  /// het lezen van elk deck bespaart (§9.3).
  ///
  /// Geeft de matchende deckmappen (exhaustief over [branch]), een lege lijst
  /// wanneer niets matcht, of `null` wanneer grep hier niet kan versnellen: er is
  /// nog geen clone, de werkboom staat op een andere branch dan [branch], of de
  /// term begint met een streepje (die weigert de gehardde runner). Bij `null`
  /// valt de aanroeper terug op de volledige scan, die overal werkt.
  Future<List<String>?> grepDeckDirs(
    String needle, {
    required bool caseSensitive,
    required String branch,
  });
}

/// Versnelt [DeckSearch] met `git grep` over de lokale clone: forge-onafhankelijk
/// en exhaustief. Geeft `null` door zodra de mirror niet kan versnellen, zodat de
/// zoekopdracht stil terugvalt op de volledige scan.
class NativeGrepShortlister implements DeckShortlister {
  NativeGrepShortlister(this._mirror);

  final NativeGitMirror _mirror;

  @override
  Future<DeckShortlist?> shortlist(
    String needle, {
    required bool caseSensitive,
    required String branch,
  }) async {
    final dirs = await _mirror.grepDeckDirs(
      needle,
      caseSensitive: caseSensitive,
      branch: branch,
    );
    if (dirs == null) return null;
    return DeckShortlist(dirs.toSet());
  }
}
