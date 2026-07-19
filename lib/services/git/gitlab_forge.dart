import 'dart:convert';
import 'dart:typed_data';

import '../../models/git_settings.dart';
import '../file_service.dart';
import 'git_forge.dart';
import 'git_transport.dart';
import 'git_transport_factory.dart';

/// GitLab (gitlab.com én self-hosted) achter dezelfde [GitForge].
///
/// De enige plek waar GitLab-specifieke kennis mag zitten (P6). Waar het van de
/// andere twee afwijkt:
///
/// - **Eén project-id in plaats van owner/repo in het pad.** GitLab adresseert
///   een project met een URL-geëncodeerd `owner/repo` (of een numeriek id), en
///   dat zit als één padsegment in elke URL.
/// - **Committen kan in één call, maar met een eigen vorm.** Anders dan GitHub
///   (vier ronden) is het hier één `POST /repository/commits` met een
///   `actions[]`-lijst, waarin per bestand staat of het `create`, `update` of
///   `delete` is. Dat onderscheid moet kloppen: GitLab weigert een `create` op
///   iets dat er al staat.
/// - **De conflictdetectie heet anders.** Wat Gitea met `last_commit_id` doet en
///   GitHub met een niet-forcerende ref-update, doet GitLab met `start_sha`
///   samen met de branchnaam: commit je op een basis die niet meer de kop is,
///   dan weigert hij.
/// - **Een pull request heet een merge request**, en wordt niet op zijn nummer
///   maar op zijn `iid` (per project oplopend) aangesproken.
class GitLabForge implements GitForge {
  GitLabForge({
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

  /// GitLab wil `PRIVATE-TOKEN`, waar Gitea `Authorization: token` wil en
  /// GitHub `Bearer`.
  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token.trim().isNotEmpty) 'PRIVATE-TOKEN': token.trim(),
  };

  /// `owner/repo`, URL-geëncodeerd tot één padsegment — zo adresseert GitLab
  /// een project.
  String get _projectId =>
      Uri.encodeComponent('${config.owner}/${config.repo}');

