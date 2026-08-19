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
  if (!await root.exists()) return [];

  final results = <ScannedMarkdown>[];
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
      if (entity is File) {
        if (!isEditableMarkdownFile(entity.path)) continue;
        if (excludePath != null && p.equals(entity.path, excludePath)) {
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
          entity,
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
      } else if (entity is Directory && depth < maxDepth) {
        final name = p.basename(entity.path);
        if (FileService._ignoredDirs.contains(name) || name.startsWith('.')) {
          continue;
        }
        await walk(entity, depth + 1);
      }
    }
  }

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
