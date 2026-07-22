import 'dart:convert';
import 'dart:typed_data';

import '../../models/git_settings.dart';
import 'forge_http.dart';
import 'git_forge.dart';
import 'git_transport.dart';
import 'git_transport_factory.dart';

/// Forgejo en Gitea achter één adapter: Forgejo is een fork van Gitea en de
/// REST-API's zijn op de punten die wij raken identiek.
///
/// Alleen het read-only oppervlak van Fase 0. De adapter is de enige plek waar
/// Gitea-specifieke kennis mag zitten (P6): de URL-vormen, de auth-header en de
/// JSON-vormen. Naar boven komt alleen [GitForge] met [GitForgeException].
class GiteaForge with ForgeHttp implements GitForge {
  GiteaForge({
    required this.config,
    required this.token,
    GitTransport? transport,
  }) : transport = transport ?? createGitTransport(config);

  @override
  final GitRepoConfig config;

  /// Het personal access token, uit de keychain gehaald door de aanroeper.
  /// Leeg is toegestaan: een publieke repo lezen mag zonder.
  final String token;

  @override
  final GitTransport transport;

  static const int maxBlobBytes = kForgeMaxBlobBytes;
  static const int maxListingBytes = kForgeMaxListingBytes;
  static const int maxListingEntries = kForgeMaxListingEntries;

  /// Bewust niet "Gitea": deze ene adapter bedient ook Forgejo, en wie Forgejo
  /// draait moet niet lezen dat het aanmelden bij Gitea mislukte.
  @override
  String get forgeName => 'de forge';

  @override
  bool get treats409AsEmptyRepo => true;

  /// Gitea/Forgejo verwacht `Authorization: token <PAT>` — niet `Bearer`.
  @override
  Map<String, String> get headers => {
    'Accept': 'application/json',
    if (token.trim().isNotEmpty) 'Authorization': 'token ${token.trim()}',
  };

  @override
  Uri apiUri(List<String> segments, {Map<String, String>? query}) {
    final origin = config.origin;
    if (origin == null) {
      throw const GitForgeException(
        GitForgeError.config,
        'Ongeldige server-URL',
      );
    }
    return origin.replace(
      pathSegments: [
        'api',
        'v1',
        'repos',
        config.owner.trim(),
        config.repo.trim(),
        ...segments,
      ],
      queryParameters: query,
    );
  }

