import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/atomic_file.dart';
import '../utils/log.dart';

/// Verplaatst presentatiebestanden naar de prullenbak van het OS — nooit hard
/// verwijderen, in lijn met de fail-safe-lijn van de app. macOS: `~/.Trash`;
/// Linux: de XDG-prullenbak (`Trash/files` + `.trashinfo`). Op Windows en web
/// is er geen veilig equivalent zonder platformcode: [isSupported] is daar
/// false en de UI verbergt de opruimactie.
class TrashService {
  final String? Function() _osHome;

  TrashService({String? Function()? osHome}) : _osHome = osHome ?? _defaultHome;

  static String? _defaultHome() =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  bool get isSupported => _trashFilesDir() != null;

  /// De map waarin verwijderde items belanden, of null op een platform
  /// zonder ondersteunde prullenbak.
  String? _trashFilesDir() {
    final home = _osHome();
    if (home == null || home.trim().isEmpty) return null;
    if (Platform.isMacOS) return p.join(home, '.Trash');
    if (Platform.isLinux) {
      final data =
          Platform.environment['XDG_DATA_HOME'] ??
          p.join(home, '.local', 'share');
      return p.join(data, 'Trash', 'files');
    }
    return null;
  }

  /// Wat er voor het deck op [mdPath] de prullenbak in gaat: de hele
  /// projectmap wanneer die — zoals bij imports — naar het deck is vernoemd
  /// (`Demo/` of `Demo (2)/` bij `Demo.md`), anders alleen het bestand plus
  /// zijn sidecars (aantekeningen, notities). Zo verdwijnen geen bestanden
  /// van andere decks die toevallig in dezelfde map staan.
  static List<String> trashTargetsFor(String mdPath) {
    final dir = p.dirname(mdPath);
    final base = p.basenameWithoutExtension(mdPath);
    final dirName = p.basename(dir);
    final ownFolder = RegExp(
      '^${RegExp.escape(base)}( \\(\\d+\\))?\$',
    ).hasMatch(dirName);
    if (ownFolder) return [dir];

    final targets = [mdPath];
    for (final ext in const ['.ink.json', '.user-notes.json', '.miauw.json']) {
      final sidecar = p.setExtension(mdPath, ext);
      if (File(sidecar).existsSync()) targets.add(sidecar);
    }
    return targets;
  }

  /// Verplaats het deck op [mdPath] (bestand + sidecars, of zijn eigen
  /// projectmap — zie [trashTargetsFor]) naar de prullenbak. Geeft true
  /// wanneer alles is verplaatst.
  Future<bool> moveToTrash(String mdPath) async {
    final trashDir = _trashFilesDir();
    if (trashDir == null) return false;
    try {
      await Directory(trashDir).create(recursive: true);
      // Doorgaan na een mislukking, niet meteen terugkeren. `trashTargetsFor`
      // zet de `.md` vooraan en de sidecars (inkt, notities) erachter; brak het
      // hier af, dan lag het deck in de prullenbak terwijl zijn sidecars in de
      // oude map achterbleven — verweesd én onzichtbaar, want er verwijst geen
      // `.md` meer naar. De uitkomst blijft `false`, dus de aanroeper meldt nog
      // steeds dat het niet volledig is gelukt.
      var allMoved = true;
      for (final target in trashTargetsFor(mdPath)) {
        if (!await _moveOne(target, trashDir)) allMoved = false;
      }
      return allMoved;
    } catch (e, s) {
      logError('TrashService.moveToTrash: $mdPath', e, s);
      return false;
    }
  }

  Future<bool> _moveOne(String path, String trashDir) async {
    final dest = _uniqueDestination(trashDir, p.basename(path));
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    final FileSystemEntity entity = switch (type) {
      FileSystemEntityType.directory => Directory(path),
      FileSystemEntityType.file => File(path),
      _ => File(path),
    };
    if (type == FileSystemEntityType.notFound) return true; // al weg
    try {
      await entity.rename(dest);
    } on FileSystemException {
      // Andere schijf/volume: hernoemen kan niet over volumegrenzen heen.
      // Kopieer dan en verwijder pas ná een geslaagde kopie (fail-safe).
      await _copyRecursive(path, dest, type);
      await entity.delete(recursive: true);
    }
    await _writeLinuxTrashInfo(trashDir, path, dest);
    return true;
  }

  Future<void> _copyRecursive(
    String from,
    String to,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.file) {
      await File(from).copy(to);
      return;
    }
    await Directory(to).create(recursive: true);
    await for (final child in Directory(
      from,
    ).list(recursive: false, followLinks: false)) {
      final childTo = p.join(to, p.basename(child.path));
      await _copyRecursive(
        child.path,
        childTo,
        child is Directory
            ? FileSystemEntityType.directory
            : FileSystemEntityType.file,
      );
    }
  }

  /// XDG-prullenbak vereist een `.trashinfo`-zusje zodat "terugzetten" weet
  /// waar het item vandaan kwam; macOS heeft zoiets niet nodig.
  Future<void> _writeLinuxTrashInfo(
    String trashDir,
    String originalPath,
    String dest,
  ) async {
    if (!Platform.isLinux) return;
    try {
      final infoDir = p.join(p.dirname(trashDir), 'info');
      await Directory(infoDir).create(recursive: true);
      final stamp = DateTime.now().toIso8601String().split('.').first;
      await writeStringAtomic(
        File(p.join(infoDir, '${p.basename(dest)}.trashinfo')),
        '[Trash Info]\n'
        'Path=${Uri.encodeFull(originalPath)}\n'
        'DeletionDate=$stamp\n',
      );
    } catch (e) {
      // Alleen metadata voor "terugzetten"; het item zelf is al veilig.
      logWarning('TrashService: .trashinfo schrijven mislukt', e);
    }
  }

  String _uniqueDestination(String trashDir, String name) {
    var dest = p.join(trashDir, name);
    var i = 2;
    while (FileSystemEntity.typeSync(dest) != FileSystemEntityType.notFound) {
      final ext = p.extension(name);
      final base = p.basenameWithoutExtension(name);
      dest = p.join(trashDir, '$base ($i)$ext');
      i++;
    }
    return dest;
  }
}
