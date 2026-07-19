import 'dart:convert';
import 'dart:typed_data';

import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/git_transport.dart';

/// An in-memory repository: the shared truth that both the reference
/// [FakeForge] and the Gitea-shaped [FakeGiteaTransport] serve. Having one
/// source of data is the point — it is what lets the contract suite assert that
/// the real adapter and the reference agree.
class FakeRepo {
  FakeRepo({
    required this.branches,
    required this.files,
    Map<String, String>? tags,
  }) : tags = tags ?? {};

  /// Branch name to commit sha.
  final Map<String, String> branches;

  /// Tag name to commit sha (Fase 4 — release-versies).
  final Map<String, String> tags;

  /// Repo-relative path to blob bytes.
  final Map<String, Uint8List> files;

  /// Open/merged pull requests (Fase 4).
  final List<FakePull> pulls = [];
  int pullCounter = 1;

  /// Bumped per commit, so every commit gets its own sha.
  int commitCounter = 1;

  /// Resolve a branch/tag name to its sha; an unknown ref is assumed to be a
  /// literal sha.
  String resolveSha(String ref) =>
      branches[ref.trim()] ?? tags[ref.trim()] ?? ref.trim();

  factory FakeRepo.sample() => FakeRepo(
    branches: {
      'main': 'commit-main',
      'decks/kwartaalcijfers/2026-07-16': 'commit-work',
    },
    files: {
      'decks/kwartaalcijfers/deck.md': _utf8('# Kwartaalcijfers'),
      'decks/kwartaalcijfers/deck.notes': _utf8('spreeknotities'),
      'decks/kwartaalcijfers/sub/nested.md': _utf8('# Nested'),
      'decks/jaarplan/deck.md': _utf8('# Jaarplan'),
      'assets/3f9a1c8e.png': Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
      'themes/librekat.css': _utf8('section { color: red }'),
    },
  );

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  /// Deterministic, so both implementations report the same sha for a blob.
  static String shaFor(String path) => 'sha-${path.hashCode.toUnsigned(32)}';

  bool hasBranch(String ref) => branches.containsKey(ref.trim());

  /// Every path that lives under [dir], as `(path, isDir)` — directories are
  /// synthesised from the file paths, exactly as a git tree does.
  List<(String, bool)> entriesUnder(String dir, {required bool recursive}) {
    final prefix = dir.isEmpty ? '' : '${dir.replaceAll(RegExp(r'/+$'), '')}/';
    final seen = <String, bool>{};
    for (final path in files.keys) {
      if (prefix.isNotEmpty && !path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      if (rest.isEmpty) continue;
      if (recursive) {
        // Every ancestor under the prefix becomes a dir entry, the leaf a file.
        final segments = rest.split('/');
        for (var i = 0; i < segments.length; i++) {
          final sub = '$prefix${segments.take(i + 1).join('/')}';
          seen[sub] = i < segments.length - 1;
        }
      } else {
        final head = rest.split('/').first;
        final isDir = rest.contains('/');
        seen['$prefix$head'] = isDir;
      }
    }
    final out = seen.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }
}

/// An in-memory pull request.
class FakePull {
  FakePull({required this.number, required this.head, required this.base});
  final int number;
  final String head;
  final String base;
  bool merged = false;
}

/// The reference [GitForge]: no transport, no JSON, just the repo. What the
/// contract suite says must hold, this is the plainest possible statement of.
class FakeForge implements GitForge {
  FakeForge(this.repo);

  final FakeRepo repo;

