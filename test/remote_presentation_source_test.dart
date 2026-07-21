import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/presentation_search/remote_file_client.dart';
import 'package:ocideck/services/presentation_search/remote_presentation_source.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// Een remote opslag in het geheugen: een mappenboom plus de bytes per pad.
class _FakeClient implements RemoteFileClient {
  _FakeClient(this.tree, this.files);

  /// Mappad → items in die map (niet-recursief), zoals list() teruggeeft.
  final Map<String, List<RemoteFileEntry>> tree;
  final Map<String, Uint8List> files;

  @override
  Future<List<RemoteFileEntry>> list(String path) async =>
      tree[path] ?? const [];

  @override
  Future<Uint8List> download(String path) async {
    final bytes = files[path];
    if (bytes == null) throw StateError('ontbreekt: $path');
    return bytes;
  }
}

RemoteFileEntry _dir(String path) => RemoteFileEntry(
  path: path,
  name: path.split('/').last,
  isDirectory: true,
  isMarkdown: false,
  isPackage: false,
);

RemoteFileEntry _md(String path) => RemoteFileEntry(
  path: path,
  name: path.split('/').last,
  isDirectory: false,
  isMarkdown: true,
  isPackage: false,
);

RemoteFileEntry _pkg(String path) => RemoteFileEntry(
  path: path,
  name: path.split('/').last,
  isDirectory: false,
  isMarkdown: false,
  isPackage: true,
);

/// Een geldige PNG-signatuur plus wat vulling — genoeg voor de magic-bytes
/// controle van [ImageService.looksLikeImage].
Uint8List _png() => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
]);

Uint8List _deckMarkdown(String title, String body) => Uint8List.fromList(
  utf8.encode('---\nmarp: true\ntheme: ocideck\ntitle: $title\n---\n\n$body'),
);

/// Bouw een `.ocideck`-pakket met een deck.md en één afbeelding.
Uint8List _package() {
  final archive = Archive();
  final md = _deckMarkdown(
    'Pakket Deck',
    '# Pakketdia\n\n![bg](images/pic.png)\n',
  );
  archive.add(ArchiveFile('deck.md', md.length, md));
  final png = _png();
  archive.add(ArchiveFile('images/pic.png', png.length, png));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

FileService _fileService() => FileService(
  MarkdownService(),
  ImageService(),
  () => const ThemeProfile(),
  homeDirectory: () => null,
);

RemotePresentationSource _source(_FakeClient client) =>
    RemotePresentationSource(
      client: client,
      fileService: _fileService(),
      label: 'WebDAV: test',
      pathPrefix: 'webdav:c1',
    );

void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  test('leest een los .md en haalt zijn afbeelding op als mem:', () async {
    final client = _FakeClient(
      {
        '': [_md('deck.md')],
      },
      {
        'deck.md': _deckMarkdown(
          'Los Deck',
          '# Losse dia\n\n![bg](images/pic.png)\n',
        ),
        'images/pic.png': _png(),
      },
    );

    final results = await _source(client).scan();

    expect(results.length, 1);
    final deck = results.single.deck;
    expect(deck.title, 'Los Deck');
    expect(results.single.path, 'webdav:c1/deck.md');
    // De afbeelding is opgehaald en als in-geheugen pad aangehaakt.
    final withImage = deck.slides.firstWhere((s) => s.imagePath.isNotEmpty);
    expect(WebAssetStore.isMemPath(withImage.imagePath), isTrue);
    expect(WebAssetStore.bytesFor(withImage.imagePath), _png());
  });

  test(
    'pakt een .ocideck-pakket in het geheugen uit, mét afbeelding',
    () async {
      final client = _FakeClient(
        {
          '': [_pkg('deck.ocideck')],
        },
        {'deck.ocideck': _package()},
      );

      final results = await _source(client).scan();

      expect(results.length, 1);
      final deck = results.single.deck;
      expect(deck.title, 'Pakket Deck');
      final withImage = deck.slides.firstWhere((s) => s.imagePath.isNotEmpty);
      expect(WebAssetStore.isMemPath(withImage.imagePath), isTrue);
      expect(WebAssetStore.bytesFor(withImage.imagePath), _png());
    },
  );

  test('neemt presentaties uit submappen mee', () async {
    final client = _FakeClient(
      {
        '': [_dir('klant')],
        'klant': [_dir('klant/2026'), _md('klant/top.md')],
        'klant/2026': [_md('klant/2026/diep.md')],
      },
      {
        'klant/top.md': _deckMarkdown('Top', '# Boven\n'),
        'klant/2026/diep.md': _deckMarkdown('Diep', '# Onder\n'),
      },
    );

    final results = await _source(client).scan();

    expect(results.map((r) => r.deck.title).toSet(), {'Top', 'Diep'});
  });

  test(
    'slaat een onleesbaar bestand over zonder de scan te laten falen',
    () async {
      final client = _FakeClient(
        {
          '': [_md('goed.md'), _md('weg.md')],
        },
        // weg.md ontbreekt in files → download gooit → alleen goed.md blijft over.
        {'goed.md': _deckMarkdown('Goed', '# Werkt\n')},
      );

      final results = await _source(client).scan();

      expect(results.length, 1);
      expect(results.single.deck.title, 'Goed');
    },
  );
}
