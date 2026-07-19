import 'dart:typed_data';

import '../../models/git_settings.dart';

/// Soort van een entry in een git-tree.
enum RepoEntryType {
  file,
  dir,

  /// Symlink of submodule. We halen de inhoud er nooit uit: een symlink kan uit
  /// de repo wijzen en een submodule is een verwijzing naar een andere repo.
  /// Ze worden wel opgesomd, zodat de UI kan tonen dát ze er zijn.
  other,
}

/// Eén item in een git-tree-listing. Spiegelt `WebdavEntry`.
class RepoEntry {
  /// Pad vanaf de repo-wortel, zonder leidende slash. Is door
  /// `GitRepoLayout.isSafeRepoPath` gehaald voordat het hier belandt.
  final String path;

  final RepoEntryType type;

  /// Blob-sha van dit object.
  final String sha;

  /// Grootte in bytes; null wanneer de forge die niet meestuurt (bij mappen).
  final int? size;

  const RepoEntry({
    required this.path,
    required this.type,
    required this.sha,
    this.size,
  });

  /// Laatste pad-segment, voor weergave.
  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  String get _lower => name.toLowerCase();
  bool get isMarkdown => _lower.endsWith('.md');
}

/// Reden waarom een forge-bewerking faalde — zodat de UI een begrijpelijke
/// melding kan tonen zonder de ruwe fout te lekken. Spiegelt [WebdavError]:
/// dezelfde soorten, plus wat versiebeheer toevoegt.
enum GitForgeError {
  /// De repo-configuratie is onvolledig of onbruikbaar (geen host, geen owner).
  config,

  /// De servernaam bestaat niet of DNS antwoordde niet. Gescheiden van
  /// [blockedHost]: die twee vragen om tegengesteld advies.
  unknownHost,

  /// De host is door NetGuard geweigerd omdat hij (mede) naar een intern adres
  /// wijst. Alleen hier helpt "vertrouwd intern".
  blockedHost,

  network,
  auth,
  notFound,
  tooLarge,
  server,

  /// De forge stuurde iets terug dat we niet als geldig antwoord herkennen —
  /// ontbrekende velden, of een pad dat uit de repo breekt. Fail-closed: een
  /// forge is niet vertrouwder dan WebDAV (P5).
  malformed,
}

class GitForgeException implements Exception {
  final GitForgeError kind;
  final String message;
  const GitForgeException(this.kind, this.message);

  @override
  String toString() => 'GitForgeException($kind): $message';
}

/// Wat een verbindingstest over de repo te weten kwam.
///
/// Bewust méér dan "het werkte". WebDAV en S3 hebben genoeg aan een ja/nee —
/// daar is één pad fout of goed. Bij git kan alles kloppen (server bereikbaar,
/// token geldig, repo gevonden) en de eerste opslag alsnog stranden, omdat de
/// branch anders heet of het token alleen mag lezen. Dat zijn precies de
/// dingen die de forge nú al weet en die de gebruiker anders pas een
/// bewerkronde later ontdekt.
class RepoProbe {
  /// De standaardbranch zoals de forge hem kent. Wij kennen geen invoerveld
  /// hiervoor, dus dit is de enige manier waarop een repo met `master` in
  /// plaats van `main` ooit kan werken.
  final String defaultBranch;

  /// De repo bestaat maar heeft nog geen enkele commit. Geen fout: de eerste
  /// opslag maakt hem aan. Wel iets om te melden, want een lege repo geeft bij
  /// bijna elke andere aanroep een 404 of 409 die er alarmerender uitziet.
  final bool isEmpty;

  /// Of het token mag schrijven. `null` wanneer de forge het niet meldt — dan
  /// weten we het niet, en dat is iets anders dan "nee".
  final bool? canPush;

  const RepoProbe({
    required this.defaultBranch,
    this.isEmpty = false,
    this.canPush,
  });
}