  void _requireRef(String ref) {
    final r = ref.trim();
    if (r.isEmpty || r.contains('..') || r.startsWith('-')) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Ongeldige branch-, tag- of commitnaam',
      );
    }
  }

  @override
  Future<RepoProbe> probe() async => RepoProbe(
    // De eerste branch is de standaard: de fake kent geen aparte instelling en
    // een testrepo heeft er in de praktijk één.
    defaultBranch: repo.branches.keys.firstOrNull ?? 'main',
    isEmpty: repo.branches.isEmpty,
    canPush: true,
  );

  @override
  Future<String> headSha(String branch) async {
    _requireRef(branch);
    final sha = repo.branches[branch.trim()];
    if (sha == null) {
      throw const GitForgeException(GitForgeError.notFound, 'Branch onbekend');
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
    return [
      for (final (p, isDir) in repo.entriesUnder(path, recursive: recursive))
        RepoEntry(
          path: p,
          sha: FakeRepo.shaFor(p),
          type: isDir ? RepoEntryType.dir : RepoEntryType.file,
          size: isDir ? null : repo.files[p]?.length,
        ),
    ];
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
    final head = repo.branches[branch.trim()];
    if (head == null) {
      throw const GitForgeException(GitForgeError.notFound, 'Branch onbekend');
    }
    // De hele reden dat baseSha bestaat: iemand anders is je voor geweest.
    if (head != baseSha) {
      throw GitConflictException(
        baseSha: baseSha,
        message: 'Branch staat op $head, niet op $baseSha',
      );
    }
    repo.files.addAll(upserts);
    for (final path in deletes) {
      repo.files.remove(path);
    }
    final sha = 'commit-${repo.commitCounter++}';
    repo.branches[branch.trim()] = sha;
    return CommitResult(sha);
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
    final bytes = repo.files[path];
    if (bytes == null) {
      throw const GitForgeException(GitForgeError.notFound, 'Niet gevonden');
    }
    return bytes;
  }

  // ── Releases (Fase 4) ───────────────────────────────────────────────────────

  @override
  Future<List<BranchRef>> listBranches() async => [
    for (final entry in repo.branches.entries)
      BranchRef(name: entry.key, sha: entry.value),
  ];

  @override
  Future<BranchRef> createBranch(String name, {required String fromRef}) async {
    _requireRef(name);
    _requireRef(fromRef);
    final sha = repo.resolveSha(fromRef);
    repo.branches[name.trim()] = sha;
    return BranchRef(name: name.trim(), sha: sha);
  }

  @override
  Future<List<TagRef>> listTags() async => [
    for (final entry in repo.tags.entries)
      TagRef(name: entry.key, sha: entry.value),
  ];

  @override
  Future<TagRef> createTag(
    String name, {
    required String target,
    required String message,
  }) async {
    _requireRef(name);
    _requireRef(target);
    final sha = repo.resolveSha(target);
    repo.tags[name.trim()] = sha;
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
    final pull = FakePull(number: repo.pullCounter++, head: head, base: base);
    repo.pulls.add(pull);
    return PullRequestRef(
      number: pull.number,
      url: 'fake://pull/${pull.number}',
      state: 'open',
      head: head.trim(),
      base: base.trim(),
    );
  }

  @override
  Future<PullRequestRef> mergePullRequest(
    int number, {
    PullRequestMergeMethod method = PullRequestMergeMethod.merge,
    bool deleteBranch = false,
  }) async {
    final pull = repo.pulls.firstWhere(
      (p) => p.number == number,
      orElse: () => throw const GitForgeException(
        GitForgeError.notFound,
        'Pull request niet gevonden',
      ),
    );
    // Merge = de base-branch schuift naar de head-commit.
    pull.merged = true;
    repo.branches[pull.base.trim()] = repo.resolveSha(pull.head);
    if (deleteBranch) repo.branches.remove(pull.head.trim());
    return PullRequestRef(
      number: number,
      url: 'fake://pull/$number',
      state: 'merged',
      merged: true,
    );
  }

  @override
  Future<PullRequestRef?> pullRequestForBranch(String head) async {
    _requireRef(head);
    for (final p in repo.pulls) {
      if (!p.merged && p.head.trim() == head.trim()) {
        return PullRequestRef(
          number: p.number,
          url: 'fake://pull/${p.number}',
          state: 'open',
          head: p.head.trim(),
          base: p.base.trim(),
        );
      }
    }
    return null;
  }
}

/// A transport that answers in Gitea's JSON shapes, backed by [FakeRepo]. Lets
/// the real `GiteaForge` run against the same data as [FakeForge] — so the
/// contract suite tests the adapter's parsing, not a second reimplementation.
class FakeGiteaTransport implements GitTransport {
  FakeGiteaTransport(this.repo);

  final FakeRepo repo;
  bool closed = false;

  @override
  Future<GitResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    // Strip /api/v1/repos/<owner>/<repo>
    final segments = uri.pathSegments.skip(5).toList();
    // The repo object itself — what `probe()` asks for.
    if (segments.isEmpty) {
      return _json({
        'default_branch': repo.branches.keys.firstOrNull ?? 'main',
        'empty': repo.branches.isEmpty,
        'permissions': {'admin': false, 'push': true, 'pull': true},
      });
    }

    if (segments.first == 'branches') {
      if (segments.length == 1) {
        return _json([
          for (final e in repo.branches.entries)
            {
              'name': e.key,
              'commit': {'id': e.value},
            },
        ]);
      }
      final branch = segments.skip(1).join('/');
      final sha = repo.branches[branch];
      if (sha == null) return _notFound();
      return _json({
        'name': branch,
        'commit': {'id': sha},
      });
    }

    if (segments.first == 'tags' && segments.length == 1) {
      return _json([
        for (final e in repo.tags.entries)
          {
            'name': e.key,
            'commit': {'sha': e.value},
          },
      ]);
    }

