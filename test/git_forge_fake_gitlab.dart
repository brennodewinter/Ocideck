import 'dart:convert';
import 'dart:typed_data';

import 'package:ocideck/services/git/git_transport.dart';

import 'git_forge_fake.dart';

/// A transport answering in **GitLab's** JSON shapes, on the same [FakeRepo] the
/// other two fakes use. Same rules, third wire format.
///
/// Two things are modelled rather than waved away, because they are exactly
/// where GitLab differs and therefore the only parts worth faking honestly:
///
/// - **`actions[]` verbs.** GitLab rejects a `create` on a path that exists and
///   a `delete` on one that does not, so the fake rejects them too — otherwise
///   the adapter could send the wrong verb forever and the suite would smile.
/// - **`start_sha` as the concurrency guard.** Committing on a base that is no
///   longer the branch head must be refused; that is GitLab's equivalent of
///   Gitea's `last_commit_id` and GitHub's non-forcing ref update.
class FakeGitLabTransport implements GitTransport {
  FakeGitLabTransport(this.repo);

  final FakeRepo repo;

  GitResponse _json(Object? body, [int status = 200]) =>
      GitResponse(status, Uint8List.fromList(utf8.encode(jsonEncode(body))));

  GitResponse _notFound() => _json({'message': '404 Not Found'}, 404);

  /// Everything after `/api/v4/projects/<id>/`, already percent-decoded.
  List<String> _rest(Uri uri) {
    final segments = uri.pathSegments.toList();
    final i = segments.indexOf('projects');
    return i < 0 ? segments : segments.skip(i + 2).toList();
  }

  @override
  Future<GitResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    final s = _rest(uri);
    final q = uri.queryParameters;
    // The project object itself — what `probe()` asks for. GitLab states
    // permissions as a numeric access level, not booleans; 30 is Developer.
    if (s.isEmpty) {
      return _json({
        'default_branch': repo.branches.keys.firstOrNull ?? 'main',
        'empty_repo': repo.branches.isEmpty,
        'permissions': {
          'project_access': {'access_level': 30},
        },
      });
    }

    if (s.length == 2 && s[0] == 'repository' && s[1] == 'tree') {
      final path = q['path'] ?? '';
      final recursive = q['recursive'] == 'true';
      return _json([
        for (final (p, isDir) in repo.entriesUnder(path, recursive: recursive))
          {
            'id': FakeRepo.shaFor(p),
            'name': p.split('/').last,
            'path': p,
            'type': isDir ? 'tree' : 'blob',
          },
      ]);
    }

    // repository/files/<path>/raw?ref=…
    if (s.length >= 4 &&
        s[0] == 'repository' &&
        s[1] == 'files' &&
        s.last == 'raw') {
      final path = s.sublist(2, s.length - 1).join('/');
      final bytes = repo.files[path];
      if (bytes == null) return _notFound();
      return GitResponse(200, bytes);
    }

    if (s.length >= 2 && s[0] == 'repository' && s[1] == 'branches') {
      if (s.length == 2) {
        return _json([
          for (final e in repo.branches.entries)
            {
              'name': e.key,
              'commit': {'id': e.value},
            },
        ]);
      }
      final name = s.sublist(2).join('/');
      final sha = repo.branches[name];
      if (sha == null) return _notFound();
      return _json({
        'name': name,
        'commit': {'id': sha},
      });
    }

    if (s.length == 2 && s[0] == 'repository' && s[1] == 'tags') {
      return _json([
        for (final e in repo.tags.entries)
          {
            'name': e.key,
            'commit': {'id': e.value},
          },
      ]);
    }

    if (s.length == 1 && s[0] == 'merge_requests') {
      final source = q['source_branch'];
      return _json([
        for (final p in repo.pulls)
          if (!p.merged && (source == null || p.head == source)) _mrJson(p),
      ]);
    }

