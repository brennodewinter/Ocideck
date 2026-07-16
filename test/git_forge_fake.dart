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
  FakeRepo({required this.branches, required this.files});

  /// Branch or tag name to commit sha.
  final Map<String, String> branches;

  /// Repo-relative path to blob bytes.
  final Map<String, Uint8List> files;

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
    if (segments.isEmpty) return _notFound();

    if (segments.first == 'branches') {
      final branch = segments.skip(1).join('/');
      final sha = repo.branches[branch];
      if (sha == null) return _notFound();
      return _json({
        'name': branch,
        'commit': {'id': sha},
      });
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

  GitResponse _json(Object? body, [int status = 200]) =>
      GitResponse(status, Uint8List.fromList(utf8.encode(jsonEncode(body))));

  GitResponse _notFound() => _json({'message': 'Not Found'}, 404);

  @override
  void close() => closed = true;
}
