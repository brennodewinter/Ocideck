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

  /// De host is door NetGuard geweigerd, of onbereikbaar.
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

/// Het forge-plane: alles wat git zélf niet kent. Provider-agnostisch (P6), met
/// `GiteaForge`/`GitHubForge`/`GitLabForge` erachter; geen provider-specifieke
/// code mag naar de editor of de state-laag lekken.
///
/// Dit is bewust alléén het read-only oppervlak van Fase 0. Schrijven
/// (`commitFiles`), branches, tags en pull requests komen in Fase 2 en 4 —
/// een interfacemethode die `UnimplementedError` gooit is erger dan een
/// interface die eerlijk zegt wat hij nu kan.
///
/// Implementaties moeten:
/// - elk pad uit een tree door `GitRepoLayout.isSafeRepoPath` halen voordat het
///   naar buiten gaat (zip-slip-equivalent, §10.1);
/// - de caps respecteren zodat een vijandige forge het geheugen niet kan laten
///   vollopen;
/// - falen met [GitForgeException], nooit met een ruwe transportfout.
abstract class GitForge {
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
