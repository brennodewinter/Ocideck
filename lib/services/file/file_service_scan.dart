// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (het zoekwerk op schijf: waar staan decks, en is
// dit bestand er wel een); all imports live in the main library file. Private
// helpers of the public scan API, which stays on the class.
part of '../file_service.dart';

/// Outcome of processing one candidate file during a broad scan: either a file
/// to keep (with its on-disk byte size), a file to skip, or a signal to stop the
/// walk because the cumulative budget is exhausted.
class _ScanFileOutcome {
  const _ScanFileOutcome.skip() : found = null, bytes = 0, stop = false;
  const _ScanFileOutcome.stop() : found = null, bytes = 0, stop = true;
  const _ScanFileOutcome.keep(this.found, this.bytes) : stop = false;

  /// De gevonden presentatie of het gevonden document, of null bij overslaan.
  final ScannedMarkdown? found;
  final int bytes;
  final bool stop;
}

/// Lost een [Link]-entiteit op naar het File of Directory van zijn doel.
/// `dir.list(followLinks: false)` rapporteert symlinks als Link — nooit als
/// File of Directory — dus zonder deze stap staat alles achter een gekoppelde
/// map (~/decks → ~/Nas/decks) stil buiten elke scan (#3145). Null bij een
/// kapotte koppeling of geweigerde toegang: zo'n entiteit draagt dan niet
/// bij, net als vóór deze resolve.
Future<FileSystemEntity?> _derefEntity(FileSystemEntity entity) async {
  if (entity is! Link) return entity;
  try {
    return switch (await FileSystemEntity.type(entity.path)) {
      FileSystemEntityType.file => File(entity.path),
      FileSystemEntityType.directory => Directory(entity.path),
      _ => null,
    };
  } on FileSystemException {
    return null;
  }
}

/// Echte locatie van een map, als dedup-sleutel zodat een symlink-lus of twee
/// koppelingen naar dezelfde map niet twee keer gewandeld wordt (#3145).
/// Null bij een onoplosbare koppeling — die slaat de wandeling over.
Future<String?> _realDirPath(String path) async {
  try {
    return await Directory(path).resolveSymbolicLinks();
  } on FileSystemException {
    return null;
  }
}

