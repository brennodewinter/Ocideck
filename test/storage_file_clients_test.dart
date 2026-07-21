import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/presentation_search/storage_file_clients.dart';
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/services/webdav_service.dart';

/// De listing die beide adapters moeten vertalen: een map, een los `.md` en een
/// pakket.
const _names = [
  ('map', 'map', true),
  ('deck.md', 'map/deck.md', false),
  ('pak.ocideck', 'pak.ocideck', false),
];

class _FakeWebdav implements WebdavService {
  @override
  Future<List<WebdavEntry>> list(String remotePath) async => [
    for (final (name, path, isDir) in _names)
      WebdavEntry(name: name, relativePath: path, isCollection: isDir),
  ];

  @override
  Future<WebdavFile> download(String remotePath, {int maxBytes = 0}) async =>
      WebdavFile(Uint8List.fromList([1, 2, 3]), null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeS3 implements S3Service {
  @override
  Future<List<S3Entry>> list(String remotePath) async => [
    for (final (name, path, isDir) in _names)
      S3Entry(name: name, relativePath: path, isCollection: isDir),
  ];

  @override
  Future<S3File> download(String remotePath, {int maxBytes = 0}) async =>
      S3File(Uint8List.fromList([4, 5, 6]), null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('WebdavFileClient vertaalt map, markdown en pakket', () async {
    final client = WebdavFileClient(_FakeWebdav());

    final entries = await client.list('');

    expect(entries.map((e) => e.path).toList(), [
      'map',
      'map/deck.md',
      'pak.ocideck',
    ]);
    expect(entries[0].isDirectory, isTrue);
    expect(entries[1].isMarkdown, isTrue);
    expect(entries[1].isPackage, isFalse);
    expect(entries[2].isPackage, isTrue);
    expect(await client.download('x'), [1, 2, 3]);
  });

  test('S3FileClient vertaalt map, markdown en pakket', () async {
    final client = S3FileClient(_FakeS3());

    final entries = await client.list('');

    expect(entries.map((e) => e.path).toList(), [
      'map',
      'map/deck.md',
      'pak.ocideck',
    ]);
    expect(entries[0].isDirectory, isTrue);
    expect(entries[1].isMarkdown, isTrue);
    expect(entries[2].isPackage, isTrue);
    expect(await client.download('x'), [4, 5, 6]);
  });
}
