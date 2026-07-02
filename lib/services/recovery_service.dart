import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

/// Eén automatisch bewaard herstelbestand voor een (nog) niet-opgeslagen deck.
class RecoverySnapshot {
  final String id;
  final DateTime savedAt;
  final String? filePath;
  final String label;
  final String markdown;

  /// JSON payload from [UserNotesCodec.encode], when the deck has user notes.
  final String? userNotes;

  const RecoverySnapshot({
    required this.id,
    required this.savedAt,
    required this.filePath,
    required this.label,
    required this.markdown,
    this.userNotes,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'savedAt': savedAt.toIso8601String(),
    'filePath': filePath,
    'label': label,
    'markdown': markdown,
    if (userNotes != null) 'userNotes': userNotes,
  };

  static RecoverySnapshot fromJson(Map<String, Object?> json) {
    return RecoverySnapshot(
      id: json['id'] as String,
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      filePath: json['filePath'] as String?,
      label: (json['label'] as String?) ?? 'Presentatie',
      markdown: (json['markdown'] as String?) ?? '',
      userNotes: json['userNotes'] as String?,
    );
  }
}

/// Schrijft en leest autosave-herstelbestanden. Elk dirty tabblad krijgt een
/// eigen `<id>.json` in de herstelmap; bij opslaan/sluiten wordt het gewist,
/// zodat resterende bestanden bij de volgende start op niet-opgeslagen werk
/// (een crash) wijzen.
class RecoveryService {
  /// Tests injecteren een tijdelijke map; in productie wordt de app-support-map
  /// gebruikt (path_provider).
  final Future<Directory> Function() _resolveDir;

  RecoveryService({Directory? baseDir})
    : _resolveDir = baseDir != null ? (() async => baseDir) : _defaultDir;

  static Future<Directory> _defaultDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'recovery'));
  }

  Future<Directory> _dir() async {
    final dir = await _resolveDir();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String id) => File(p.join(dir.path, '$id.json'));

  /// Per-id operation chains. The periodic autosave tick (`save`) and the
  /// "tab became clean" listener (`discard`) fire independently for the same
  /// id; without ordering, a save that was already in flight could land *after*
  /// a discard and leave a stale recovery file that falsely prompts to restore
  /// already-saved work. Serialising per id makes the later call win.
  final Map<String, Future<void>> _chains = {};

  Future<void> _enqueue(String id, Future<void> Function() op) {
    final next = (_chains[id] ?? Future<void>.value()).then((_) => op());
    _chains[id] = next;
    next.whenComplete(() {
      if (_chains[id] == next) _chains.remove(id);
    });
    return next;
  }

  Future<void> save(RecoverySnapshot snapshot) {
    return _enqueue(snapshot.id, () async {
      try {
        final dir = await _dir();
        await _file(
          dir,
          snapshot.id,
        ).writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      } catch (e) {
        logWarning('RecoveryService.save: write recovery snapshot', e);
        // Autosave mag nooit de app verstoren.
      }
    });
  }

  Future<void> discard(String id) {
    return _enqueue(id, () async {
      try {
        final file = _file(await _dir(), id);
        if (file.existsSync()) await file.delete();
      } catch (e) {
        logWarning('RecoveryService.discard: delete recovery file', e);
      }
    });
  }

  /// Recovery snapshots hold full deck markdown (and notes) in plaintext, so an
  /// orphaned one — left by a crash the user never followed up on — is a slow
  /// leak of possibly-classified content on disk. Cap how long that can linger.
  static const Duration defaultMaxAge = Duration(days: 30);

  /// Delete recovery files last modified more than [maxAge] ago. Best-effort:
  /// failures are logged, never thrown. Returns the number of files removed.
  Future<int> pruneOlderThan(Duration maxAge) async {
    var removed = 0;
    try {
      final dir = await _dir();
      final now = DateTime.now();
      for (final entry in dir.listSync()) {
        if (entry is! File || !entry.path.endsWith('.json')) continue;
        try {
          final age = now.difference(entry.statSync().modified);
          if (age > maxAge) {
            await entry.delete();
            removed++;
          }
        } catch (e) {
          logWarning('RecoveryService.pruneOlderThan: stat/delete', e);
        }
      }
    } catch (e) {
      logWarning('RecoveryService.pruneOlderThan: list recovery dir', e);
    }
    return removed;
  }

  Future<List<RecoverySnapshot>> loadAll() async {
    // Bound plaintext residue: drop stale orphans before offering the rest.
    await pruneOlderThan(defaultMaxAge);
    try {
      final dir = await _dir();
      final out = <RecoverySnapshot>[];
      for (final entry in dir.listSync()) {
        if (entry is File && entry.path.endsWith('.json')) {
          try {
            final data = jsonDecode(await entry.readAsString());
            if (data is! Map) {
              throw const FormatException('Recovery snapshot is not a map');
            }
            out.add(RecoverySnapshot.fromJson(Map<String, Object?>.from(data)));
          } catch (e, s) {
            logError('RecoveryService.loadAll: decode recovery snapshot', e, s);
          }
        }
      }
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (e) {
      logWarning('RecoveryService.loadAll: list recovery dir', e);
      return const [];
    }
  }

  Future<void> clearAll() async {
    try {
      final dir = await _dir();
      for (final entry in dir.listSync()) {
        if (entry is File && entry.path.endsWith('.json')) {
          try {
            await entry.delete();
          } catch (e) {
            logWarning('RecoveryService.clearAll: delete recovery file', e);
          }
        }
      }
    } catch (e) {
      logWarning('RecoveryService.clearAll: list recovery dir', e);
    }
  }
}

final recoveryServiceProvider = Provider<RecoveryService>(
  (_) => RecoveryService(),
);