/// Wat er van een geslaagde commit terugkomt.
class CommitResult {
  /// De sha van de nieuwe commit — de nieuwe [GitOrigin.baseSha] van de tab.
  final String sha;

  const CommitResult(this.sha);
}

/// Een branch: de naam plus de commit waar hij op staat (§9.5).
class BranchRef {
  final String name;
  final String sha;

  const BranchRef({required this.name, required this.sha});
}

/// Een tag: de naam plus de commit die hij aanwijst (§9.4 — release-tags
/// `decks/<naam>/vX`).
class TagRef {
  final String name;
  final String sha;

  const TagRef({required this.name, required this.sha});
}

/// Hoe een pull request gemerged wordt.
enum PullRequestMergeMethod { merge, squash, rebase }

/// Een pull request (§9.4): het nummer, de web-URL om op te reviewen, en of hij
/// nog open is of al gemerged.
class PullRequestRef {
  final int number;
  final String url;
  final String state;
  final bool merged;

  /// De bron- en doelbranch, wanneer bekend (bij het opsommen/opzoeken van een
  /// PR). Leeg wanneer het antwoord ze niet meegaf (bv. vlak na een merge).
  final String head;
  final String base;

  const PullRequestRef({
    required this.number,
    required this.url,
    required this.state,
    this.merged = false,
    this.head = '',
    this.base = '',
  });
}

/// Iemand anders heeft de branch verzet sinds [baseSha]. Bewust een eigen type
/// en geen [GitForgeException]-soort: dit is geen fout maar een uitkomst waar de
/// aanroeper iets mee moet — herladen, of (vanaf Fase 3) mergen. Het verschil
/// tussen "er ging iets mis" en "je bent ingehaald" mag niet vervagen.
class GitConflictException implements Exception {
  /// De commit waarop het werk was gebaseerd.
  final String baseSha;

  final String message;

  const GitConflictException({required this.baseSha, required this.message});

  @override
  String toString() => 'GitConflictException(base=$baseSha): $message';
}

/// Het forge-plane: alles wat git zélf niet kent. Provider-agnostisch (P6), met
/// `GiteaForge`/`GitHubForge`/`GitLabForge` erachter; geen provider-specifieke
/// code mag naar de editor of de state-laag lekken.
///
/// Het oppervlak groeit per fase mee. Lezen, schrijven, en — sinds Fase 4 —
/// branches, tags en pull requests staan er; een interfacemethode die
/// `UnimplementedError` gooit is erger dan een interface die eerlijk zegt wat
/// hij nu kan.
///
/// Implementaties moeten:
/// - elk pad uit een tree door `GitRepoLayout.isSafeRepoPath` halen voordat het
///   naar buiten gaat (zip-slip-equivalent, §10.1);
/// - de caps respecteren zodat een vijandige forge het geheugen niet kan laten
///   vollopen;
/// - falen met [GitForgeException], nooit met een ruwe transportfout.
abstract class GitForge {
  /// Haal de repo zelf op: bestaat hij, hoe heet zijn standaardbranch, is hij
  /// leeg, en mag dit token schrijven.
  ///
  /// De goedkoopste aanroep die alle vier beantwoordt, en de enige die de
  /// gebruiker kan doen vóórdat er werk in het spel is. Spiegelt
  /// `WebdavService.probe` en `S3Service.probe`, die git tot nu toe miste —
  /// waardoor elke instelfout pas bij de eerste opslag opdook.
  Future<RepoProbe> probe();