    // search?scope=blobs&search=<term>&ref=<branch> — project-scope blob search.
    // Like the GitHub fake, this returns every file whose content contains the
    // term (the adapter filters down to decks/<name>/deck.md itself). An
    // unsupported scope answers empty, as a basic-search instance would.
    if (s.length == 1 && s[0] == 'search') {
      if (q['scope'] != 'blobs') return _json([]);
      final lower = (q['search'] ?? '').toLowerCase();
      return _json([
        for (final e in repo.files.entries)
          if (utf8.decode(e.value).toLowerCase().contains(lower))
            {'path': e.key, 'basename': e.key.split('/').last.split('.').first},
      ]);
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

    if (method == 'POST' &&
        s.length == 2 &&
        s[0] == 'repository' &&
        s[1] == 'commits') {
      final branch = payload['branch'] as String;
      final head = repo.branches[branch];
      if (head == null) return _notFound();
      // De guard: committen op een basis die niet meer de kop is, weigert.
      if (payload['start_sha'] != head) {
        return _json({'message': 'Branch changed since start_sha'}, 409);
      }
      for (final raw in (payload['actions'] as List)) {
        final action = raw as Map<String, Object?>;
        final path = action['file_path'] as String;
        switch (action['action']) {
          case 'create':
            if (repo.files.containsKey(path)) {
              return _json({
                'message': 'A file with this name already exists',
              }, 400);
            }
            repo.files[path] = Uint8List.fromList(
              base64Decode(action['content'] as String),
            );
          case 'update':
            if (!repo.files.containsKey(path)) {
              return _json({
                'message': 'A file with this name does not exist',
              }, 400);
            }
            repo.files[path] = Uint8List.fromList(
              base64Decode(action['content'] as String),
            );
          case 'delete':
            if (!repo.files.containsKey(path)) {
              return _json({
                'message': 'A file with this name does not exist',
              }, 400);
            }
            repo.files.remove(path);
        }
      }
      final sha = 'commit-${repo.commitCounter++}';
      repo.branches[branch] = sha;
      return _json({'id': sha}, 201);
    }

    if (method == 'POST' &&
        s.length == 2 &&
        s[0] == 'repository' &&
        s[1] == 'branches') {
      final name = payload['branch'] as String;
      final sha = repo.resolveSha(payload['ref'] as String);
      repo.branches[name] = sha;
      return _json({
        'name': name,
        'commit': {'id': sha},
      }, 201);
    }

    if (method == 'POST' &&
        s.length == 2 &&
        s[0] == 'repository' &&
        s[1] == 'tags') {
      final name = payload['tag_name'] as String;
      final sha = repo.resolveSha(payload['ref'] as String);
      repo.tags[name] = sha;
      return _json({
        'name': name,
        'commit': {'id': sha},
      }, 201);
    }

    if (method == 'POST' && s.length == 1 && s[0] == 'merge_requests') {
      final pull = FakePull(
        number: repo.pullCounter++,
        head: payload['source_branch'] as String,
        base: payload['target_branch'] as String,
      );
      repo.pulls.add(pull);
      return _json(_mrJson(pull), 201);
    }

    if (method == 'PUT' &&
        s.length == 3 &&
        s[0] == 'merge_requests' &&
        s[2] == 'merge') {
      final iid = int.tryParse(s[1]);
      for (final p in repo.pulls) {
        if (p.number != iid) continue;
        p.merged = true;
        repo.branches[p.base] = repo.resolveSha(p.head);
        if (payload['should_remove_source_branch'] == true) {
          repo.branches.remove(p.head);
        }
        return _json(_mrJson(p));
      }
      return _notFound();
    }

    return _notFound();
  }

  Map<String, Object?> _mrJson(FakePull p) => {
    // Het per-project oplopende iid, niet het globale id: daar werkt de rest
    // van de API mee.
    'iid': p.number,
    'id': 90000 + p.number,
    'web_url': 'https://gitlab.example/-/merge_requests/${p.number}',
    'state': p.merged ? 'merged' : 'opened',
    'source_branch': p.head,
    'target_branch': p.base,
  };

  @override
  void close() {}
}
