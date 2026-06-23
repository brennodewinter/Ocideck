import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/atomic_file.dart';
import 'package:path/path.dart' as p;

void main() {
  test('writeStringAtomic creates the file with exact content', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_atomic_');
    addTearDown(() => temp.delete(recursive: true));
    final target = File(p.join(temp.path, 'out.txt'));

    await writeStringAtomic(target, 'hello wörld');

    expect(await target.readAsString(), 'hello wörld');
    // No temp sibling is left behind.
    expect(await File('${target.path}.tmp').exists(), isFalse);
  });

  test('writeStringAtomic overwrites an existing file atomically', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_atomic_');
    addTearDown(() => temp.delete(recursive: true));
    final target = File(p.join(temp.path, 'out.txt'));
    await target.writeAsString('original');

    await writeStringAtomic(target, 'replaced');

    expect(await target.readAsString(), 'replaced');
    expect(await File('${target.path}.tmp').exists(), isFalse);
  });

  test('on failure the original is intact and no temp file lingers', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_atomic_');
    addTearDown(() => temp.delete(recursive: true));
    // A directory at the target path makes the final rename fail: the helper
    // must rethrow, leave the directory ("original") untouched, and clean up
    // the temp file it wrote.
    final target = Directory(p.join(temp.path, 'target'));
    await target.create();

    await expectLater(
      writeStringAtomic(File(target.path), 'x'),
      throwsA(isA<FileSystemException>()),
    );

    expect(await target.exists(), isTrue);
    expect(await File('${target.path}.tmp').exists(), isFalse);
  });
}
