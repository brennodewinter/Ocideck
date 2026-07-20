import 'dart:convert';
import 'dart:typed_data';

import 'package:ocideck/services/git/git_transport.dart';

import 'git_forge_fake.dart';

/// A transport that answers in **GitHub's** JSON shapes, backed by the same
/// [FakeRepo] as the Gitea one. That shared backing is the point: it lets the
/// contract suite assert that `GitHubForge` and the reference `FakeForge` agree
/// about behaviour, while differing completely in wire format.
///
/// The Git Data API is modelled properly rather than faked away, because that is
/// where GitHub actually differs: a commit is blobs → tree → commit → ref, and
/// the fast-forward check on that last step *is* the concurrency guard. So this
/// keeps real blob/tree/commit objects and refuses a ref update whose parent is
/// no longer the branch head — otherwise the conflict half of the contract would
/// pass without ever being exercised.
class FakeGitHubTransport implements GitTransport {
  FakeGitHubTransport(this.repo);

  final FakeRepo repo;

  final Map<String, Uint8List> _blobs = {};
  final Map<String, Map<String, Uint8List>> _trees = {};
  final Map<String, ({String tree, String? parent})> _commits = {};
  int _objectCounter = 1;

  String _nextSha(String kind) => '$kind-${_objectCounter++}';

  /// The file map a commit points at. Seed commits (the ones the test set up by
  /// hand) have no recorded tree, so they resolve to whatever the repo holds —
  /// the same single-tree simplification the Gitea fake makes.
  Map<String, Uint8List> _filesOfCommit(String sha) {
    final commit = _commits[sha];
    if (commit == null) return repo.files;
    return _trees[commit.tree] ?? repo.files;
  }

  String _treeIdOfCommit(String sha) {
    final commit = _commits[sha];
    if (commit != null) return commit.tree;
    // Seed commit: hand out a tree id that maps to the current files.
    final id = _nextSha('tree');
    _trees[id] = Map.of(repo.files);
    return id;
  }

  GitResponse _json(Object? body, [int status = 200]) =>
      GitResponse(status, Uint8List.fromList(utf8.encode(jsonEncode(body))));

  GitResponse _notFound() => _json({'message': 'Not Found'}, 404);

  /// Strip `/repos/<owner>/<repo>` (api.github.com) — the path always starts
  /// there for every endpoint this adapter uses.
  List<String> _rest(Uri uri) {
    final segments = uri.pathSegments.toList();
    final i = segments.indexOf('repos');
    return i < 0 ? segments : segments.skip(i + 3).toList();
  }

  @override
  Future<GitResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    final s = _rest(uri);
    // The repo object itself — what `probe()` asks for. GitHub reports no
    // emptiness flag, so the shape deliberately lacks one.
    if (s.isEmpty) {
      return _json({
        'default_branch': repo.branches.keys.firstOrNull ?? 'main',
        'permissions': {'admin': false, 'push': true, 'pull': true},
      });
    }

    // git/trees/<ref>?recursive=1
    if (s.length >= 3 && s[0] == 'git' && s[1] == 'trees') {
      final ref = s.skip(2).join('/');
      final files = _filesOfCommit(repo.resolveSha(ref));
      final dirs = <String>{};
      for (final path in files.keys) {
        final parts = path.split('/');
        for (var i = 1; i < parts.length; i++) {
          dirs.add(parts.take(i).join('/'));
        }
      }
      return _json({
        'sha': 'tree-of-$ref',
        'truncated': false,
        'tree': [
          for (final d in dirs)
            {'path': d, 'sha': FakeRepo.shaFor(d), 'type': 'tree'},
          for (final e in files.entries)
            {
              'path': e.key,
              'sha': FakeRepo.shaFor(e.key),
              'type': 'blob',
              'size': e.value.length,
            },
        ],
      });
    }

    // contents/<path>?ref=…  (Accept: raw → the bytes themselves)
    if (s.first == 'contents' && s.length >= 2) {
      final path = s.skip(1).join('/');
      final ref = uri.queryParameters['ref'] ?? 'main';
      final bytes = _filesOfCommit(repo.resolveSha(ref))[path];
      if (bytes == null) return _notFound();
      return GitResponse(200, bytes);
    }

    // branches  /  branches/<name>
    if (s.first == 'branches') {
      if (s.length == 1) {
        return _json([
          for (final e in repo.branches.entries)
            {
              'name': e.key,
              'commit': {'sha': e.value},
            },
        ]);
      }
      final name = s.skip(1).join('/');
      final sha = repo.branches[name];
      if (sha == null) return _notFound();
      return _json({
        'name': name,
        'commit': {'sha': sha},
      });
    }

    if (s.first == 'tags' && s.length == 1) {
      return _json([
        for (final e in repo.tags.entries)
          {
            'name': e.key,
            'commit': {'sha': e.value},
          },
      ]);
    }

    // git/commits/<sha> — the adapter needs its tree to build the next one.
    if (s.length == 3 && s[0] == 'git' && s[1] == 'commits') {
      return _json({
        'sha': s[2],
        'tree': {'sha': _treeIdOfCommit(s[2])},
      });
    }

    // pulls?state=open&head=owner:branch   /   pulls/<n>
    if (s.first == 'pulls') {
      if (s.length == 1) {
        final head = uri.queryParameters['head'];
        final wanted = head?.split(':').last;
        return _json([
          for (final p in repo.pulls)
            if (!p.merged && (wanted == null || p.head == wanted)) _pullJson(p),
        ]);
      }
      final number = int.tryParse(s[1]);
      for (final p in repo.pulls) {
        if (p.number == number) return _json(_pullJson(p));
      }
      return _notFound();
    }

