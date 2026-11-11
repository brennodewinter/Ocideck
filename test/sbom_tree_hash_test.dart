import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../tool/sbom_build.dart';

void main() {
  late Directory temporary;
  setUp(() => temporary = Directory.systemTemp.createTempSync('sbom_links_'));
  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'native symlinks and Git Windows placeholder files hash identically',
    () {
      final native = Directory(p.join(temporary.path, 'native'))..createSync();
      final windows = Directory(p.join(temporary.path, 'windows'))
        ..createSync();
      for (final dir in [native, windows]) {
        File(p.join(dir.path, 'source.dart')).writeAsStringSync('source');
      }
      Link(p.join(native.path, 'alias.dart')).createSync('source.dart');
      File(p.join(windows.path, 'alias.dart')).writeAsStringSync('source.dart');
      expect(forkTreeHash(native), forkTreeHash(windows));

      Link(p.join(native.path, 'alias.dart')).updateSync('different.dart');
      expect(forkTreeHash(native), isNot(forkTreeHash(windows)));
    },
    skip: Platform.isWindows
        ? 'Creating native links needs Windows privilege'
        : false,
  );

  test(
    'a link outside the fork records its target without reading outside bytes',
    () {
      final root = Directory(p.join(temporary.path, 'fork'))..createSync();
      final outside = File(p.join(temporary.path, 'outside.txt'))
        ..writeAsStringSync('private original');
      Link(p.join(root.path, 'alias')).createSync('../outside.txt');
      final before = forkTreeHash(root);
      outside.writeAsStringSync('private changed');
      expect(forkTreeHash(root), before);
      Link(p.join(root.path, 'alias')).deleteSync();
      expect(forkTreeHash(root), isNot(before));
    },
    skip: Platform.isWindows
        ? 'Creating native links needs Windows privilege'
        : false,
  );

  test('ordinary source changes count and hidden build files do not', () {
    final root = Directory(p.join(temporary.path, 'fork'))..createSync();
    final source = File(p.join(root.path, 'source.dart'))
      ..writeAsStringSync('a');
    final before = forkTreeHash(root);
    final cache = Directory(p.join(root.path, '.dart_tool'))..createSync();
    File(p.join(cache.path, 'cache')).writeAsStringSync('machine-specific');
    expect(forkTreeHash(root), before);
    source.writeAsStringSync('b');
    expect(forkTreeHash(root), isNot(before));
  });
}