/// De implementatie achter [FileService.scanKnownLocations]: wandelt de
/// bekende wortels ([FileService._knownScanRoots]) en proeft elk bewerkbaar
/// Markdown-bestand via [FileService._probeMarkdown]. Top-level zoals
/// [walkMarkdownFiles]: de klasse zit tegen haar plafond.
Future<List<ScanHit>> _scanKnownLocations(
  FileService service, {
  List<String> recentFiles = const [],
  void Function(String phase, int found)? onProgress,
  bool Function()? isCancelled,
  bool includeDocuments = true,
  int maxDepth = 8,
  int maxFilesVisited = 20000,
  int maxMatches = 2000,
}) async {
  final roots = service._knownScanRoots(recentFiles);
  final hits = <ScanHit>[];
  final seen = <String>{};
  final seenDirs = <String>{};
  var visited = 0;
  var capped = false;
  bool cancelled() => isCancelled?.call() ?? false;

  Future<void> walk(Directory dir, int depth) async {
    if (cancelled() || hits.length >= maxMatches || capped) return;
    onProgress?.call(p.basename(dir.path), hits.length);
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (e) {
      logWarning('FileService.scanKnownLocations: directory not readable', e);
      return;
    }
    for (final entity in entries) {
      if (cancelled() || hits.length >= maxMatches) return;
      // Symlinks resolven eenmalig naar hun doeltype (#3145, zie
      // [_derefEntity]); [seenDirs] houdt lussen en dubbele wandelingen uit.
      final effective = await _derefEntity(entity);
      if (effective is File) {
        if (!isEditableMarkdownFile(effective.path)) continue;
        final normPath = p.normalize(effective.path);
        if (!seen.add(normPath)) continue;
        if (++visited > maxFilesVisited) {
          capped = true;
          logWarning(
            'FileService.scanKnownLocations: visited cap reached '
            '($maxFilesVisited files) — results truncated',
          );
          return;
        }
        final hit = await service._probeMarkdown(
          effective,
          includeDocuments: includeDocuments,
        );
        if (hit != null) hits.add(hit);
      } else if (effective is Directory && depth < maxDepth) {
        final name = p.basename(effective.path);
        if (name.startsWith('.') ||
            FileService._ignoredDirs.contains(name) ||
            FileService._scanDenylistDirs.contains(name)) {
          continue;
        }
        final real = await _realDirPath(effective.path);
        if (real == null || !seenDirs.add(real)) continue;
        await walk(effective, depth + 1);
      }
    }
  }

  for (final root in roots) {
    if (cancelled() || hits.length >= maxMatches || capped) break;
    final dir = Directory(root);
    try {
      if (!await dir.exists()) continue;
    } on FileSystemException catch (e) {
      // Zoals walk() bij een ondermap: een onleesbare wortel slaat de
      // zoekopdracht niet over — meld hem en ga door met de volgende.
      logWarning('FileService: zoekwortel niet leesbaar', e);
      continue;
    }
    final realDir = await _realDirPath(dir.path);
    if (realDir != null) seenDirs.add(realDir);
    await walk(dir, 0);
  }

  // Presentaties eerst (OciDeck-thema vooraan), dan de documenten, elk op
  // weergavetitel. Het is één lijst met twee soorten erin; op soort groeperen
  // scheelt de gebruiker het uit elkaar houden van rijen die er anders om en
  // om staan — en het filter in het scherm haalt de andere soort weg.
  hits.sort((a, b) {
    if (a.kind != b.kind) return a.kind.isPresentation ? -1 : 1;
    if (a.isOcideckTheme != b.isOcideckTheme) {
      return a.isOcideckTheme ? -1 : 1;
    }
    return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
  });
  return hits;
}

/// De mapwandeling achter [FileService.scanMarkdownFiles]: loopt [directory]
/// recursief af en leest elk bewerkbaar tekstbestand in.
///
/// Top-level en niet op [FileService]: hij raakt geen enkel veld van die klasse
/// aan (alles loopt via [service]), en de klasse zit tegen haar plafond.
Future<List<ScannedMarkdown>> walkMarkdownFiles(
  FileService service,
  String directory, {
  String? excludePath,
  bool includeDocuments = true,
  int maxDepth = 32,
  int maxFilesVisited = 5000,
  int maxScanBytes = 256 * 1024 * 1024,
}) async {
  final root = Directory(directory);
  try {
    if (!await root.exists()) return [];
  } catch (e) {
    // Zoals walk() een onleesbare ondermap overslaat: een wortel die niet te
    // lezen is levert niets op — met een logregel, geen ontsnapte fout.
    logWarning('FileService.scanMarkdownFiles: root niet leesbaar', e);
    return [];
  }

  final results = <ScannedMarkdown>[];
  final seenDirs = <String>{};
  var visited = 0;
  var scannedBytes = 0;
  var capped = false;
  Future<void> walk(Directory dir, int depth) async {
    if (capped) return;
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (e) {
      logWarning('FileService.scanMarkdownFiles: directory listing failed', e);
      return;
    }
    for (final entity in entries) {
      if (capped) return;
      // Symlinks resolven eenmalig naar hun doeltype (#3145, zie
      // [_derefEntity]); [seenDirs] houdt lussen en dubbele wandelingen uit.
      final effective = await _derefEntity(entity);
      if (effective is File) {
        if (!isEditableMarkdownFile(effective.path)) continue;
        if (excludePath != null && p.equals(effective.path, excludePath)) {
          continue;
        }
        if (++visited > maxFilesVisited) {
          capped = true;
          logWarning(
            'FileService.scanMarkdownFiles: visited cap reached '
            '($maxFilesVisited files) — results truncated',
          );
          return;
        }
        final outcome = await _scanOneFile(
          service,
          effective,
          scannedBytes,
          maxScanBytes,
          includeDocuments: includeDocuments,
        );
        if (outcome.stop) {
          capped = true;
          return;
        }
        final found = outcome.found;
        if (found != null) {
          scannedBytes += outcome.bytes;
          results.add(found);
        }
      } else if (effective is Directory && depth < maxDepth) {
        final name = p.basename(effective.path);
        if (FileService._ignoredDirs.contains(name) || name.startsWith('.')) {
          continue;
        }
        final real = await _realDirPath(effective.path);
        if (real == null || !seenDirs.add(real)) continue;
        await walk(effective, depth + 1);
      }
    }
  }

  final realRoot = await _realDirPath(root.path);
  if (realRoot != null) seenDirs.add(realRoot);
  await walk(root, 0);
  // Sorteren op een vooraf berekende sleutel: `displayTitle` van een document
  // leest zijn eerste kop uit de bron, en een vergelijkingsfunctie roept dat
  // voor elk item vele malen aan.
  final keyed = [
    for (final found in results)
      (key: found.displayTitle.toLowerCase(), file: found),
  ]..sort((a, b) => a.key.compareTo(b.key));
  return [for (final entry in keyed) entry.file];
}