    // search/code?q=<term> repo:owner/repo path:decks filename:deck.md
    // The qualifiers are ignored here on purpose: the fake returns every file
    // whose content contains the free-text term, so the adapter's own filtering
    // (down to decks/<name>/deck.md) is what the test exercises.
    if (s.length == 2 && s[0] == 'search' && s[1] == 'code') {
      final term = (uri.queryParameters['q'] ?? '')
          .split(' repo:')
          .first
          .trim();
      final lower = term.toLowerCase();
      return _json({
        'items': [
          for (final e in repo.files.entries)
            if (utf8.decode(e.value).toLowerCase().contains(lower))
              {'path': e.key, 'name': e.key.split('/').last},
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
    final s = _rest(uri);
    final payload = body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(utf8.decode(body)) as Map<String, Object?>;

    if (method == 'POST' && s.length == 2 && s[0] == 'git' && s[1] == 'blobs') {
      final sha = _nextSha('blob');
      _blobs[sha] = Uint8List.fromList(
        base64Decode(payload['content'] as String),
      );
      return _json({'sha': sha}, 201);
    }

    if (method == 'POST' && s.length == 2 && s[0] == 'git' && s[1] == 'trees') {
      // Start from the base tree and apply the entries; a null sha deletes.
      final base = payload['base_tree'] as String?;
      final files = Map<String, Uint8List>.of(
        base == null ? const {} : (_trees[base] ?? repo.files),
      );
      for (final raw in (payload['tree'] as List)) {
        final entry = raw as Map<String, Object?>;
        final path = entry['path'] as String;
        final sha = entry['sha'];
        if (sha == null) {
          files.remove(path);
        } else {
          files[path] = _blobs[sha] ?? Uint8List(0);
        }
      }
      final id = _nextSha('tree');
      _trees[id] = files;
      return _json({'sha': id}, 201);
    }

    if (method == 'POST' &&
        s.length == 2 &&
        s[0] == 'git' &&
        s[1] == 'commits') {
      final sha = 'commit-${repo.commitCounter++}';
      final parents = (payload['parents'] as List?)?.cast<String>() ?? const [];
      _commits[sha] = (
        tree: payload['tree'] as String,
        parent: parents.isEmpty ? null : parents.first,
      );
      return _json({'sha': sha}, 201);
    }

    if (method == 'POST' && s.length == 2 && s[0] == 'git' && s[1] == 'refs') {
      final ref = payload['ref'] as String;
      final sha = payload['sha'] as String;
      if (ref.startsWith('refs/heads/')) {
        repo.branches[ref.substring('refs/heads/'.length)] = sha;
      } else if (ref.startsWith('refs/tags/')) {
        repo.tags[ref.substring('refs/tags/'.length)] = sha;
      }
      return _json({
        'ref': ref,
        'object': {'sha': sha},
      }, 201);
    }

    if (method == 'POST' && s.length == 2 && s[0] == 'git' && s[1] == 'tags') {
      // An annotated tag object; the ref pointing at it comes separately.
      final sha = _nextSha('tagobj');
      return _json({'sha': sha, 'tag': payload['tag']}, 201);
    }

    // The concurrency guard: a ref only moves forward from its own parent.
    if (method == 'PATCH' &&
        s.length >= 3 &&
        s[0] == 'git' &&
        s[1] == 'refs' &&
        s[2] == 'heads') {
      final branch = s.skip(3).join('/');
      final sha = payload['sha'] as String;
      final parent = _commits[sha]?.parent;
      if (repo.branches[branch] != parent) {
        return _json({'message': 'Update is not a fast forward'}, 422);
      }
      repo.branches[branch] = sha;
      // The branch now points at our commit, so the repo's files follow.
      final files = _filesOfCommit(sha);
      repo.files
        ..clear()
        ..addAll(files);
      return _json({
        'object': {'sha': sha},
      });
    }

    if (method == 'DELETE' &&
        s.length >= 3 &&
        s[0] == 'git' &&
        s[1] == 'refs' &&
        s[2] == 'heads') {
      repo.branches.remove(s.skip(3).join('/'));
      return GitResponse(204, Uint8List(0));
    }

    if (method == 'POST' && s.length == 1 && s.first == 'pulls') {
      final pull = FakePull(
        number: repo.pullCounter++,
        head: payload['head'] as String,
        base: payload['base'] as String,
      );
      repo.pulls.add(pull);
      return _json(_pullJson(pull), 201);
    }

    if (method == 'PUT' &&
        s.length == 3 &&
        s[0] == 'pulls' &&
        s[2] == 'merge') {
      final number = int.tryParse(s[1]);
      for (final p in repo.pulls) {
        if (p.number != number) continue;
        p.merged = true;
        repo.branches[p.base] = repo.resolveSha(p.head);
        return _json({'merged': true, 'sha': repo.branches[p.base]});
      }
      return _notFound();
    }

    return _notFound();
  }

  Map<String, Object?> _pullJson(FakePull p) => {
    'number': p.number,
    'html_url': 'https://github.example/pulls/${p.number}',
    'state': p.merged ? 'closed' : 'open',
    'merged': p.merged,
    'head': {'ref': p.head},
    'base': {'ref': p.base},
  };

  @override
  void close() {}
}
