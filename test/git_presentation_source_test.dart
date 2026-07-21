import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/presentation_search/git_presentation_source.dart';

/// Een GitForge die een vaste set deckmappen onder `decks/` en hun `deck.md`
/// bedient; elke andere forge-methode gooit via noSuchMethod (niet gebruikt).
class _FakeForge implements GitForge {
  _FakeForge(this.dirs, this.blobs);

  /// Deckmap-paden zoals `decks/alpha`.
  final List<String> dirs;

  /// Pad → bytes, bijv. `decks/alpha/deck.md`.
  final Map<String, Uint8List> blobs;

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) async => [
    for (final d in dirs) RepoEntry(path: d, type: RepoEntryType.dir, sha: d),
  ];

  @override
  Future<Uint8List> readBlob(String ref, String path) async {
    final b = blobs[path];
    if (b == null) {
      throw const GitForgeException(GitForgeError.notFound, 'ontbreekt');
    }
    return b;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FileService _fileService() => FileService(
  MarkdownService(),
  ImageService(),
  () => const ThemeProfile(),
  homeDirectory: () => null,
);

const _config = GitRepoConfig(
  baseUrl: 'https://git.example',
  owner: 'team',
  repo: 'presentaties',
);

Uint8List _deckMd(String title, String heading) => Uint8List.fromList(
  utf8.encode(
    '---\nmarp: true\ntheme: ocideck\ntitle: $title\n---\n\n'
    '# $heading\n\n- punt\n',
  ),
);

GitPresentationSource _source(_FakeForge forge) => GitPresentationSource(
  forge: forge,
  config: _config,
  fileService: _fileService(),
  label: 'Git: test',
);

void main() {
  test('scan levert één presentatie per deck met geparsede inhoud', () async {
    final forge = _FakeForge(
      ['decks/alpha', 'decks/beta'],
      {
        'decks/alpha/deck.md': _deckMd('Alpha', 'Sleutelbeheer'),
        'decks/beta/deck.md': _deckMd('Beta', 'Netwerksegmentatie'),
      },
    );

    final results = await _source(forge).scan();

    expect(results.length, 2);
    expect(results.map((r) => r.deck.title).toSet(), {'Alpha', 'Beta'});
    // Remote decks dragen geen lokale projectmap, zodat mem:-beeld heel blijft.
    expect(results.every((r) => r.deck.projectPath == null), isTrue);
    expect(results.map((r) => r.path).toSet(), {
      'git:team/presentaties/decks/alpha',
      'git:team/presentaties/decks/beta',
    });
  });

  test('scan slaat een onleesbaar deck over in plaats van te falen', () async {
    final forge = _FakeForge(
      ['decks/alpha', 'decks/kapot'],
      // decks/kapot/deck.md ontbreekt → readBlob gooit → deck overgeslagen.
      {'decks/alpha/deck.md': _deckMd('Alpha', 'Sleutelbeheer')},
    );

    final results = await _source(forge).scan();

    expect(results.length, 1);
    expect(results.single.deck.title, 'Alpha');
  });

  test('scan weigert inhoud die geen marp-presentatie is', () async {
    final forge = _FakeForge(
      ['decks/alpha'],
      {
        'decks/alpha/deck.md': Uint8List.fromList(
          utf8.encode('# Zomaar tekst, geen front matter\n'),
        ),
      },
    );

    final results = await _source(forge).scan();

    expect(results, isEmpty);
  });
}
