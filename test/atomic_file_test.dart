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

  group('writeBytesAtomicSyncRetrying', () {
    // De aanleiding: op Windows houdt een ánder proces een net gelezen bestand
    // nog even vast, waardoor zowel de rename als het verwijderen van het doel
    // faalt (errno 32). Het bijsnijdvenster verloor daar elke rotatie op —
    // geluidloos, want die schrijffout wordt bewust ingeslikt.
    test('een tijdelijke vergrendeling wordt uitgezeten', () {
      final temp = Directory.systemTemp.createTempSync('ocideck_retry_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final target = File(p.join(temp.path, 'out.bin'))
        ..writeAsStringSync('original');

      var renames = 0;
      final pauses = <Duration>[];
      writeBytesAtomicSyncRetrying(
        target,
        utf8.encode('replaced'),
        retryDelay: const Duration(milliseconds: 7),
        renameOnce: (tmp, destination) {
          renames++;
          // Twee keer bezet, daarna geeft de houder hem vrij.
          if (renames <= 2) {
            throw const FileSystemException('bezet door een ander proces');
          }
          tmp.renameSync(destination);
        },
        pause: pauses.add,
      );

      expect(target.readAsStringSync(), 'replaced');
      // Drie hernoemingen, twee pogingen: `writeBytesAtomicSync` probeert bij
      // een mislukte rename zélf nog eens ná het verwijderen van het doel, dus
      // de eerste poging verbruikt er twee.
      expect(renames, 3, reason: 'er is niet opnieuw geprobeerd');
      expect(pauses, [
        const Duration(milliseconds: 7),
      ], reason: 'er is niet tussen de pogingen gewacht');
      expect(temp.listSync().whereType<File>().length, 1);
    });

    test(
      'een blijvende vergrendeling gooit, zodat de aanroeper het kan melden',
      () {
        final temp = Directory.systemTemp.createTempSync('ocideck_retry_');
        addTearDown(() => temp.deleteSync(recursive: true));
        final target = File(p.join(temp.path, 'out.bin'))
          ..writeAsStringSync('original');

        var renames = 0;
        expect(
          () => writeBytesAtomicSyncRetrying(
            target,
            utf8.encode('replaced'),
            attempts: 3,
            renameOnce: (tmp, destination) {
              renames++;
              throw const FileSystemException('blijft bezet');
            },
            pause: (_) {},
          ),
          throwsA(isA<FileSystemException>()),
        );

        // Poging 1 verbruikt twee hernoemingen (rename, verwijder doel,
        // rename), poging 2 en 3 elk één: het doel bestaat dan niet meer, dus
        // de terugval slaat over.
        expect(renames, 4, reason: 'het aantal pogingen klopt niet');
        // Het doel is weg — dat is de prijs van verwijder-dan-hernoem — maar de
        // inhoud niet: het tijdelijke bestand van de poging die het doel
        // verwijderde blijft staan als herstelkopie. Zou die ook opgeruimd
        // worden, dan maakte een mislukte schrijfbeurt een bestaand bestand
        // leeg.
        expect(target.existsSync(), isFalse);
        final over = temp.listSync().whereType<File>().toList();
        expect(over.length, 1, reason: 'geen of te veel herstelkopieën');
        expect(over.single.path, endsWith('.tmp'));
        expect(over.single.readAsStringSync(), 'replaced');
      },
    );
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
