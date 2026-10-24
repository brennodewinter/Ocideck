// Desktop-versie van [RecordingStaging]: een map per sessie onder de
// OS-temp, vergelijkbaar met hoe [RecoveryService] zijn herstelmap onder
// de support-directory houdt. Audio is gevoeliger dan een platte tekst —
// op Linux krijgt de wortelmap daarom dezelfde `700`-hardening als de
// recoverymap, want temp is op veel opstellingen voor iedereen leesbaar.
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

/// Staging op het bestandssysteem: `<temp>/ocideck-recordings/<sessie>/`.
/// [baseDir] is de testinjectie — productie laat hem op de echte tempmap
/// staan.
class IoRecordingStaging implements RecordingStaging {
  IoRecordingStaging({Directory? baseDir})
    : _resolveRoot = baseDir != null ? (() async => baseDir) : _defaultRoot;

  final Future<Directory> Function() _resolveRoot;

  static const rootDirName = 'ocideck-recordings';

  static Future<Directory> _defaultRoot() async {
    final temp = await getTemporaryDirectory();
    return Directory(p.join(temp.path, rootDirName));
  }

  Future<Directory> _root() async {
    final root = await _resolveRoot();
    if (!root.existsSync()) {
      await root.create(recursive: true);
      if (Platform.isLinux && !await chmodPath('700', root.path)) {
        throw const FileSystemException(
          'Opname-staging kon niet op eigenaar-alleen worden gezet',
        );
      }
    }
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