/// Stats, size-gates, reads and parses one candidate file. The two size guards
/// keep a pathological tree from exhausting memory: a file over
/// [FileService.maxDeckMarkdownBytes] is skipped on its stat alone (never read),
/// and once adding it would cross [maxScanBytes] the walk is told to stop.
///
/// Een bestand dat geen Marp-deck is, komt als plat document terug wanneer
/// [includeDocuments] aan staat — maar alleen als het door dezelfde
/// fail-closed poort komt als het openen (`openDeckDetailed` scant de bytes die
/// het parseert). Een bestand dat om een ándere reden dan "geen presentatie"
/// wordt geweigerd — uitvoerbare inhoud, kapot, onleesbaar — komt in geen enkele
/// lijst terecht: wat je niet mag openen, hoor je ook niet aangeboden te krijgen.
Future<_ScanFileOutcome> _scanOneFile(
  FileService service,
  File entity,
  int scannedBytes,
  int maxScanBytes, {
  bool includeDocuments = true,
}) async {
  // Stat first so an oversized file is rejected on its size alone, never read
  // into memory. stat() also gives the modified time we keep below.
  FileStat stat;
  try {
    stat = await entity.stat();
  } catch (e) {
    logWarning('FileService.scanMarkdownFiles: stat failed', e);
    return const _ScanFileOutcome.skip();
  }
  if (stat.size > FileService.maxDeckMarkdownBytes) {
    logWarning(
      'FileService.scanMarkdownFiles: file exceeds '
      '${FileService.maxDeckMarkdownBytes ~/ (1024 * 1024)} MiB cap — skipped',
      entity.path,
    );
    return const _ScanFileOutcome.skip();
  }
  // Stop before crossing the cumulative budget so the retained sources can't
  // add up past [maxScanBytes], even when every file is valid.
  if (scannedBytes + stat.size > maxScanBytes) {
    logWarning(
      'FileService.scanMarkdownFiles: scan budget reached '
      '(${maxScanBytes ~/ (1024 * 1024)} MiB) — results truncated',
    );
    return const _ScanFileOutcome.stop();
  }
  String content;
  try {
    content = await entity.readAsString();
  } catch (e) {
    logWarning('FileService.scanMarkdownFiles: file not readable', e);
    return const _ScanFileOutcome.skip();
  }
  final outcome = await service.openDeckDetailed(entity.path, content: content);
  final deck = outcome.deck;
  if (deck != null) {
    if (deck.slides.isEmpty) return const _ScanFileOutcome.skip();
    return _ScanFileOutcome.keep(
      ScannedPresentation(
        path: entity.path,
        fileName: p.basename(entity.path),
        deck: deck,
        content: content,
        modified: stat.modified,
      ),
      stat.size,
    );
  }
  // Geen deck. Alleen "dit is geen presentatie" is een document; elke andere
  // weigering (unsafe, corrupt, te groot) blijft een weigering.
  if (!includeDocuments || outcome.failure != OpenFailure.notPresentation) {
    return const _ScanFileOutcome.skip();
  }
  return _ScanFileOutcome.keep(
    ScannedMarkdown(
      path: entity.path,
      fileName: p.basename(entity.path),
      content: content,
      modified: stat.modified,
    ),
    stat.size,
  );
}

