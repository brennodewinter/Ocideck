import 'dart:convert';
import 'dart:typed_data';

import '../../models/git_settings.dart';
import '../file_service.dart';
import 'git_forge.dart';
import 'git_transport.dart';
import 'git_transport_factory.dart';

/// GitHub (github.com én GitHub Enterprise Server) achter dezelfde [GitForge].
///
/// De enige plek waar GitHub-specifieke kennis mag zitten (P6). Twee dingen
/// wijken wezenlijk af van Gitea, en die verklaren de omvang van dit bestand:
///
/// - **Committen kost vier ronden.** Gitea zet meerdere bestanden in één
///   `POST /contents`; GitHub heeft dat niet. Daar bouw je via de Git Data API
///   een blob per bestand, dan een tree bovenop de vorige, dan een commit, en
///   dan verzet je de ref. Dat is ook waar de conflictdetectie zit: de ref
///   verzetten zónder force lukt alleen als het een fast-forward is, en dat is
///   precies niet zo wanneer iemand anders ondertussen commit.
/// - **De API-host verschilt van de web-host.** Voor github.com is dat
///   `api.github.com`; voor een eigen Enterprise-server is het `/api/v3` op
///   dezelfde host.
class GitHubForge implements GitForge {
  GitHubForge({
    required this.config,
    required this.token,
    GitTransport? transport,
  }) : _transport = transport ?? createGitTransport(config);

  final GitRepoConfig config;

  /// Het personal access token, uit de keychain gehaald door de aanroeper.
  /// Leeg is toegestaan: een publieke repo lezen mag zonder.
  final String token;

  final GitTransport _transport;

  static const int maxBlobBytes = FileService.maxPackageBytes;
  static const int maxListingBytes = 16 * 1024 * 1024;
  static const int maxListingEntries = 5000;