  @override
  Future<RepoProbe> probe() async {
    final json = await getJson(const []);
    if (json is! Map) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op de repo-gegevens',
      );
    }
    final branch = json['default_branch'];
    final permissions = json['permissions'];
    return RepoProbe(
      // Een lege repo heeft bij Gitea nog geen default_branch; dan is onze
      // eigen instelling het beste antwoord dat we hebben.
      defaultBranch: branch is String && branch.trim().isNotEmpty
          ? branch.trim()
          : config.defaultBranch,
      isEmpty: json['empty'] == true,
      canPush: permissions is Map && permissions['push'] is bool
          ? permissions['push'] as bool
          : null,
    );
  }

  @override
  Future<String> headSha(String branch) async {
    requireRef(branch);
    final json = await getJson(['branches', branch]);
    if (json is! Map) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een branch-opvraging',
      );
    }
    final commit = json['commit'];
    final sha = commit is Map ? commit['id'] : null;
    if (sha is! String || sha.trim().isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Branch zonder commit-sha',
      );
    }
    return sha;
  }

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) async {
    requireRef(ref);
    if (path.isNotEmpty && !GitRepoLayout.isSafeRepoPath(path)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onveilig pad opgevraagd',
      );
    }
    return recursive ? _listRecursive(ref, path) : _listContents(ref, path);
  }

  /// Niet-recursief: `/contents/{path}` geeft één mapniveau.
  Future<List<RepoEntry>> _listContents(String ref, String path) async {
    final json = await getJson(
      ['contents', ...path.split('/').where((s) => s.isNotEmpty)],
      query: {'ref': ref},
    );
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een maplisting',
      );
    }
    requireEntryCount(json.length);
    final entries = <RepoEntry>[];
    for (final raw in json) {
      final entry = _contentsEntry(raw);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// Recursief: `/git/trees/{ref}?recursive=1` geeft de hele boom in één keer.
  Future<List<RepoEntry>> _listRecursive(String ref, String path) async {
    final json = await getJson(
      ['git', 'trees', ref],
      query: {'recursive': '1'},
    );
    if (json is! Map) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een tree-opvraging',
      );
    }
    // Gitea kapt een grote tree af en zegt dat eerlijk. Een halve boom stil
    // teruggeven zou erger zijn dan falen: de aanroeper zou denken dat een deck
    // niet bestaat terwijl het alleen niet meegestuurd is.
    if (json['truncated'] == true) {
      throw const GitForgeException(
        GitForgeError.tooLarge,
        'De repository-boom is te groot om in één keer te lezen.',
      );
    }
    final tree = json['tree'];
    if (tree is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Tree-antwoord zonder entries',
      );
    }
    requireEntryCount(tree.length);
    final prefix = path.isEmpty
        ? ''
        : '${path.replaceAll(RegExp(r'/+$'), '')}/';
    final entries = <RepoEntry>[];
    for (final raw in tree) {
      final entry = _treeEntry(raw);
      if (entry == null) continue;
      if (prefix.isEmpty || entry.path.startsWith(prefix)) entries.add(entry);
    }
    return entries;
  }

  /// Eén entry uit `/contents`. Geeft null wanneer de entry onbruikbaar is —
  /// een onveilig pad wordt overgeslagen, niet doorgegeven.
  RepoEntry? _contentsEntry(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final sha = raw['sha'];
    if (path is! String || sha is! String) return null;
    if (!GitRepoLayout.isSafeRepoPath(path)) return null;
    final size = raw['size'];
    return RepoEntry(
      path: path,
      sha: sha,
      size: size is int ? size : null,
      type: switch (raw['type']) {
        'file' => RepoEntryType.file,
        'dir' => RepoEntryType.dir,
        _ => RepoEntryType.other,
      },
    );
  }

  /// Eén entry uit `/git/trees`. Daar heten de soorten `blob` en `tree`.
  RepoEntry? _treeEntry(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final sha = raw['sha'];
    if (path is! String || sha is! String) return null;
    if (!GitRepoLayout.isSafeRepoPath(path)) return null;
    final size = raw['size'];
    return RepoEntry(
      path: path,
      sha: sha,
      size: size is int ? size : null,
      type: switch (raw['type']) {
        'blob' => RepoEntryType.file,
        'tree' => RepoEntryType.dir,
        _ => RepoEntryType.other,
      },
    );
  }

  @override
  Future<Uint8List> readBlob(String ref, String path) async {
    requireRef(ref);
    if (!GitRepoLayout.isSafeRepoPath(path)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onveilig pad opgevraagd',
      );
    }
    // `/raw` geeft de bytes zoals ze zijn. De `/contents`-variant zou base64 in
    // JSON geven: een derde groter, en voor een video onzinnig.
    final response = await transport.get(
      apiUri(
        ['raw', ...path.split('/').where((s) => s.isNotEmpty)],
        query: {'ref': ref},
      ),
      headers: {
        if (token.trim().isNotEmpty) 'Authorization': 'token ${token.trim()}',
      },
      maxBytes: maxBlobBytes,
    );
    checkStatus(response.status);
    return response.bytes;
  }

  @override
  Future<CommitResult> commitFiles({
    required String branch,
    required String message,
    required Map<String, Uint8List> upserts,
    required List<String> deletes,
    required String baseSha,
  }) async {
    requireRef(branch);
    requireRef(baseSha);
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

    // Gitea eist bij een `update`/`delete` de blob-sha van het bestand zoals het
    // er nú staat, en bij een `create` juist géén. Eén tree-listing bepaalt dus
    // per pad welke operatie het is — één call, niet één per bestand.
    final existing = await _blobShas(branch);

    final files = <Map<String, Object?>>[
      for (final entry in upserts.entries)
        {
          'operation': existing.containsKey(entry.key) ? 'update' : 'create',
          'path': entry.key,
          'content': base64Encode(entry.value),
          if (existing.containsKey(entry.key)) 'sha': existing[entry.key],
        },
      for (final path in deletes)
        // Een delete van iets dat er niet is slaan we over: de uitkomst die de
        // aanroeper wil (het staat er niet) is al bereikt, en Gitea zou erover
        // vallen.
        if (existing.containsKey(path))
          {'operation': 'delete', 'path': path, 'sha': existing[path]},
    ];
    if (files.isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Niets te committen',
      );
    }

    final response = await sendJson(
      'POST',
      ['contents'],
      {
        'branch': branch,
        'message': message,
        'files': files,
        // Dít is de concurrency-guard: Gitea weigert wanneer de branch niet meer
        // op deze commit staat, in plaats van er overheen te schrijven.
        'last_commit_id': baseSha,
      },
    );
    _checkCommitStatus(response.status, baseSha);

    final json = decodeJson(response.bytes);
    final commit = json is Map ? json['commit'] : null;
    final sha = commit is Map ? commit['sha'] : null;
    if (sha is! String || sha.trim().isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Commit gelukt maar zonder sha in het antwoord',
      );
    }
    return CommitResult(sha);
  }

  /// Pad → blob-sha voor de hele boom op [ref].
  Future<Map<String, String>> _blobShas(String ref) async {
    final entries = await listTree(ref, '', recursive: true);
    return {
      for (final entry in entries)
        if (entry.type == RepoEntryType.file) entry.path: entry.sha,
    };
  }

  /// Als [_checkStatus], maar met het conflict eruit gelicht.
  void _checkCommitStatus(int status, String baseSha) {
    // Een verschoven branch is geen fout maar een uitkomst. Gitea meldt hem als
    // 409; sommige versies gebruiken 422 voor dezelfde situatie.
    if (status == 409 || status == 422) {
      throw GitConflictException(
        baseSha: baseSha,
        message:
            'Iemand anders heeft deze presentatie gewijzigd sinds jij hem '
            'opende. Haal de nieuwste versie op voordat je opnieuw opslaat.',
      );
    }
    checkStatus(status);
  }

  // ── Releases (Fase 4) ───────────────────────────────────────────────────────

  @override
  Future<List<BranchRef>> listBranches() async {
    final json = await getJson(['branches'], query: {'limit': '50'});
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een branch-listing',
      );
    }
    requireEntryCount(json.length);
    return [for (final raw in json) ?_branchRef(raw)];
  }

  @override
  Future<BranchRef> createBranch(String name, {required String fromRef}) async {
    requireRef(name);
    requireRef(fromRef);
    final branch = _branchRef(
      await post(
        ['branches'],
        {'new_branch_name': name, 'old_ref_name': fromRef},
      ),
    );
    if (branch == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Branch gemaakt maar zonder bruikbaar antwoord',
      );
    }
    return branch;
  }

  @override
  Future<List<TagRef>> listTags() async {
    final json = await getJson(['tags'], query: {'limit': '50'});
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een tag-listing',
      );
    }
    requireEntryCount(json.length);
    return [for (final raw in json) ?_tagRef(raw)];
  }

  @override
  Future<TagRef> createTag(
    String name, {
    required String target,
    required String message,
  }) async {
    requireRef(name);
    requireRef(target);
    final tag = _tagRef(
      await post(
        ['tags'],
        {'tag_name': name, 'target': target, 'message': message},
      ),
    );
    if (tag == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Tag gemaakt maar zonder bruikbaar antwoord',
      );
    }
    return tag;
  }

  @override
  Future<PullRequestRef> openPullRequest({
    required String head,
    required String base,
    required String title,
    String body = '',
  }) async {
    requireRef(head);
    requireRef(base);
    final pr = _pullRef(
      await post(
        ['pulls'],
        {'head': head, 'base': base, 'title': title, 'body': body},
      ),
    );
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
    final response = await sendJson(
      'POST',
      ['pulls', '$number', 'merge'],
      {'Do': method.name, if (deleteBranch) 'delete_branch_after_merge': true},
    );
    // Gitea meldt "kan nog niet mergen" (open reviews, conflicten) als 405.
    if (response.status == 405) {
      throw const GitForgeException(
        GitForgeError.server,
        'De pull request kan nog niet gemerged worden — controleer reviews en '
        'conflicten op de forge.',
      );
    }
    checkStatus(response.status);
    // Een geslaagde merge geeft een lege body; het nummer kennen we al.
    return PullRequestRef(
      number: number,
      url: '',
      state: 'merged',
      merged: true,
    );
  }

  @override
  Future<PullRequestRef?> pullRequestForBranch(String head) async {
    requireRef(head);
    final json = await getJson(
      ['pulls'],
      query: {'state': 'open', 'limit': '50'},
    );
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een pull-request-listing',
      );
    }
    requireEntryCount(json.length);
    for (final raw in json) {
      final pr = _pullRef(raw);
      if (pr != null && pr.head == head.trim()) return pr;
    }
    return null;
  }

  BranchRef? _branchRef(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final commit = raw['commit'];
    final sha = commit is Map ? (commit['id'] ?? commit['sha']) : null;
    if (name is! String || sha is! String) return null;
    return BranchRef(name: name, sha: sha);
  }

  TagRef? _tagRef(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final commit = raw['commit'];
    final sha = commit is Map ? (commit['sha'] ?? commit['id']) : raw['id'];
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

  @override
  void close() => transport.close();
}
