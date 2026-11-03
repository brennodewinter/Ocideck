// Desktop-versie van [RecordingStaging]: een map per sessie onder de
// app-supportmap, naast de herstelmap van [RecoveryService]. Audio is
// gevoeliger dan een platte tekst — op Linux krijgt de wortelmap daarom
// dezelfde `700`-hardening als de recoverymap.
//
// Niet de OS-temp, waar hij tot #2761 stond: een opname moet de zeven
// hersteldagen halen, en de temp haalt die niet. macOS' dirhelper wist
// `/var/folders/…/T` dagelijks voor alles ouder dan drie dagen, en op
// Linux is `/tmp` vaak tmpfs, die bij een herstart leeg is — precies na
// de vastgelopen call waarvoor het herstel bestaat. Een vergadering neem
// je niet opnieuw op.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/chmod.dart';
import '../../utils/log.dart';
import 'recording_staging_stub.dart';

// De interface hoort aan de publieke kant van de barrel: de conditionele
// export in recording_staging.dart kiest dit bestand, en zonder deze
// re-export is [RecordingStaging] daardoor onzichtbaar.
export 'recording_staging_stub.dart' show RecordingStaging;

/// Staging op het bestandssysteem:
/// `<support>/transcription/recordings/<sessie>/`. [baseDir] is de
/// testinjectie voor de wortel zelf; [supportDir] en [tempDir] vervangen
/// path_provider, zodat de verhuizing uit de oude tempwortel te toetsen is.
class IoRecordingStaging implements RecordingStaging {
  IoRecordingStaging({
    Directory? baseDir,
    Future<Directory> Function()? supportDir,
    Future<Directory> Function()? tempDir,
  }) : _resolveRoot = baseDir != null
           ? (() async => baseDir)
           : _supportRoot(
               supportDir ?? getApplicationSupportDirectory,
               tempDir ?? getTemporaryDirectory,
             );

  final Future<Directory> Function() _resolveRoot;

  /// De naam van de oude wortel onder de OS-temp (vóór #2761).
  static const legacyRootDirName = 'ocideck-recordings';

  /// De wortel onder app-support, één keer opgezocht. Die eerste keer neemt
  /// hij de sessies van een oude tempwortel over, zodat een update geen
  /// bewaarde opname kwijtraakt.
  static Future<Directory> Function() _supportRoot(
    Future<Directory> Function() support,
    Future<Directory> Function() temp,
  ) {
    Future<Directory>? once;
    return () => once ??= () async {
      final root = Directory(
        p.join((await support()).path, 'transcription', 'recordings'),
      );
      try {
        final legacy = Directory(
          p.join((await temp()).path, legacyRootDirName),
        );
        if (await legacy.exists()) await _adoptLegacy(legacy, root);
      } catch (e) {
        logWarning('RecordingStaging: oude tempstaging niet overgezet', e);
      }
      return root;
    }();
  }

  /// Verhuist elke sessiemap uit [legacy] naar [root]. Een `rename` waar dat
  /// kan; over een schijfgrens (tmpfs) kopiëren, mét wijzigingstijd, want de
  /// lijst sorteert daarop. Een map die al bestaat blijft liggen.
  static Future<void> _adoptLegacy(Directory legacy, Directory root) async {
    await _ensureRoot(root);
    await for (final entity in legacy.list()) {
      if (entity is! Directory) continue;
      final target = Directory(p.join(root.path, p.basename(entity.path)));
      if (await target.exists()) continue;
      try {
        await entity.rename(target.path);
      } on FileSystemException {
        await target.create();
        await for (final file in entity.list()) {
          if (file is! File) continue;
          final copy = await file.copy(
            p.join(target.path, p.basename(file.path)),
          );
          await copy.setLastModified(await file.lastModified());
        }
        await entity.delete(recursive: true);
      }
    }
    await legacy.delete();
  }

  static Future<void> _ensureRoot(Directory root) async {
    if (root.existsSync()) return;
    await root.create(recursive: true);
    if (Platform.isLinux && !await chmodPath('700', root.path)) {
      throw const FileSystemException(
        'Opname-staging kon niet op eigenaar-alleen worden gezet',
      );
    }
  }

  Future<Directory> _root() async {
    final root = await _resolveRoot();
    await _ensureRoot(root);
    return root;
  }

  @override
  Future<String?> createSessionDir() async {
    final root = await _root();
    // Milliseconde + teller: uniek genoeg voor een app die nooit twee
    // sessies tegelijk heeft (RecordingManager dwingt dat af).
    var name = DateTime.now().millisecondsSinceEpoch.toString();
    var dir = Directory(p.join(root.path, name));
    var n = 0;
    while (dir.existsSync()) {
      n++;
      dir = Directory(p.join(root.path, '$name-$n'));
    }
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<void> discardDir(String? dir) async {
    if (dir == null) return;
    final d = Directory(dir);
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      logWarning('RecordingStaging.discardDir: $dir', e);
    }
  }

  @override
  Future<void> sweep({required Duration maxAge}) async {
    final root = await _resolveRoot();
    if (!root.existsSync()) return;
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in root.list()) {
      try {
        if (entity is! Directory) continue;
        // De leeftijd zit in de naam (`<millis>` of `<millis>-<n>`), niet in
        // de ctime — die laat zich niet aanzetten en is daarom niet te
        // testen. Een vreemde naam levert geen leeftijd en blijft liggen.
        final millis = int.tryParse(p.basename(entity.path).split('-').first);
        if (millis == null) continue;
        final created = DateTime.fromMillisecondsSinceEpoch(millis);
        if (created.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } catch (e) {
        // Eén weerbarstige map mag de rest van de veeg niet blokkeren.
        logWarning('RecordingStaging.sweep: ${entity.path}', e);
      }
    }
  }

  @override
  Future<List<String>> listSessionDirs() async {
    final root = await _resolveRoot();
    if (!root.existsSync()) return const [];
    final dirs = <String>[];
    await for (final entity in root.list()) {
      if (entity is Directory) dirs.add(entity.path);
    }
    return dirs;
  }

  @override
  Future<void> discardAll() async {
    final root = await _resolveRoot();
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (e) {
      logWarning('RecordingStaging.discardAll', e);
    }
  }
}

RecordingStaging createRecordingStaging() => IoRecordingStaging();
