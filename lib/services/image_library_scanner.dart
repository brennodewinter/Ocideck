import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/library_scan_limits.dart';
import '../utils/log.dart';

/// De uitkomst van één afbeeldingsbibliotheek-scan: de gevonden paden (nieuwste
/// eerst) en of de scan werd afgekapt op de bestandsgrens.
class ImageLibraryScanResult {
  const ImageLibraryScanResult({
    required this.paths,
    required this.truncated,
    this.failed = false,
    this.unreachableRoots = const [],
  });

  /// Absolute paden naar de gevonden afbeeldingen, nieuwste eerst.
  final List<String> paths;

  /// True wanneer de scan de bestandsgrens raakte en dus onvolledig is.
  final bool truncated;

  /// True wanneer minstens één map niet gelezen kon worden (bijv. een
  /// onbereikbare netwerkmap); de lijst kan dan onvolledig zijn.
  final bool failed;

  /// Zoekwortels die niet bestonden (niet-gemounte schijf, verplaatste map).
  /// Leeg als elke gevraagde wortel bereikbaar was of de lijst leeg was.
  final List<String> unreachableRoots;
}

/// Doorloopt zoekmappen recursief op afbeeldingsbestanden — begrensd op diepte
/// en aantal, gebatcht en annuleerbaar, zodat een grote of gemounte bibliotheek
/// de aanroepende isolate niet lang blokkeert (#1049). Een aparte, testbare
/// service in plaats van een privémethode in de kiezer, zoals
/// `ImageReferenceService.findDeckFiles` voor de deck-scan.
class ImageLibraryScanner {
  /// De extensies die als afbeelding tellen (met punt, kleine letters).
  static const defaultExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.tiff',
    '.tif',
  };

  /// Mappen die niet naar afbeeldingen doorzocht worden: versiebeheer, build- en
  /// pakketuitvoer. Anders dan bij de deck-scan blijven `images`/`logos`/`themes`
  /// hier juist wél in beeld — dáár staan de afbeeldingen.
  static const _ignoredDirs = {'node_modules', 'build', '.git', '.dart_tool'};

  /// Hoeveel bestanden per batch worden gestat vóór er wordt teruggegeven aan de
  /// gebeurtenislus; klein genoeg dat de interface responsief blijft.
  static const _statBatch = 256;

  /// Zoek recursief alle afbeeldingsbestanden onder [searchPaths], nieuwste
  /// eerst. Begrensd op [maxFiles] en [maxDepth]; overlappende zoekpaden leveren
  /// elk bestand één keer op. [isCancelled] wordt gepolst — geeft die true, dan
  /// stopt de scan en komt er een lege, niet-afgekapte uitslag terug (de
  /// aanroeper hoort die weg te gooien). De stat- en sorteerstap draait in
  /// asynchrone batches, zodat een grote bibliotheek de isolate niet blokkeert.
  static Future<ImageLibraryScanResult> scan(
    Iterable<String> searchPaths, {
    int maxFiles = kLibraryScanMaxFiles,
    int maxDepth = kLibraryScanMaxDepth,
    bool Function()? isCancelled,
    Set<String> extensions = defaultExtensions,
  }) async {
    final found = <String>{};
    var cancelled = false;
    var failed = false;
    final unreachableRoots = <String>[];

    bool wantsStop() => isCancelled?.call() ?? false;

    Future<void> walk(Directory dir, int depth) async {
      if (found.length >= maxFiles || cancelled) return;
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (e) {
        logWarning('ImageLibraryScanner.scan: list directory', e);
        failed = true;
        return;
      }
      for (final entity in entries) {
        if (found.length >= maxFiles) return;
        if (wantsStop()) {
          cancelled = true;
          return;
        }
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (extensions.contains(ext)) found.add(p.normalize(entity.path));
        } else if (entity is Directory && depth < maxDepth) {
          final name = p.basename(entity.path);
          if (_ignoredDirs.contains(name) || name.startsWith('.')) continue;
          await walk(entity, depth + 1);
        }
      }
    }

    for (final dirPath in searchPaths) {
      if (dirPath.isEmpty || cancelled) continue;
      final root = Directory(dirPath);
      if (!root.existsSync()) {
        unreachableRoots.add(dirPath);
        continue;
      }
      await walk(root, 0);
    }

    if (cancelled) {
      return const ImageLibraryScanResult(paths: [], truncated: false);
    }
    // Alle gevraagde wortels weg (niet-gemounte schijf) is een mislukte scan —
    // stil een lege bibliotheek tonen alsof er niets is, is erger.
    if (unreachableRoots.isNotEmpty && found.isEmpty) {
      failed = true;
    }
    final truncated = found.length >= maxFiles;

    // Stat in batches: elk pad één keer, met een adempauze tussen de batches en
    // een annuleringscontrole, in plaats van 20000 synchrone stats achter elkaar
    // op de aanroepende isolate.
    final withTimes = <(String, DateTime)>[];
    final all = found.toList();
    for (var i = 0; i < all.length; i += _statBatch) {
      if (wantsStop()) {
        return const ImageLibraryScanResult(paths: [], truncated: false);
      }
      final end = (i + _statBatch < all.length) ? i + _statBatch : all.length;
      for (var j = i; j < end; j++) {
        DateTime modified;
        try {
          modified = (await File(all[j]).stat()).modified;
        } catch (e) {
          logWarning('ImageLibraryScanner.scan: stat', e);
          modified = DateTime.fromMillisecondsSinceEpoch(0);
        }
        withTimes.add((all[j], modified));
      }
      // Adempauze voor de gebeurtenislus tussen batches.
      await Future<void>.delayed(Duration.zero);
    }

    withTimes.sort((a, b) => b.$2.compareTo(a.$2));
    return ImageLibraryScanResult(
      paths: [for (final e in withTimes) e.$1],
      truncated: truncated,
      failed: failed,
      unreachableRoots: unreachableRoots,
    );
  }
}