  /// GitHub wil `Bearer`, waar Gitea `token` wil. De API-versie staat er vast
  /// bij: zonder pin verandert het antwoord onder je handen bij een upgrade.
  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
  };

  /// De API zit op een ándere host dan de repo-URL: `api.github.com` voor
  /// github.com, `/api/v3` op de eigen host voor Enterprise.
  Uri _apiUri(List<String> segments, {Map<String, String>? query}) {
    final origin = config.origin;
    if (origin == null) {
      throw const GitForgeException(
        GitForgeError.config,
        'Ongeldige server-URL',
      );
    }
    final host = origin.host.toLowerCase();
    final isDotCom = host == 'github.com' || host == 'www.github.com';
    final base = isDotCom
        ? Uri.parse('https://api.github.com')
        : origin.replace(pathSegments: const ['api', 'v3']);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'repos',
        config.owner,
        config.repo,
        ...segments,
      ],
      queryParameters: query,
    );
  }

  // ── Lezen ───────────────────────────────────────────────────────────────────

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) async {
    _requireRef(ref);
    if (path.isNotEmpty && !GitRepoLayout.isSafeRepoPath(path)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onveilig pad opgevraagd',
      );
    }
    // De tree-API geeft de hele boom in één keer; filteren op prefix is
    // goedkoper dan per map een listing ophalen.
    final response = await _transport.get(
      _apiUri(['git', 'trees', ref], query: {'recursive': '1'}),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
    if (json is! Map || json['tree'] is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een tree-listing',
      );
    }
    final tree = json['tree'] as List;
    _requireEntryCount(tree.length);

    final prefix = path.isEmpty ? '' : '$path/';
    final out = <RepoEntry>[];
    for (final raw in tree) {
      if (raw is! Map) continue;
      final entryPath = raw['path'];
      final type = raw['type'];
      final sha = raw['sha'];
      if (entryPath is! String || type is! String || sha is! String) continue;
      if (prefix.isNotEmpty && !entryPath.startsWith(prefix)) continue;
      if (!recursive) {
        // Alleen directe leden: alles met nóg een schuine streep hoort dieper.
        // Ook in de wortel, waar het prefix leeg is — anders geeft een
        // niet-recursieve listing daar de hele boom terug.
        if (entryPath.substring(prefix.length).contains('/')) continue;
      }
      final size = raw['size'];
      out.add(
        RepoEntry(
          path: entryPath,
          sha: sha,
          type: type == 'tree' ? RepoEntryType.dir : RepoEntryType.file,
          size: size is int ? size : 0,
        ),
      );
    }
    // Op pad gesorteerd, zoals de andere adapters: de aanroeper mag niet van de
    // toevallige volgorde van een forge-antwoord afhangen.
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  @override
  Future<Uint8List> readBlob(String ref, String path) async {
    _requireRef(ref);
    if (!GitRepoLayout.isSafeRepoPath(path)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onveilig pad opgevraagd',
      );
    }
    // `Accept: raw` levert de bytes zelf in plaats van base64-in-JSON.
    final response = await _transport.get(
      _apiUri(['contents', path], query: {'ref': ref}),
      headers: {..._headers, 'Accept': 'application/vnd.github.raw'},
      maxBytes: maxBlobBytes,
    );
    _checkStatus(response.status);
    return response.bytes;
  }

  @override
  Future<String> headSha(String branch) async {
    _requireRef(branch);
    final response = await _transport.get(
      _apiUri(['branches', branch]),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
    final commit = json is Map ? json['commit'] : null;
    final sha = commit is Map ? commit['sha'] : null;
    if (sha is! String || sha.trim().isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Geen commit-sha in het antwoord',
      );
    }
    return sha;
  }

  // ── Schrijven ───────────────────────────────────────────────────────────────

  @override
  Future<CommitResult> commitFiles({
    required String branch,
    required String message,
    required Map<String, Uint8List> upserts,
    required List<String> deletes,
    required String baseSha,
  }) async {
    _requireRef(branch);
    _requireRef(baseSha);
    if (upserts.isEmpty && deletes.isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Niets te committen',
      );
    }
    for (final path in [...upserts.keys, ...deletes]) {
      if (!GitRepoLayout.isSafeRepoPath(path)) {
        throw GitForgeException(
          GitForgeError.malformed,
          'Onveilig pad in commit: $path',
        );
      }
    }

    // 1 — de boom waar we op voortbouwen.
    final baseTree = await _treeShaOf(baseSha);

    // 2 — een blob per bestand. GitHub wil ze los aangemaakt hebben; pas in de
    //     tree krijgen ze een pad.
    final entries = <Map<String, Object?>>[];
    for (final entry in upserts.entries) {
      final blob = await _post(
        ['git', 'blobs'],
        {'content': base64Encode(entry.value), 'encoding': 'base64'},
      );
      final sha = blob is Map ? blob['sha'] : null;
      if (sha is! String) {
        throw const GitForgeException(
          GitForgeError.malformed,
          'Blob aangemaakt maar zonder sha',
        );
      }
      entries.add({
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': sha,
      });
    }
    // Een verwijdering is een tree-entry met sha `null`. Alleen voor paden die
    // er echt staan: GitHub weigert een delete van iets wat er niet is.
    if (deletes.isNotEmpty) {
      final existing = {
        for (final e in await listTree(baseSha, '', recursive: true))
          if (e.type == RepoEntryType.file) e.path,
      };
      for (final path in deletes) {
        if (!existing.contains(path)) continue;
        entries.add({
          'path': path,
          'mode': '100644',
          'type': 'blob',
          'sha': null,
        });
      }
    }
    if (entries.isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Niets te committen',
      );
    }

    // 3 — de nieuwe boom, en 4 — de commit eronder.
    final tree = await _post(
      ['git', 'trees'],
      {'base_tree': baseTree, 'tree': entries},
    );
    final treeSha = tree is Map ? tree['sha'] : null;
    if (treeSha is! String) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Tree aangemaakt maar zonder sha',
      );
    }
    final commit = await _post(
      ['git', 'commits'],
      {
        'message': message,
        'tree': treeSha,
        'parents': [baseSha],
      },
    );
    final commitSha = commit is Map ? commit['sha'] : null;
    if (commitSha is! String) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Commit gemaakt maar zonder sha',
      );
    }

    // 5 — de branch verzetten. Zónder force, want dát is de concurrency-guard:
    // is er ondertussen op de branch gecommit, dan is onze commit (met de oude
    // basis als ouder) geen fast-forward meer en weigert GitHub met een 422.
    final response = await _transport.send(
      'PATCH',
      _apiUri(['git', 'refs', 'heads', branch]),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode({'sha': commitSha, 'force': false})),
      maxBytes: maxListingBytes,
    );
    // 422 = geen fast-forward: precies het geval dat we willen betrappen.
    if (response.status == 422 || response.status == 409) {
      throw GitConflictException(
        baseSha: baseSha,
        message:
            'Iemand anders heeft deze presentatie gewijzigd sinds jij hem '
            'opende. Haal de nieuwste versie op voordat je opnieuw opslaat.',
      );
    }
    _checkStatus(response.status);
    return CommitResult(commitSha);
  }

  // ── Releases ────────────────────────────────────────────────────────────────

  @override
  Future<List<BranchRef>> listBranches() async {
    final json = await _getJson(['branches'], query: {'per_page': '100'});
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een branch-listing',
      );
    }
    _requireEntryCount(json.length);
    return [for (final raw in json) ?_branchRef(raw)];
  }

  @override
  Future<BranchRef> createBranch(String name, {required String fromRef}) async {
    _requireRef(name);
    _requireRef(fromRef);
    // GitHub wil een sha, geen naam: eerst oplossen.
    final sha = await _resolveToSha(fromRef);
    final json = await _post(
      ['git', 'refs'],
      {'ref': 'refs/heads/${name.trim()}', 'sha': sha},
    );
    final object = json is Map ? json['object'] : null;
    final created = object is Map ? object['sha'] : null;
    if (created is! String) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Branch gemaakt maar zonder bruikbaar antwoord',
      );
    }
    return BranchRef(name: name.trim(), sha: created);
  }

  @override
  Future<List<TagRef>> listTags() async {
    final json = await _getJson(['tags'], query: {'per_page': '100'});
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een tag-listing',
      );
    }
    _requireEntryCount(json.length);
    return [for (final raw in json) ?_tagRef(raw)];
  }

  @override
  Future<TagRef> createTag(
    String name, {
    required String target,
    required String message,
  }) async {
    _requireRef(name);
    _requireRef(target);
    final sha = await _resolveToSha(target);
    // Een geannoteerde tag is bij GitHub twee stappen: het tag-object, en dan
    // de ref die ernaar wijst.
    final tag = await _post(
      ['git', 'tags'],
      {'tag': name.trim(), 'message': message, 'object': sha, 'type': 'commit'},
    );
    final tagSha = tag is Map ? tag['sha'] : null;
    if (tagSha is! String) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Tag gemaakt maar zonder sha',
      );
    }
    await _post(
      ['git', 'refs'],
      {'ref': 'refs/tags/${name.trim()}', 'sha': tagSha},
    );
    // De tag wíjst naar de commit; dat is wat de aanroeper wil weten.
    return TagRef(name: name.trim(), sha: sha);
  }

  @override
  Future<PullRequestRef> openPullRequest({
    required String head,
    required String base,
    required String title,
    String body = '',
  }) async {
    _requireRef(head);
    _requireRef(base);
    final json = await _post(
      ['pulls'],
      {'head': head, 'base': base, 'title': title, 'body': body},
    );
    final pr = _pullRef(json);
    if (pr == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Pull request geopend maar zonder bruikbaar antwoord',
      );
    }
    return pr;
  }

  @override
  Future<PullRequestRef> mergePullRequest(
    int number, {
    PullRequestMergeMethod method = PullRequestMergeMethod.merge,
    bool deleteBranch = false,
  }) async {
    if (number <= 0) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Ongeldig pull-request-nummer',
      );
    }
    // Anders dan Gitea kent GitHub geen "ruim de branch op"-vlag op de merge.
    // De branchnaam moeten we dus ophalen vóór het mergen — daarna is de PR
    // gesloten en is dat een omweg.
    String? head;
    if (deleteBranch) {
      final pr = _pullRef(await _getJson(['pulls', '$number']));
      head = pr?.head.isEmpty ?? true ? null : pr!.head;
    }

    final response = await _transport.send(
      'PUT',
      _apiUri(['pulls', '$number', 'merge']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode({'merge_method': method.name})),
      maxBytes: maxListingBytes,
    );
    // 405 = niet mergebaar (reviews, checks), 409 = de kop is verzet.
    if (response.status == 405 || response.status == 409) {
      throw const GitForgeException(
        GitForgeError.server,
        'De pull request kan nog niet gemerged worden — controleer reviews en '
        'conflicten op de forge.',
      );
    }
    _checkStatus(response.status);

    if (head != null) {
      // Best-effort: de merge is al geland, en een blijvende branch is hinder,
      // geen verlies.
      try {
        await _transport.send(
          'DELETE',
          _apiUri(['git', 'refs', 'heads', head]),
          headers: _headers,
          body: const [],
          maxBytes: maxListingBytes,
        );
      } on GitForgeException {
        // Bewust ingeslikt; zie hierboven.
      }
    }
    return PullRequestRef(
      number: number,
      url: '',
      state: 'merged',
      merged: true,
    );
  }

  @override
  Future<PullRequestRef?> pullRequestForBranch(String head) async {
    _requireRef(head);
    // GitHub filtert op `owner:branch`; dat scheelt de hele lijst doorlopen.
    final json = await _getJson(
      ['pulls'],
      query: {'state': 'open', 'head': '${config.owner}:${head.trim()}'},
    );
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een pull-request-listing',
      );
    }
    _requireEntryCount(json.length);
    for (final raw in json) {
      final pr = _pullRef(raw);
      if (pr != null && pr.head == head.trim()) return pr;
    }
    return null;
  }

  // ── Gedeeld ─────────────────────────────────────────────────────────────────

  /// De boom van een commit — de basis waarop [commitFiles] voortbouwt.
  Future<String> _treeShaOf(String commitSha) async {
    final json = await _getJson(['git', 'commits', commitSha]);
    final tree = json is Map ? json['tree'] : null;
    final sha = tree is Map ? tree['sha'] : null;
    if (sha is! String) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Geen tree in het commit-antwoord',
      );
    }
    return sha;
  }

  /// Een branchnaam, tag of sha naar een commit-sha. GitHub wil bij het maken
  /// van een ref een sha, niet een naam.
  Future<String> _resolveToSha(String ref) async {
    // Ziet het er al uit als een sha, dan is het er een.
    final r = ref.trim();
    if (RegExp(r'^[0-9a-f]{7,40}$').hasMatch(r)) return r;
    return headSha(r);
  }

  Future<Object?> _getJson(
    List<String> segments, {
    Map<String, String>? query,
  }) async {
    final response = await _transport.get(
      _apiUri(segments, query: query),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    return _decodeJson(response.bytes);
  }

  Future<Object?> _post(
    List<String> segments,
    Map<String, Object?> body,
  ) async {
    final response = await _transport.send(
      'POST',
      _apiUri(segments),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    return _decodeJson(response.bytes);
  }

  BranchRef? _branchRef(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final commit = raw['commit'];
    final sha = commit is Map ? commit['sha'] : null;
    if (name is! String || sha is! String) return null;
    return BranchRef(name: name, sha: sha);
  }

  TagRef? _tagRef(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final commit = raw['commit'];
    final sha = commit is Map ? commit['sha'] : null;
    if (name is! String || sha is! String) return null;
    return TagRef(name: name, sha: sha);
  }

  PullRequestRef? _pullRef(Object? raw) {
    if (raw is! Map) return null;
    final number = raw['number'];
    if (number is! int) return null;
    final head = raw['head'];
    final base = raw['base'];
    return PullRequestRef(
      number: number,
      url: raw['html_url'] is String ? raw['html_url'] as String : '',
      state: raw['state'] is String ? raw['state'] as String : 'open',
      merged: raw['merged'] == true,
      head: head is Map && head['ref'] is String ? head['ref'] as String : '',
      base: base is Map && base['ref'] is String ? base['ref'] as String : '',
    );
  }

  void _requireEntryCount(int count) {
    if (count > maxListingEntries) {
      throw const GitForgeException(
        GitForgeError.tooLarge,
        'Te veel bestanden in één listing',
      );
    }
  }

  void _checkStatus(int status) {
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw GitForgeException(
        GitForgeError.auth,
        'Aanmelden bij GitHub mislukt ($status). Controleer je token en of het '
        'toegang heeft tot ${config.slug}.',
      );
    }
    if (status == 404) {
      // Ook bij een repo die het token niet mag zien: GitHub verraadt liever
      // niet dát hij bestaat. De melding mag dat niet als zekerheid brengen.
      throw const GitForgeException(
        GitForgeError.notFound,
        'Niet gevonden — of je token heeft er geen toegang toe.',
      );
    }
    if (status == 409) {
      throw const GitForgeException(
        GitForgeError.notFound,
        'Repository is leeg.',
      );
    }
    if (status >= 500) {
      throw GitForgeException(GitForgeError.server, 'Serverfout ($status)');
    }
    throw GitForgeException(GitForgeError.server, 'Onverwachte status $status');
  }

  Object? _decodeJson(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Antwoord van GitHub is geen geldige JSON',
      );
    }
  }

  void _requireRef(String ref) {
    final r = ref.trim();
    if (r.isEmpty ||
        r.length > 255 ||
        r.startsWith('-') ||
        r.contains('..') ||
        r.contains('?') ||
        r.contains('#') ||
        r.contains('&') ||
        r.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Ongeldige branch-, tag- of commitnaam',
      );
    }
  }

  void close() => _transport.close();
}