    if (segments.first == 'pulls' && segments.length == 1) {
      return _json([
        for (final p in repo.pulls)
          if (!p.merged)
            {
              'number': p.number,
              'html_url': 'https://forge.example/pulls/${p.number}',
              'state': 'open',
              'merged': false,
              'head': {'ref': p.head},
              'base': {'ref': p.base},
            },
      ]);
    }

    if (segments.first == 'raw') {
      final path = segments.skip(1).join('/');
      final bytes = repo.files[path];
      if (bytes == null) return _notFound();
      return GitResponse(200, bytes);
    }

    if (segments.first == 'contents') {
      final dir = segments.skip(1).join('/');
      return _json([
        for (final (p, isDir) in repo.entriesUnder(dir, recursive: false))
          {
            'path': p,
            'sha': FakeRepo.shaFor(p),
            'type': isDir ? 'dir' : 'file',
            if (!isDir) 'size': repo.files[p]!.length,
          },
      ]);
    }

    if (segments.length >= 2 &&
        segments[0] == 'git' &&
        segments[1] == 'trees') {
      final ref = segments.skip(2).join('/');
      if (!repo.hasBranch(ref)) return _notFound();
      return _json({
        'truncated': false,
        'tree': [
          for (final (p, isDir) in repo.entriesUnder('', recursive: true))
            {
              'path': p,
              'sha': FakeRepo.shaFor(p),
              'type': isDir ? 'tree' : 'blob',
              if (!isDir) 'size': repo.files[p]!.length,
            },
        ],
      });
    }

    return _notFound();
  }

  @override
  Future<GitResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required List<int> body,
    required int maxBytes,
  }) async {
    final segments = uri.pathSegments.skip(5).toList();

    if (segments.length == 1 && segments.first == 'branches') {
      final p = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
      final name = p['new_branch_name'] as String;
      final sha = repo.resolveSha(p['old_ref_name'] as String);
      repo.branches[name] = sha;
      return _json({
        'name': name,
        'commit': {'id': sha},
      });
    }

    if (segments.length == 1 && segments.first == 'tags') {
      final p = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
      final name = p['tag_name'] as String;
      final sha = repo.resolveSha(p['target'] as String);
      repo.tags[name] = sha;
      return _json({
        'name': name,
        'commit': {'sha': sha},
      });
    }

    if (segments.length == 1 && segments.first == 'pulls') {
      final p = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
      final pull = FakePull(
        number: repo.pullCounter++,
        head: p['head'] as String,
        base: p['base'] as String,
      );
      repo.pulls.add(pull);
      return _json({
        'number': pull.number,
        'html_url': 'https://forge.example/pulls/${pull.number}',
        'state': 'open',
        'merged': false,
        'head': {'ref': pull.head},
        'base': {'ref': pull.base},
      });
    }

    if (segments.length == 3 &&
        segments[0] == 'pulls' &&
        segments[2] == 'merge') {
      final number = int.tryParse(segments[1]);
      final pull = repo.pulls
          .where((p) => p.number == number)
          .cast<FakePull?>()
          .firstWhere((p) => true, orElse: () => null);
      if (pull == null) return _notFound();
      final p = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
      pull.merged = true;
      repo.branches[pull.base] = repo.resolveSha(pull.head);
      if (p['delete_branch_after_merge'] == true) {
        repo.branches.remove(pull.head);
      }
      return GitResponse(200, Uint8List(0)); // Gitea: lege body bij succes
    }

    if (segments.length != 1 || segments.first != 'contents') {
      return _notFound();
    }
    final payload = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    final branch = payload['branch'] as String;
    final head = repo.branches[branch];
    if (head == null) return _notFound();
    // Gitea's eigen concurrency-guard: de branch moet nog op last_commit_id
    // staan. 409 is wat hij dan geeft.
    if (payload['last_commit_id'] != head) {
      return _json({'message': 'not a fast forward'}, 409);
    }

    for (final raw in payload['files'] as List) {
      final file = raw as Map<String, Object?>;
      final path = file['path'] as String;
      switch (file['operation']) {
        case 'create':
        case 'update':
          repo.files[path] = Uint8List.fromList(
            base64Decode(file['content'] as String),
          );
        case 'delete':
          repo.files.remove(path);
      }
    }
    final sha = 'commit-${repo.commitCounter++}';
    repo.branches[branch] = sha;
    return _json({
      'commit': {'sha': sha},
    });
  }

  GitResponse _json(Object? body, [int status = 200]) =>
      GitResponse(status, Uint8List.fromList(utf8.encode(jsonEncode(body))));

  GitResponse _notFound() => _json({'message': 'Not Found'}, 404);

  @override
  void close() => closed = true;
}