  /// Som de tree onder [path] op voor [ref] (branch, tag of sha). Een lege
  /// [path] is de repo-wortel. Met [recursive] worden ook submappen meegenomen.
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  });

  /// Haal de bytes van één blob op.
  Future<Uint8List> readBlob(String ref, String path);

  /// De commit-sha waar [branch] nu op staat. Dit is wat een tab als `baseSha`
  /// bewaart, zodat een latere commit een non-fast-forward kan detecteren in
  /// plaats van stil werk te overschrijven.
  Future<String> headSha(String branch);

  /// Eén save = één atomaire commit van de gewijzigde set (§7.2).
  ///
  /// [upserts] is pad → bytes, [deletes] zijn paden die verdwijnen. [baseSha] is
  /// de commit waarop het werk is geschreven: staat de branch daar niet meer op,
  /// dan is er iemand vóór je geweest en volgt een [GitConflictException] in
  /// plaats van een overschrijving. Dat is het git-equivalent van de
  /// atomic-write-guard van WebDAV.
  ///
  /// Atomair is geen detail: een half doorgekomen deck — markdown nieuw, asset
  /// nog niet — zou een commit opleveren die naar een blob wijst die er niet is.
  /// Elke provider kan dit in één server-side operatie; alleen de vorm verschilt
  /// (§7.2), en dat verschil hoort in de adapter.
  Future<CommitResult> commitFiles({
    required String branch,
    required String message,
    required Map<String, Uint8List> upserts,
    required List<String> deletes,
    required String baseSha,
  });

  // ── Releases (Fase 4, §9.4/§9.5) ────────────────────────────────────────────

  /// Alle branches in de repo.
  Future<List<BranchRef>> listBranches();

  /// Maak [name] aan, aftakkend van [fromRef] (een branch, tag of sha). Voor de
  /// gegenereerde werkbranch per bewerkronde (§9.4/D3).
  Future<BranchRef> createBranch(String name, {required String fromRef});

  /// Alle tags in de repo (de release-versies, §9.4).
  Future<List<TagRef>> listTags();

  /// Maak een geannoteerde tag [name] op [target] (een branch, tag of sha) met
  /// [message]. Een release-tag is een blijvende, geadverteerde verwijzing en
  /// staat daarom onder de classificatie-poort (P8) — die evalueert de aanroeper
  /// vóór dit punt.
  Future<TagRef> createTag(
    String name, {
    required String target,
    required String message,
  });

  /// Open een pull request van [head] naar [base]. Ook dit staat onder de
  /// classificatie-poort (P8), vóór het openen geëvalueerd.
  Future<PullRequestRef> openPullRequest({
    required String head,
    required String base,
    required String title,
    String body = '',
  });

  /// Merge pull request [number]. Branch-bescherming en verplichte reviews zijn
  /// de zaak van de forge, niet van OciDeck (§9.4). Met [deleteBranch] ruimt de
  /// forge de gemergede werkbranch meteen op — de gebruiker biedt dat aan.
  Future<PullRequestRef> mergePullRequest(
    int number, {
    PullRequestMergeMethod method = PullRequestMergeMethod.merge,
    bool deleteBranch = false,
  });

  /// De open pull request met [head] als bronbranch, of null als er geen is. Zo
  /// vindt "Merge concept" de PR van de werkbranch terug, ook een sessie later.
  Future<PullRequestRef?> pullRequestForBranch(String head);

  /// Geef het onderliggende transport vrij. Alle drie de adapters hadden dit
  /// al; het stond alleen niet in het contract, waardoor een aanroeper die met
  /// een [GitForge] werkt in plaats van met een concrete adapter hem niet kón
  /// sluiten — precies het geval van de verbindingstest.
  void close();
}

extension GitForgeDecks on GitForge {
  /// De deckmappen op [branch], als deknaam → pad.
  ///
  /// Alleen mappen direct onder `decks/` tellen: de layout kent geen genest
  /// deck (D6), en een map die niet als deknaam door de beugel kan laten we uit
  /// de lijst in plaats van hem half te tonen.
  Future<Map<String, String>> listDecks(String branch) async {
    final entries = await listTree(branch, GitRepoLayout.decksRoot);
    final decks = <String, String>{};
    for (final entry in entries) {
      if (entry.type != RepoEntryType.dir) continue;
      final name = GitRepoLayout.deckNameOf(entry.path);
      if (name != null) decks[name] = entry.path;
    }
    return decks;
  }
}
