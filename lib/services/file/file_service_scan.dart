// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (het zoekwerk op schijf: waar staan decks, en is
// dit bestand er wel een); all imports live in the main library file. Private
// helpers of the public scan API, which stays on the class.
part of '../file_service.dart';

/// Outcome of processing one candidate `.md` file during a broad scan: either a
/// presentation to keep (with its on-disk byte size), a file to skip, or a
/// signal to stop the walk because the cumulative budget is exhausted.
class _ScanFileOutcome {
  const _ScanFileOutcome.skip() : presentation = null, bytes = 0, stop = false;
  const _ScanFileOutcome.stop() : presentation = null, bytes = 0, stop = true;
  const _ScanFileOutcome.keep(this.presentation, this.bytes) : stop = false;

  final ScannedPresentation? presentation;
  final int bytes;
  final bool stop;
}

/// Stats, size-gates, reads and parses one candidate `.md` file. The two size
/// guards keep a pathological tree from exhausting memory: a file over
/// [FileService.maxDeckMarkdownBytes] is skipped on its stat alone (never read),
/// and once adding it would cross [maxScanBytes] the walk is told to stop.
Future<_ScanFileOutcome> _scanOneFile(
  FileService service,
  File entity,
  int scannedBytes,
  int maxScanBytes,
) async {
  // Stat first so an oversized file is rejected on its size alone, never read
  // into memory. stat() also gives the modified time we keep below.
  FileStat stat;
  try {
    stat = await entity.stat();
  } catch (e) {
    logWarning('FileService.scanPresentations: stat failed', e);
    return const _ScanFileOutcome.skip();
  }
  if (stat.size > FileService.maxDeckMarkdownBytes) {
    logWarning(
      'FileService.scanPresentations: file exceeds '
      '${FileService.maxDeckMarkdownBytes ~/ (1024 * 1024)} MiB cap — skipped',
      entity.path,
    );
    return const _ScanFileOutcome.skip();
  }
  // Stop before crossing the cumulative budget so the retained sources can't
  // add up past [maxScanBytes], even when every file is valid.
  if (scannedBytes + stat.size > maxScanBytes) {
    logWarning(
      'FileService.scanPresentations: scan budget reached '
      '(${maxScanBytes ~/ (1024 * 1024)} MiB) — results truncated',
    );
    return const _ScanFileOutcome.stop();
  }
  String content;
  try {
    content = await entity.readAsString();
  } catch (e) {
    logWarning('FileService.scanPresentations: file not readable', e);
    return const _ScanFileOutcome.skip();
  }
  final deck = await service.openDeck(entity.path, content: content);
  if (deck == null || deck.slides.isEmpty) return const _ScanFileOutcome.skip();
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

extension _FileServiceScan on FileService {
  /// Frontmatter probe for one file: reads at most [_scanHeadBytes], and returns
  /// a [ScanHit] only when the file declares `marp: true`. Oversized or
  /// unreadable files are skipped (logged, never thrown).
  Future<ScanHit?> _probeMarkdown(File file) async {
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
      if (!fm.marp) return null;
      final theme = fm.theme?.trim();
      final stat = await file.stat();
      return ScanHit(
        path: file.path,
        fileName: p.basename(file.path),
        title: fm.title,
        theme: (theme == null || theme.isEmpty) ? null : theme,
        isOcideckTheme: theme == 'ocideck',
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
