import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/git_settings.dart';
import '../../utils/atomic_file.dart';
import 'draft_store.dart';

/// De werkkopie op desktop: echte bestanden onder de app-support-map, in exact
/// de repo-layout van §6 — want dat ís de repo, zodra Fase 3 er een clone van
/// maakt.
DraftStore createDraftStore({String scope = ''}) =>
    FileDraftStore(scope: scope);

class FileDraftStore implements DraftStore {
  /// [scope] is `GitRepoConfig.storageSlug`: de werkkopie van elke repo krijgt
  /// een eigen submap. Zonder dat deelden twee repo's met een gelijknamig deck
  /// dezelfde bestanden. Genegeerd wanneer [baseDir] wordt meegegeven — dan is
  /// de map al gekozen (de native mirror doet dat, en die scoopt zelf al).
  FileDraftStore({Directory? baseDir, String scope = ''})
    : _scope = baseDir != null ? '' : scope,
      _resolveDir = baseDir != null
          ? (() async => baseDir)
          : (() => _defaultDir(scope));

  /// Leeg wanneer de map van buiten kwam: dan scoopt de aanroeper al.
  final String _scope;

  final Future<Directory> Function() _resolveDir;
  Directory? _cached;

  static Future<Directory> _defaultDir(String scope) async {
    final support = await getApplicationSupportDirectory();
    final root = p.join(support.path, 'git_mirror');
    return Directory(scope.isEmpty ? root : p.join(root, scope));
  }

  @override
  bool get isDurable => true;

  /// De oude, ongescopede werkkopie lag rechtstreeks in `git_mirror/`. Verhuis
  /// wat daar los staat naar de submap van deze repo. Mappen die zelf een scope
  /// zijn blijven staan — die horen al bij iemand.
  ///
  /// Alleen zinvol wanneer deze store zijn eigen map koos; kreeg hij er een
  /// mee ([_scope] leeg), dan is er niets te verhuizen.
  @override
  Future<int> adoptLegacyEntries() async {
    final scope = _scope;
    if (scope.isEmpty) return 0;
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'git_mirror'));
    if (!await root.exists()) return 0;
    final target = await _base();
    var moved = 0;
    await for (final entity in root.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name == scope) continue; // de eigen submap
      if (entity is! Directory) continue;
      // Een deckmap heet `decks`; alles daarbuiten is een andere scope of iets
      // wat wij niet hebben neergezet, en blijft met rust.
      if (name != GitRepoLayout.decksRoot) continue;
      final dest = Directory(p.join(target.path, name));
      if (await dest.exists()) continue; // nieuwe werkkopie wint
      await entity.rename(dest.path);
      moved++;
    }
    return moved;
  }

  Future<Directory> _base() async {
    final hit = _cached;
    if (hit != null) return hit;
    final dir = await _resolveDir();
    await dir.create(recursive: true);
    _cached = dir;
    return dir;
  }

  /// Het absolute pad voor een repo-relatief pad, of null wanneer het buiten de
  /// wortel zou vallen. Laatste vangnet: de aanroeper heeft al gecontroleerd,
  /// maar hier gaan echte bytes naar een echt bestandssysteem.
  Future<String?> _absolute(String repoPath) async {
    if (!GitRepoLayout.isSafeRepoPath(repoPath)) return null;
    final base = await _base();
    final abs = p.normalize(p.join(base.path, repoPath));
    if (!p.isWithin(base.path, abs)) return null;
    return abs;
  }

  @override
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files) async {
    // Eerst alle paden oplossen, dan pas schrijven: een deck half wegschrijven
    // en dan stranden op één slecht pad is erger dan niets schrijven.
    final targets = <String, Uint8List>{};
    for (final entry in files.entries) {
      final abs = await _absolute(entry.key);
      if (abs == null) {
        throw DraftStoreUnsupported('Onveilig pad: ${entry.key}');
      }
      targets[abs] = entry.value;
    }
    // Vervang de map in z'n geheel: een lid dat in deze versie niet meer bestaat
    // hoort ook niet meer op schijf te staan, anders zou een verwijderde slide
    // z'n asset laten rondslingeren.
    await discardDeck(deckDir);
    for (final entry in targets.entries) {
      final file = File(entry.key);
      await file.parent.create(recursive: true);
      await writeBytesAtomic(file, entry.value);
    }
  }

  @override
  Future<Map<String, Uint8List>> readDeck(String deckDir) async {
    final abs = await _absolute(deckDir);
    if (abs == null) return {};
    final dir = Directory(abs);
    if (!await dir.exists()) return {};

    final base = await _base();
    final out = <String, Uint8List>{};
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: base.path);
      out[p.posix.joinAll(p.split(rel))] = await entity.readAsBytes();
    }
    return out;
  }

  @override
  Future<bool> hasDeck(String deckDir) async {
    final abs = await _absolute(deckDir);
    if (abs == null) return false;
    return Directory(abs).exists();
  }

  @override
  Future<void> discardDeck(String deckDir) async {
    final abs = await _absolute(deckDir);
    if (abs == null) return;
    final dir = Directory(abs);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<List<String>> deckDirs() async {
    final base = await _base();
    final decks = Directory(p.join(base.path, GitRepoLayout.decksRoot));
    if (!await decks.exists()) return [];
    final out = <String>[];
    await for (final entity in decks.list()) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      final dir = GitRepoLayout.deckDir(name);
      if (dir != null) out.add(dir);
    }
    out.sort();
    return out;
  }
}
