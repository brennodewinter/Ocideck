import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';

/// A package import must bound how much a single entry can inflate, so a
/// highly-compressible "zip bomb" entry can't exhaust memory. The extraction
/// is capped at `maxBytes`; an entry that would blow past it aborts the import.
void main() {
  late Directory tmp;
  late FileService file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocideck_bomb_');
    file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Uint8List zipOf(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('a large highly-compressible entry is refused, not inflated', () async {
    // 8 MiB of zeros compresses to a few KB but would inflate past a 1 MiB cap.
    final bomb = Uint8List(8 * 1024 * 1024);
    final bytes = zipOf({
      'deck.md': '# Hi\n'.codeUnits,
      'big.bin': bomb,
    });
    expect(bytes.length, lessThan(1024 * 1024), reason: 'bomb must be tiny');

    final result = await file.importPackageBytes(
      bytes,
      tmp.path,
      maxBytes: 1024 * 1024, // 1 MiB budget
    );
    expect(result, isNull, reason: 'oversized inflation must be refused');
  });

  test('a normal package within budget still imports', () async {
    final bytes = zipOf({
      'deck.md': '# Hallo wereld\n\n- punt\n'.codeUnits,
    });
    final result = await file.importPackageBytes(
      bytes,
      tmp.path,
      maxBytes: 1024 * 1024,
    );
    expect(result, isNotNull);
    expect(File(result!).existsSync(), isTrue);
  });
}
