import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/atomic_file.dart';
import '../utils/library_scan_limits.dart';
import '../utils/log.dart';

/// Vindt en herschrijft afbeeldingsverwijzingen (`![…](pad)`) in
/// Marp-markdownbestanden op schijf. Zo gaan bij het opruimen van duplicaten
/// ook presentaties mee die nu niet geopend zijn.
class ImageReferenceService {
  /// Zelfde mappen als FileService.scanPresentations overslaat.
  static const _ignoredDirs = {
    'images',
    'logos',
    'themes',
    'node_modules',
    'build',
    '.git',
    '.dart_tool',
  };

  /// Diepte- en aantalsplafond voor de walk — gedeeld met de afbeeldingskiezer
  /// ([ImageLibraryScanner]) zodat beide een grote map even hard begrenzen.
  static const _maxDepth = kLibraryScanMaxDepth;
  static const _maxFiles = kLibraryScanMaxFiles;

  /// Markdown-afbeelding: `![alt of bg-directive](pad)`.
  static final _imageRef = RegExp(r'!\[([^\]]*)\]\(([^)\n]+)\)');

  /// Zoek recursief alle `.md`-bestanden onder [searchDirs] (begrensd op diepte
  /// en aantal; asset- en verborgen mappen worden overgeslagen). Dubbele
  /// treffers via overlappende zoekpaden worden één keer teruggegeven.
  Future<List<String>> findDeckFiles(Iterable<String> searchDirs) async {
    final found = <String>{};

    Future<void> walk(Directory dir, int depth) async {
      if (found.length >= _maxFiles) return;
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (e) {
        logWarning('ImageReferenceService.findDeckFiles: list directory', e);
        return;
      }
      for (final entity in entries) {
        if (found.length >= _maxFiles) return;
        if (entity is File) {
          if (entity.path.toLowerCase().endsWith('.md')) {
            found.add(p.normalize(entity.path));
          }
        } else if (entity is Directory && depth < _maxDepth) {
          final name = p.basename(entity.path);
          if (_ignoredDirs.contains(name) || name.startsWith('.')) continue;
          await walk(entity, depth + 1);
        }
      }
    }

    for (final dirPath in searchDirs) {
      if (dirPath.isEmpty) continue;
      final root = Directory(dirPath);
      if (!root.existsSync()) continue;
      await walk(root, 0);
    }
    return found.toList();
  }

  /// Tel per pad uit [targets] hoe vaak het in [deckFiles] wordt genoemd.
  /// Paden in de markdown worden opgelost relatief aan de map van het
  /// `.md`-bestand. Paden zonder verwijzingen ontbreken in het resultaat.
  Future<Map<String, int>> countReferences(
    Iterable<String> deckFiles,
    Iterable<String> targets,
  ) async {
    final wanted = {for (final t in targets) p.normalize(t)};
    final counts = <String, int>{};
    for (final deckFile in deckFiles) {
      String content;
      try {
        content = await File(deckFile).readAsString();
      } catch (e) {
        logWarning('ImageReferenceService.countReferences: read deck file', e);
        continue;
      }
      final mdDir = p.dirname(deckFile);
      for (final match in _imageRef.allMatches(content)) {
        final resolved = _resolve(match.group(2)!, mdDir);
        if (resolved == null) continue;
        for (final target in wanted) {
          if (p.equals(resolved, target)) {
            counts[target] = (counts[target] ?? 0) + 1;
            break;
          }
        }
      }
    }
    return counts;
  }

  /// Per deckbestand: hoe vaak [target] erin wordt genoemd. Bestanden zonder
  /// treffer ontbreken in het resultaat. Gebruikt voor de waarschuwing bij
  /// verwijderen, zodat ook niet-geopende presentaties zichtbaar zijn.
  Future<Map<String, int>> referencingFiles(
    Iterable<String> deckFiles,
    String target,
  ) async {
    final wanted = p.normalize(target);
    final result = <String, int>{};
    for (final deckFile in deckFiles) {
      String content;
      try {
        content = await File(deckFile).readAsString();
      } catch (e) {
        logWarning('ImageReferenceService.referencingFiles: read deck file', e);
        continue;
      }
      final mdDir = p.dirname(deckFile);
      var count = 0;
      for (final match in _imageRef.allMatches(content)) {
        final resolved = _resolve(match.group(2)!, mdDir);
        if (resolved != null && p.equals(resolved, wanted)) count++;
      }
      if (count > 0) result[deckFile] = count;
    }
    return result;
  }

  /// Herschrijf in [deckFile] elke verwijzing naar [fromAbsolute] zodat die
  /// naar [toAbsolute] wijst. Alleen het pad binnen `![…](…)` verandert; de
  /// rest van het bestand blijft byte-voor-byte gelijk. Geeft true terug
  /// wanneer het bestand daadwerkelijk is gewijzigd.
  Future<bool> replaceReferences(
    String deckFile,
    String fromAbsolute,
    String toAbsolute,
  ) async {
    final file = File(deckFile);
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      logWarning('ImageReferenceService.replaceReferences: read deck file', e);
      return false;
    }
    final mdDir = p.dirname(deckFile);
    var changed = false;
    final updated = content.replaceAllMapped(_imageRef, (m) {
      final ref = m.group(2)!;
      final resolved = _resolve(ref, mdDir);
      if (resolved == null || !p.equals(resolved, fromAbsolute)) {
        return m.group(0)!;
      }
      changed = true;
      // Blijf relatief schrijven als de verwijzing dat al was en het nieuwe
      // pad binnen de projectmap ligt; anders absoluut.
      //
      // Altijd met '/' als scheiding: een verwijzing in de `.md` is portabel
      // (net als de deck-serializer, die `p.posix` schrijft). Zonder de
      // conversie zet `p.relative` op Windows backslashes in het bestand
      // (`images\foto.png`), en dan opent een op Windows bewerkt deck de
      // afbeelding niet meer op macOS of Linux.
      final replacement =
          !p.isAbsolute(ref.trim()) && p.isWithin(mdDir, toAbsolute)
          ? p.relative(toAbsolute, from: mdDir).replaceAll(r'\', '/')
          : toAbsolute;
      return '![${m.group(1)}]($replacement)';
    });
    if (!changed) return false;
    try {
      // Atomair: dit herschrijft het deck-bestand van de gebruiker in situ.
      await writeStringAtomic(file, updated);
    } catch (e) {
      logWarning('ImageReferenceService.replaceReferences: write deck file', e);
      return false;
    }
    return true;
  }

  String? _resolve(String ref, String mdDir) {
    final cleaned = ref.trim();
    if (cleaned.isEmpty || cleaned.contains('://')) return null;
    return p.normalize(
      p.isAbsolute(cleaned) ? cleaned : p.join(mdDir, cleaned),
    );
  }
}
