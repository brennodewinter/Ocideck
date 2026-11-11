// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (kiezen waar een import belandt: een vrije
// mapnaam, of een bestaande map die exact dezelfde leden bevat en dus
// hergebruikt mag worden); all imports live in the main library file.
part of '../file_service.dart';

extension _FileServiceImportDirs on FileService {
  Directory _uniqueDir(String parent, String name) {
    var dir = Directory(p.join(parent, name));
    var i = 2;
    while (true) {
      bool taken;
      try {
        taken = dir.existsSync();
      } on FileSystemException {
        // Niet vast te stellen of hij vrij is — de naam teruggeven en het
        // `create` eronder laten beslissen: faalt de map ook aan te maken,
        // dan wordt díé fout de destinationUnavailable-melding.
        return dir;
      }
      if (!taken) return dir;
      dir = Directory(p.join(parent, '$name ($i)'));
      i++;
    }
  }

  /// De bestaande importmappen zoals [_uniqueDir] ze aanmaakt: `naam`,
  /// `naam (2)`, … — in aanmaakvolgorde, stoppend bij het eerste gat.
  Iterable<Directory> _importDirCandidates(String parent, String name) sync* {
    var dir = Directory(p.join(parent, name));
    var i = 2;
    while (true) {
      bool exists;
      try {
        exists = dir.existsSync();
      } on FileSystemException {
        // Een onleesbare kandidaat eindigt de lijst: hergebruik valt af en
        // de import pakt uit in een verse map — dezelfde uitkomst als een
        // map waarvan de inhoud niet overeenkomt.
        return;
      }
      if (!exists) return;
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
      try {
        if (!file.existsSync()) return false;
      } on FileSystemException {
        return false;
      }
      if (!await _fileHasBytes(file, e.value)) return false;
    }
    return true;
  }

  Future<bool> _fileHasBytes(File file, List<int> bytes) async {
    // Een leesfout telt als "niet gelijk", dezelfde afspraak als
    // `filesHaveSameContent`: hergebruik valt dan af en de import pakt uit in
    // een verse map — erger dan nodig, maar nooit een ontsnapte uitzondering
    // of een stil overschreven bestand (#2882).
    try {
      if (await file.length() != bytes.length) return false;
      final onDisk = await file.readAsBytes();
      for (var i = 0; i < bytes.length; i++) {
        if (onDisk[i] != bytes[i]) return false;
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