extension _FileServiceScan on FileService {
  /// Frontmatter probe for one file: reads at most [_scanHeadBytes] and turns it
  /// into a [ScanHit]. Een bestand met `marp: true` wordt een presentatie; al het
  /// andere een document — tenzij [includeDocuments] uit staat, dan valt het weg.
  /// Oversized or unreadable files are skipped (logged, never thrown).
  ///
  /// De veiligheidsscan zit hier bewust níét: dit is een lijst, geen open. Wat
  /// je aanklikt gaat alsnog door de fail-closed poort van het openen (en van
  /// het voorbeeld), en die leest de bytes die hij parseert.
  Future<ScanHit?> _probeMarkdown(
    File file, {
    bool includeDocuments = true,
  }) async {
    try {
      final length = await file.length();
      if (length > FileService.maxDeckMarkdownBytes) return null;
      final cap = length < FileService._scanHeadBytes
          ? length
          : FileService._scanHeadBytes;
      final bytes = <int>[];
      await for (final chunk in file.openRead(0, cap)) {
        bytes.addAll(chunk);
      }
      // Tolerate malformed bytes: the header is ASCII/UTF-8, and a bad tail
      // byte from the cut-off point must not drop the whole probe.
      final head = utf8.decode(bytes, allowMalformed: true);
      final fm = _md.sniffFrontmatter(head);
      if (!fm.marp && !includeDocuments) return null;
      final theme = fm.theme?.trim();
      final stat = await file.stat();
      return ScanHit(
        path: file.path,
        fileName: p.basename(file.path),
        // Een document draagt geen `title:`; dan is de eerste kop de naam die
        // de gebruiker herkent.
        title: fm.marp ? fm.title : (fm.title ?? firstMarkdownHeading(head)),
        theme: (!fm.marp || theme == null || theme.isEmpty) ? null : theme,
        isOcideckTheme: fm.marp && theme == 'ocideck',
        kind: fm.marp ? MarkdownKind.presentation : MarkdownKind.document,
        size: length,
        modified: stat.modified,
      );
    } catch (e) {
      logWarning('FileService.scanKnownLocations: file probe failed', e);
      return null;
    }
  }

  /// The deduplicated set of root folders the broad scan walks. Parent folders
  /// of recent files plus the standard user locations; a root nested inside
  /// another is dropped so the tree isn't walked twice.
  List<String> _knownScanRoots(List<String> recentFiles) {
    final home = _homeDirectory() ?? Platform.environment['HOME'];
    final candidates = <String>[];
    if (home != null && home.trim().isNotEmpty) {
      for (final sub in const [
        'Documents',
        'Desktop',
        'Downloads',
        'Library/Mobile Documents/com~apple~CloudDocs',
      ]) {
        candidates.add(p.join(home, sub));
      }
    }
    // Geconfigureerde bibliotheken staan mogelijk buiten de standaardmappen;
    // neem ze als eigen wortels mee zodat de brede scan ze ook dekt.
    for (final path in _libraryPaths()) {
      if (path.trim().isNotEmpty) candidates.add(path);
    }
    for (final f in recentFiles) {
      if (f.trim().isEmpty) continue;
      candidates.add(p.dirname(f));
    }

    // Normalise, dedupe, then drop any root that lives inside another root.
    final normalized = <String>{
      for (final c in candidates) p.normalize(c),
    }.toList();
    final roots = <String>[];
    for (final c in normalized) {
      final nested = normalized.any(
        (other) => other != c && p.isWithin(other, c),
      );
      if (!nested) roots.add(c);
    }
    return roots;
  }
}
