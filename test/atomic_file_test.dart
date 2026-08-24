import 'dart:convert';
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

  group('writeBytesAtomicSync', () {
    // De sync-variant draagt dezelfde belofte als de async: hij overschrijft
    // een bestaand doel. Op POSIX doet `rename` dat zelf; op Windows faalt hij
    // en is de terugval (verwijder-dan-hernoem) het enige wat de belofte
    // waarmaakt. Die terugval ontbrak, en omdat de enige aanroeper
    // (het bijsnijdvenster) schrijffouten inslikt, verdween een rotatie daar
    // op Windows spoorloos.
    test('overwrites an existing file', () {
      final temp = Directory.systemTemp.createTempSync('ocideck_atomic_sync_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final target = File(p.join(temp.path, 'out.bin'))
        ..writeAsStringSync('original');

      writeBytesAtomicSync(target, utf8.encode('replaced'));

      expect(target.readAsStringSync(), 'replaced');
      expect(temp.listSync().whereType<File>().length, 1);
    });

    test('a failing rename onto an existing target falls back', () {
      final temp = Directory.systemTemp.createTempSync('ocideck_atomic_sync_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final target = File(p.join(temp.path, 'out.bin'))
        ..writeAsStringSync('original');

      // Windows-nabootsing: de eerste hernoeming faalt zoals daar over een
      // bestaand bestand, de tweede (na het verwijderen) doet het echte werk.
      // Zonder deze injectie kan geen enkele POSIX-machine deze tak halen.
      var renames = 0;
      writeBytesAtomicSync(
        target,
        utf8.encode('replaced'),
        renameOnce: (tmp, destination) {
          renames++;
          if (renames == 1) {
            throw const FileSystemException(
              'rename onto an existing file fails on Windows',
            );
          }
          tmp.renameSync(destination);
        },
      );

      expect(renames, 2, reason: 'de terugval hernoemde niet opnieuw');
      expect(target.readAsStringSync(), 'replaced');
      expect(
        temp.listSync().whereType<File>().length,
        1,
        reason: 'er bleef een .tmp achter',
      );
    });

    test('a failing rename without a target rethrows and cleans up', () {
      final temp = Directory.systemTemp.createTempSync('ocideck_atomic_sync_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final target = File(p.join(temp.path, 'afwezig.bin'));

      expect(
        () => writeBytesAtomicSync(
          target,
          utf8.encode('x'),
          renameOnce: (tmp, destination) =>
              throw const FileSystemException('rename mislukt'),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(target.existsSync(), isFalse);
      expect(temp.listSync(), isEmpty, reason: 'er bleef een .tmp achter');
    });
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
