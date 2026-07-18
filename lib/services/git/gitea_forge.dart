import 'dart:convert';
import 'dart:typed_data';

import '../../models/git_settings.dart';
import '../file_service.dart';
import 'git_forge.dart';
import 'git_transport.dart';
import 'git_transport_factory.dart';

/// Forgejo en Gitea achter één adapter: Forgejo is een fork van Gitea en de
/// REST-API's zijn op de punten die wij raken identiek.
///
/// Alleen het read-only oppervlak van Fase 0. De adapter is de enige plek waar
/// Gitea-specifieke kennis mag zitten (P6): de URL-vormen, de auth-header en de
/// JSON-vormen. Naar boven komt alleen [GitForge] met [GitForgeException].
class GiteaForge implements GitForge {
  GiteaForge({
    required this.config,
    required this.token,
    GitTransport? transport,
  }) : _transport = transport ?? createGitTransport(config);

  final GitRepoConfig config;

  /// Het personal access token, uit de keychain gehaald door de aanroeper.
  /// Leeg is toegestaan: een publieke repo lezen mag zonder.
  final String token;

  final GitTransport _transport;

  /// Een blob mag zo groot zijn als een pakket: assets zijn hier de grote
  /// jongens, en de limiet verwijst naar de bron zodat de twee niet kunnen
  /// divergeren.
  static const int maxBlobBytes = FileService.maxPackageBytes;

  /// Cap op een listing-respons, zodat een vijandige forge het geheugen niet kan
  /// laten vollopen.
  static const int maxListingBytes = 16 * 1024 * 1024;

  /// Maximaal aantal entries dat we uit één listing accepteren.
  static const int maxListingEntries = 5000;

  /// Gitea/Forgejo verwacht `Authorization: token <PAT>` — niet `Bearer`.
  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token.trim().isNotEmpty) 'Authorization': 'token ${token.trim()}',
  };

  Uri _apiUri(List<String> segments, {Map<String, String>? query}) {
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

  /// Vertaal een HTTP-status naar een [GitForgeException]. Alleen 2xx gaat door.
  void _checkStatus(int status) {
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw GitForgeException(
        GitForgeError.auth,
        'Aanmelden bij de forge mislukt ($status). Controleer je token en of '
        'het toegang heeft tot ${config.slug}.',
      );
    }
    if (status == 404) {
      // Een forge geeft ook 404 wanneer het token de repo niet mag zien: hij
      // verraadt liever niet dát hij bestaat. De melding mag dat niet als
      // zekerheid presenteren.
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
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Antwoord van de forge is geen geldige JSON',
      );
    }
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
    _requireRef(ref);
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
    final response = await _transport.get(
      _apiUri(
        ['contents', ...path.split('/').where((s) => s.isNotEmpty)],
        query: {'ref': ref},
      ),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een maplisting',
      );
    }
    _requireEntryCount(json.length);
    final entries = <RepoEntry>[];
    for (final raw in json) {
      final entry = _contentsEntry(raw);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// Recursief: `/git/trees/{ref}?recursive=1` geeft de hele boom in één keer.
  Future<List<RepoEntry>> _listRecursive(String ref, String path) async {
    final response = await _transport.get(
      _apiUri(['git', 'trees', ref], query: {'recursive': '1'}),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
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
    _requireEntryCount(tree.length);
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

  void _requireEntryCount(int count) {
    if (count > maxListingEntries) {
      throw GitForgeException(
        GitForgeError.tooLarge,
        'Te veel entries in één listing ($count)',
      );
    }
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
    _requireRef(ref);
    if (!GitRepoLayout.isSafeRepoPath(path)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onveilig pad opgevraagd',
      );
    }
    // `/raw` geeft de bytes zoals ze zijn. De `/contents`-variant zou base64 in
    // JSON geven: een derde groter, en voor een video onzinnig.
    final response = await _transport.get(
      _apiUri(
        ['raw', ...path.split('/').where((s) => s.isNotEmpty)],
        query: {'ref': ref},
      ),
      headers: {
        if (token.trim().isNotEmpty) 'Authorization': 'token ${token.trim()}',
      },
      maxBytes: maxBlobBytes,
    );
    _checkStatus(response.status);
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

    final response = await _transport.post(
      _apiUri(['contents']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(
        jsonEncode({
          'branch': branch,
          'message': message,
          'files': files,
          // Dít is de concurrency-guard: Gitea weigert wanneer de branch niet
          // meer op deze commit staat, in plaats van er overheen te schrijven.
          'last_commit_id': baseSha,
        }),
      ),
      maxBytes: maxListingBytes,
    );
    _checkCommitStatus(response.status, baseSha);

    final json = _decodeJson(response.bytes);
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
    _checkStatus(status);
  }

  // ── Releases (Fase 4) ───────────────────────────────────────────────────────

  @override
  Future<List<BranchRef>> listBranches() async {
    final response = await _transport.get(
      _apiUri(['branches'], query: {'limit': '50'}),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
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
    final response = await _transport.post(
      _apiUri(['branches']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(
        jsonEncode({'new_branch_name': name, 'old_ref_name': fromRef}),
      ),
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final branch = _branchRef(_decodeJson(response.bytes));
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
    final response = await _transport.get(
      _apiUri(['tags'], query: {'limit': '50'}),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
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
    final response = await _transport.post(
      _apiUri(['tags']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(
        jsonEncode({'tag_name': name, 'target': target, 'message': message}),
      ),
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final tag = _tagRef(_decodeJson(response.bytes));
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
    _requireRef(head);
    _requireRef(base);
    final response = await _transport.post(
      _apiUri(['pulls']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(
        jsonEncode({'head': head, 'base': base, 'title': title, 'body': body}),
      ),
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final pr = _pullRef(_decodeJson(response.bytes));
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
    final response = await _transport.post(
      _apiUri(['pulls', '$number', 'merge']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(
        jsonEncode({
          'Do': method.name,
          if (deleteBranch) 'delete_branch_after_merge': true,
        }),
      ),
      maxBytes: maxListingBytes,
    );
    // Gitea meldt "kan nog niet mergen" (open reviews, conflicten) als 405.
    if (response.status == 405) {
      throw const GitForgeException(
        GitForgeError.server,
        'De pull request kan nog niet gemerged worden — controleer reviews en '
        'conflicten op de forge.',
      );
    }
    _checkStatus(response.status);
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
    _requireRef(head);
    final response = await _transport.get(
      _apiUri(['pulls'], query: {'state': 'open', 'limit': '50'}),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
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

  /// Een ref komt soms uit door de gebruiker of de forge geleverde data. Hij
  /// belandt in een URL-pad, dus weigeren we alles wat daar een betekenis heeft
  /// of wat git zelf niet als refnaam accepteert.
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
