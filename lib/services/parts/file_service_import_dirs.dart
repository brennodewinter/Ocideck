// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (kiezen waar een import belandt: een vrije
// mapnaam, of een bestaande map die exact dezelfde leden bevat en dus
// hergebruikt mag worden); all imports live in the main library file.
part of '../file_service.dart';

extension _FileServiceImportDirs on FileService {
  Directory _uniqueDir(String parent, String name) {
    var dir = Directory(p.join(parent, name));
    var i = 2;
    while (dir.existsSync()) {
      dir = Directory(p.join(parent, '$name ($i)'));
      i++;
    }
    return dir;
  }

  /// De bestaande importmappen zoals [_uniqueDir] ze aanmaakt: `naam`,
  /// `naam (2)`, … — in aanmaakvolgorde, stoppend bij het eerste gat.
  Iterable<Directory> _importDirCandidates(String parent, String name) sync* {
    var dir = Directory(p.join(parent, name));
    var i = 2;
    while (dir.existsSync()) {
      yield dir;
      dir = Directory(p.join(parent, '$name ($i)'));
      i++;
    }
  }

  /// Of [dir] alle pakketleden [entries] byte-identiek bevat (traversal-leden
  /// tellen niet mee, die worden ook nooit geschreven). Een gewijzigd of
  /// ontbrekend lid — een lokaal bewerkte kopie — valt af. Extra lokale
  /// bestanden zijn juist toegestaan: de app schrijft sidecars (annotaties,
  /// notities) naast de markdown, en hergebruik schrijft zelf niets, dus die
  /// kunnen nooit worden overschreven.
  Future<bool> _dirMatchesEntries(
    Directory dir,
    List<PackageEntry> entries,
  ) async {
    final expected = <String, List<int>>{};
    for (final entry in entries) {
      final resolved = p.normalize(p.join(dir.path, entry.name));
      if (resolved == dir.path || !p.isWithin(dir.path, resolved)) continue;
      expected[resolved] = entry.bytes;
    }
    for (final e in expected.entries) {
      final file = File(e.key);
      if (!file.existsSync()) return false;
      if (!await _fileHasBytes(file, e.value)) return false;
    }
    return true;
  }

  Future<bool> _fileHasBytes(File file, List<int> bytes) async {
    if (await file.length() != bytes.length) return false;
    final onDisk = await file.readAsBytes();
    for (var i = 0; i < bytes.length; i++) {
      if (onDisk[i] != bytes[i]) return false;
    }
    return true;
  }
}