  Uri _apiUri(List<String> segments, {Map<String, String>? query}) {
    final origin = config.origin;
    if (origin == null) {
      throw const GitForgeException(
        GitForgeError.config,
        'Ongeldige server-URL',
      );
    }
    return origin.replace(
      // Het project-id is al geëncodeerd; via pathSegments zou Uri de schuine
      // streep er nóg eens overheen encoderen.
      path:
          '/api/v4/projects/$_projectId/${segments.map(Uri.encodeComponent).join('/')}',
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
    final json = await _getJson(
      ['repository', 'tree'],
      query: {
        'ref': ref,
        if (path.isNotEmpty) 'path': path,
        'recursive': recursive.toString(),
        'per_page': '100',
      },
    );
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een tree-listing',
      );
    }
    _requireEntryCount(json.length);
    final out = <RepoEntry>[];
    for (final raw in json) {
      if (raw is! Map) continue;
      final entryPath = raw['path'];
      final type = raw['type'];
      final id = raw['id'];
      if (entryPath is! String || type is! String) continue;
      out.add(
        RepoEntry(
          path: entryPath,
          sha: id is String ? id : '',
          // GitLab noemt een map 'tree' en een bestand 'blob'.
          type: type == 'tree' ? RepoEntryType.dir : RepoEntryType.file,
          size: 0,
        ),
      );
    }
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
    // `files/<pad>/raw` levert de bytes zelf; het pad is één geëncodeerd segment.
    final response = await _transport.get(
      _apiUri(['repository', 'files', path, 'raw'], query: {'ref': ref}),
      headers: _headers,
      maxBytes: maxBlobBytes,
    );
    _checkStatus(response.status);
    return response.bytes;
  }

  /// Bij GitLab zegt een getal wat je mag: 30 is Developer, en dat is de
  /// laagste rol die mag pushen. Rechten kunnen van het project óf van de
  /// bovenliggende groep komen; de hoogste van de twee telt.
  static const int _developerAccessLevel = 30;

  static int? _accessLevel(Object? access) {
    if (access is! Map) return null;
    final level = access['access_level'];
    return level is int ? level : null;
  }

  @override
  Future<RepoProbe> probe() async {
    final origin = config.origin;
    if (origin == null) {
      throw const GitForgeException(
        GitForgeError.config,
        'Ongeldige server-URL',
      );
    }
    // Niet via [_apiUri]: die plakt er een schuine streep achter wanneer er
    // geen segmenten zijn, en juist op het project zelf is dat een pad dat
    // niet elke GitLab-opstelling accepteert.
    final response = await _transport.get(
      origin.replace(path: '/api/v4/projects/$_projectId'),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
    if (json is! Map) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op de repo-gegevens',
      );
    }
    final branch = json['default_branch'];
    final permissions = json['permissions'];
    int? level;
    if (permissions is Map) {
      final project = _accessLevel(permissions['project_access']);
      final group = _accessLevel(permissions['group_access']);
      if (project != null || group != null) {
        level = (project ?? 0) > (group ?? 0) ? project : group;
      }
    }
    return RepoProbe(
      defaultBranch: branch is String && branch.trim().isNotEmpty
          ? branch.trim()
          : config.defaultBranch,
      isEmpty: json['empty_repo'] == true,
      canPush: level == null ? null : level >= _developerAccessLevel,
    );
  }

  @override
  Future<String> headSha(String branch) async {
    _requireRef(branch);
    final json = await _getJson(['repository', 'branches', branch]);
    final commit = json is Map ? json['commit'] : null;
    final sha = commit is Map ? commit['id'] : null;
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

    // GitLab eist per bestand het juiste werkwoord: een `create` op iets dat er
    // al staat is een fout, en een `delete` van iets dat er niet is ook. Eén
    // boom-listing bepaalt dus wat wat is — dezelfde truc als de Gitea-adapter.
    final existing = {
      for (final e in await listTree(baseSha, '', recursive: true))
        if (e.type == RepoEntryType.file) e.path,
    };

    final actions = <Map<String, Object?>>[
      for (final entry in upserts.entries)
        {
          'action': existing.contains(entry.key) ? 'update' : 'create',
          'file_path': entry.key,
          'content': base64Encode(entry.value),
          'encoding': 'base64',
        },
      for (final path in deletes)
        if (existing.contains(path)) {'action': 'delete', 'file_path': path},
    ];
    if (actions.isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Niets te committen',
      );
    }

    final response = await _transport.send(
      'POST',
      _apiUri(['repository', 'commits']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(
        jsonEncode({
          'branch': branch,
          'commit_message': message,
          // Dít is de concurrency-guard: commit je op een basis die niet meer de
          // kop van de branch is, dan weigert GitLab in plaats van eroverheen te
          // schrijven.
          'start_sha': baseSha,
          'start_branch': branch,
          'actions': actions,
        }),
      ),
      maxBytes: maxListingBytes,
    );
    // 400 met een "changed since" / 409: iemand anders was ons voor.
    if (response.status == 409 || response.status == 400) {
      throw GitConflictException(
        baseSha: baseSha,
        message:
            'Iemand anders heeft deze presentatie gewijzigd sinds jij hem '
            'opende. Haal de nieuwste versie op voordat je opnieuw opslaat.',
      );
    }
    _checkStatus(response.status);

    final json = _decodeJson(response.bytes);
    final sha = json is Map ? json['id'] : null;
    if (sha is! String || sha.trim().isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Commit gelukt maar zonder sha in het antwoord',
      );
    }
    return CommitResult(sha);
  }

  // ── Releases ────────────────────────────────────────────────────────────────

  @override
  Future<List<BranchRef>> listBranches() async {
    final json = await _getJson(
      ['repository', 'branches'],
      query: {'per_page': '100'},
    );
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
    final json = await _post(
      ['repository', 'branches'],
      {'branch': name.trim(), 'ref': fromRef},
    );
    final branch = _branchRef(json);
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
    final json = await _getJson(
      ['repository', 'tags'],
      query: {'per_page': '100'},
    );
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
    final json = await _post(
      ['repository', 'tags'],
      {'tag_name': name.trim(), 'ref': target, 'message': message},
    );
    final tag = _tagRef(json);
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
    final json = await _post(
      ['merge_requests'],
      {
        'source_branch': head,
        'target_branch': base,
        'title': title,
        'description': body,
      },
    );
    final pr = _pullRef(json);
    if (pr == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Merge request geopend maar zonder bruikbaar antwoord',
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
        'Ongeldig merge-request-nummer',
      );
    }
    final response = await _transport.send(
      'PUT',
      _apiUri(['merge_requests', '$number', 'merge']),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: utf8.encode(
        jsonEncode({
          // GitLab kent squash als vlag, niet als merge-methode; rebase is
          // een aparte endpoint. Voor onze doeleinden is de gewone merge genoeg.
          if (method == PullRequestMergeMethod.squash) 'squash': true,
          'should_remove_source_branch': deleteBranch,
        }),
      ),
      maxBytes: maxListingBytes,
    );
    // 405 = niet mergebaar (openstaande discussies, pipelines), 409 = verzet.
    if (response.status == 405 || response.status == 409) {
      throw const GitForgeException(
        GitForgeError.server,
        'De merge request kan nog niet gemerged worden — controleer reviews en '
        'conflicten op de forge.',
      );
    }
    _checkStatus(response.status);
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
    final json = await _getJson(
      ['merge_requests'],
      query: {
        'state': 'opened',
        'source_branch': head.trim(),
        'per_page': '50',
      },
    );
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een merge-request-listing',
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
    final sha = commit is Map ? commit['id'] : null;
    if (name is! String || sha is! String) return null;
    return BranchRef(name: name, sha: sha);
  }

  TagRef? _tagRef(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final commit = raw['commit'];
    final sha = commit is Map ? commit['id'] : raw['target'];
    if (name is! String || sha is! String) return null;
    return TagRef(name: name, sha: sha);
  }

  PullRequestRef? _pullRef(Object? raw) {
    if (raw is! Map) return null;
    // Het per-project oplopende iid is waar de rest van de API mee werkt; het
    // globale `id` is een ander getal en zou de verkeerde MR aanspreken.
    final iid = raw['iid'];
    if (iid is! int) return null;
    final state = raw['state'];
    return PullRequestRef(
      number: iid,
      url: raw['web_url'] is String ? raw['web_url'] as String : '',
      state: state is String ? (state == 'opened' ? 'open' : state) : 'open',
      merged: state == 'merged',
      head: raw['source_branch'] is String
          ? raw['source_branch'] as String
          : '',
      base: raw['target_branch'] is String
          ? raw['target_branch'] as String
          : '',
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
        'Aanmelden bij GitLab mislukt ($status). Controleer je token en of het '
        'toegang heeft tot ${config.slug}.',
      );
    }
    if (status == 404) {
      // Ook wanneer het token het project niet mag zien: GitLab verraadt liever
      // niet dát het bestaat. De melding mag dat niet als zekerheid brengen.
      throw const GitForgeException(
        GitForgeError.notFound,
        'Niet gevonden — of je token heeft er geen toegang toe.',
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
        'Antwoord van GitLab is geen geldige JSON',
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

  @override
  void close() => _transport.close();
}
