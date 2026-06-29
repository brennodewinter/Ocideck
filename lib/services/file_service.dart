import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;
import '../models/deck.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../models/chart.dart';
import '../models/slide.dart';
import '../utils/atomic_file.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';
import '../utils/project_path.dart';
import 'annotation_codec.dart';
import 'user_notes_codec.dart';
import 'caption_service.dart';
import 'image_service.dart';
import 'markdown_safety.dart';
import 'markdown_service.dart';

/// A presentation found on disk while scanning a directory.
class ScannedPresentation {
  final String path;
  final String fileName;
  final Deck deck;

  /// The raw markdown source, kept for maximal full-text search.
  final String content;

  const ScannedPresentation({
    required this.path,
    required this.fileName,
    required this.deck,
    this.content = '',
  });
}

/// A Marp presentation found by the disk-wide scan. Unlike [ScannedPresentation]
/// this is a lightweight record built from a frontmatter probe only — no full
/// parse — so scanning large folder trees stays cheap.
class ScanHit {
  final String path;
  final String fileName;

  /// Title from the frontmatter, or null when the deck omits one.
  final String? title;

  /// The declared `theme:` value, or null when absent.
  final String? theme;

  /// True when [theme] is the OciDeck theme (sorted/marked first in the UI).
  final bool isOcideckTheme;

  const ScanHit({
    required this.path,
    required this.fileName,
    required this.title,
    required this.theme,
    required this.isOcideckTheme,
  });

  /// A display label: the frontmatter title, falling back to the file name
  /// without its extension.
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return p.basenameWithoutExtension(fileName);
  }
}

class _LogoProjectAsset {
  final ThemeProfile profile;
  final String? cssUrl;

  const _LogoProjectAsset(this.profile, this.cssUrl);
}

class FileService {
  final MarkdownService _md;
  final ImageService _img;
  final ThemeProfile Function() _themeProfile;
  final String Function() _languageCode;
  final String? Function() _homeDirectory;
  final CaptionService _captions = CaptionService();

  FileService(
    this._md,
    this._img,
    this._themeProfile, {
    String Function()? languageCode,
    String? Function()? homeDirectory,
  }) : _languageCode = languageCode ?? (() => 'nl'),
       _homeDirectory = homeDirectory ?? (() => null);

  ThemeProfile get currentThemeProfile => resolveThemeProfile(_themeProfile());

  /// The user's active style profile, resolved for [projectPath]. Styling is no
  /// longer read from the markdown (the file holds only content); the app
  /// applies the current profile whenever a deck is opened.
  ThemeProfile activeProfileFor({String? projectPath}) =>
      resolveThemeProfile(_themeProfile(), projectPath: projectPath);

  ThemeProfile resolveThemeProfile(
    ThemeProfile profile, {
    String? projectPath,
  }) {
    final logoPath = profile.logoPath;
    if (logoPath == null || logoPath.trim().isEmpty || p.isAbsolute(logoPath)) {
      return profile;
    }

    final bases = [?projectPath, ?_homeDirectory()];
    for (final base in bases) {
      final candidate = p.normalize(p.join(base, logoPath));
      if (File(candidate).existsSync()) {
        return profile.copyWith(logoPath: candidate);
      }
    }
    return profile;
  }

  String _d(String text) => AppLocalizations.sourceFor(_languageCode(), text);

  static const _ignoredDirs = {
    'images',
    'logos',
    'themes',
    'node_modules',
    'build',
    '.git',
    '.dart_tool',
  };

  /// Recursively scan [directory] for Marp markdown presentations and parse
  /// them into decks. [excludePath] (typically the currently open file) is
  /// skipped. Directories such as images/ and themes/ are ignored, and the
  /// walk is bounded by [maxDepth] to keep large home folders responsive.
  Future<List<ScannedPresentation>> scanPresentations(
    String directory, {
    String? excludePath,
    int maxDepth = 4,
  }) async {
    final root = Directory(directory);
    if (!await root.exists()) return [];

    final results = <ScannedPresentation>[];
    Future<void> walk(Directory dir, int depth) async {
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (e) {
        logWarning(
          'FileService.scanPresentations: directory listing failed',
          e,
        );
        return;
      }
      for (final entity in entries) {
        if (entity is File) {
          if (!entity.path.toLowerCase().endsWith('.md')) continue;
          if (excludePath != null && p.equals(entity.path, excludePath)) {
            continue;
          }
          String content;
          try {
            content = await entity.readAsString();
          } catch (e) {
            logWarning('FileService.scanPresentations: file not readable', e);
            continue;
          }
          final deck = await openDeck(entity.path, content: content);
          if (deck != null && deck.slides.isNotEmpty) {
            results.add(
              ScannedPresentation(
                path: entity.path,
                fileName: p.basename(entity.path),
                deck: deck,
                content: content,
              ),
            );
          }
        } else if (entity is Directory && depth < maxDepth) {
          final name = p.basename(entity.path);
          if (_ignoredDirs.contains(name) || name.startsWith('.')) continue;
          await walk(entity, depth + 1);
        }
      }
    }

    await walk(root, 0);
    results.sort(
      (a, b) =>
          a.deck.title.toLowerCase().compareTo(b.deck.title.toLowerCase()),
    );
    return results;
  }

  /// Directories the broad scan never descends into, on top of [_ignoredDirs]:
  /// large system trees that can't hold user presentations.
  static const _scanDenylistDirs = {
    'Library',
    'Applications',
    'System',
    'Pods',
    'Caches',
  };

  /// Only the first slice of each `.md` is read for the frontmatter probe; the
  /// header always lives at the very top, so 64 KiB is plenty.
  static const _scanHeadBytes = 64 * 1024;

  /// Scan a fixed set of well-known locations (parent folders of [recentFiles],
  /// plus the user's Documents/Desktop/Downloads/iCloud and configured home
  /// directory) for Marp markdown presentations, using a cheap frontmatter
  /// probe rather than a full parse.
  ///
  /// Only files declaring `marp: true` are returned; OciDeck-themed decks are
  /// flagged via [ScanHit.isOcideckTheme] and sorted first. The walk is bounded
  /// by [maxDepth], [maxFilesVisited] and [maxMatches] so a pathological tree
  /// can't hang the UI; [onProgress] reports the current folder and match count,
  /// and [isCancelled] lets the caller abort.
  Future<List<ScanHit>> scanKnownLocations({
    List<String> recentFiles = const [],
    void Function(String phase, int found)? onProgress,
    bool Function()? isCancelled,
    int maxDepth = 8,
    int maxFilesVisited = 20000,
    int maxMatches = 2000,
  }) async {
    final roots = _knownScanRoots(recentFiles);
    final hits = <ScanHit>[];
    final seen = <String>{};
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
        if (entity is File) {
          if (!entity.path.toLowerCase().endsWith('.md')) continue;
          final normPath = p.normalize(entity.path);
          if (!seen.add(normPath)) continue;
          if (++visited > maxFilesVisited) {
            capped = true;
            logWarning(
              'FileService.scanKnownLocations: visited cap reached '
              '($maxFilesVisited files) — results truncated',
            );
            return;
          }
          final hit = await _probeMarkdown(entity);
          if (hit != null) hits.add(hit);
        } else if (entity is Directory && depth < maxDepth) {
          final name = p.basename(entity.path);
          if (name.startsWith('.') ||
              _ignoredDirs.contains(name) ||
              _scanDenylistDirs.contains(name)) {
            continue;
          }
          await walk(entity, depth + 1);
        }
      }
    }

    for (final root in roots) {
      if (cancelled() || hits.length >= maxMatches || capped) break;
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await walk(dir, 0);
    }

    // OciDeck-themed decks first, then by display title (case-insensitive).
    hits.sort((a, b) {
      if (a.isOcideckTheme != b.isOcideckTheme) {
        return a.isOcideckTheme ? -1 : 1;
      }
      return a.displayTitle.toLowerCase().compareTo(
        b.displayTitle.toLowerCase(),
      );
    });
    return hits;
  }

  /// Frontmatter probe for one file: reads at most [_scanHeadBytes], and returns
  /// a [ScanHit] only when the file declares `marp: true`. Oversized or
  /// unreadable files are skipped (logged, never thrown).
  Future<ScanHit?> _probeMarkdown(File file) async {
    try {
      final length = await file.length();
      if (length > maxDeckMarkdownBytes) return null;
      final cap = length < _scanHeadBytes ? length : _scanHeadBytes;
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
      return ScanHit(
        path: file.path,
        fileName: p.basename(file.path),
        title: fm.title,
        theme: (theme == null || theme.isEmpty) ? null : theme,
        isOcideckTheme: theme == 'ocideck',
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

  Future<String?> pickMarkdownFile({String? initialDirectory}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: _d('Presentatie openen'),
      type: FileType.custom,
      allowedExtensions: ['md'],
      initialDirectory: initialDirectory,
    );
    return result?.files.single.path;
  }

  /// Scan the `.md` at [filePath] for executable/dangerous content before it is
  /// opened or imported. An empty list means the file is data-only and safe.
  ///
  /// Reading problems (missing, over-size, non-UTF-8) return an empty list:
  /// [openDeck] applies the same caps and will refuse those files anyway, so we
  /// must not raise a false security alarm for a file that simply won't load.
  Future<List<MarkdownSafetyFinding>> scanForUnsafeMarkdown(
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const [];
      if (await file.length() > maxDeckMarkdownBytes) return const [];
      final raw = await file.readAsString();
      return MarkdownSafetyScanner.scan(raw);
    } catch (e, s) {
      logError('FileService.scanForUnsafeMarkdown', e, s);
      return const [];
    }
  }

  /// Open and parse a deck file.
  ///
  /// The bytes are ALWAYS scanned for executable content and the open is refused
  /// (returns null) if any is found. The scan runs on the exact in-memory bytes
  /// that are about to be parsed — there is no separate "check" read that a file
  /// could change behind, so no caller can be marked "trusted" to skip it. A
  /// disk file can be swapped between any two reads, so trust is never assumed;
  /// only the bytes in hand at parse time are authoritative.
  Future<Deck?> openDeck(String filePath, {String? content}) async {
    String raw;
    if (content != null) {
      raw = content;
    } else {
      final file = File(filePath);
      if (!await file.exists()) return null;
      // A deck is plain text (images/media are sidecar files), so a huge .md is
      // pathological. Cap it to avoid loading/parsing an attacker-sized file.
      try {
        if (await file.length() > maxDeckMarkdownBytes) {
          logWarning(
            'FileService.openDeck: file exceeds ${maxDeckMarkdownBytes ~/ (1024 * 1024)} MiB cap',
          );
          return null;
        }
      } catch (e) {
        logWarning('FileService.openDeck: cannot stat file', e);
        return null;
      }
      try {
        raw = await file.readAsString();
      } catch (e) {
        // Non-UTF8 / unreadable bytes must not crash the open flow.
        logWarning('FileService.openDeck: file not readable as UTF-8', e);
        return null;
      }
    }
    // Fail-closed: never parse/open a deck that carries executable content.
    // Scanning `raw` (the very bytes we hand to the parser) closes any
    // time-of-check/time-of-use gap — the file cannot have changed between the
    // scan and the parse because both use this one in-memory string.
    final findings = MarkdownSafetyScanner.scan(raw);
    if (findings.isNotEmpty) {
      logWarning(
        'FileService.openDeck: refused — executable content '
        '(${findings.length} finding(s))',
        filePath,
      );
      return null;
    }
    final parsed = _md.parseDeck(raw, filePath: filePath);
    if (parsed == null) return null;
    // Guard against silently opening a truncated/corrupt file as a blank deck:
    // a valid save always emits at least one slide block after the frontmatter,
    // so a complete header with an empty body means the source was cut short.
    if (content == null && _looksTruncated(raw, parsed)) {
      logWarning(
        'FileService.openDeck: frontmatter present but no slide body',
        filePath,
      );
      return null;
    }
    // The file carries only content; apply the active style profile on open.
    final deck = parsed.copyWith(
      themeProfile: activeProfileFor(projectPath: parsed.projectPath),
    );
    var hydrated = await _hydrateCharts(await _hydrateImageCaptions(deck));
    // Re-attach separate sidecar layers when reading from disk.
    if (content == null) {
      final sidecar = File(_sidecarPath(filePath));
      if (await sidecar.exists()) {
        try {
          final map = AnnotationCodec.decode(
            await sidecar.readAsString(),
            hydrated.slides,
          );
          if (map.isNotEmpty) hydrated = hydrated.copyWith(annotations: map);
        } catch (e) {
          // A broken sidecar must never block opening the deck.
          logWarning('FileService.openDeck: annotation sidecar unreadable', e);
        }
      }
      final userNotesSidecar = File(_userNotesSidecarPath(filePath));
      if (await userNotesSidecar.exists()) {
        try {
          final map = UserNotesCodec.decode(
            await userNotesSidecar.readAsString(),
            hydrated.slides,
          );
          if (map.isNotEmpty) hydrated = hydrated.copyWith(userNotes: map);
        } catch (e) {
          logWarning('FileService.openDeck: user-notes sidecar unreadable', e);
        }
      }
    }
    return hydrated;
  }

  /// True when [raw] opens with a complete frontmatter block but carries no
  /// slide body after it, while [parsed] degraded to the single placeholder
  /// slide — the signature of a truncated or corrupt deck file.
  bool _looksTruncated(String raw, Deck parsed) {
    if (parsed.slides.length != 1) return false;
    final norm = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!norm.startsWith('---\n')) return false;
    final end = norm.indexOf('\n---\n', 4);
    // Unterminated frontmatter: leave it to the parser rather than reject here.
    if (end == -1) return false;
    // A complete frontmatter header followed by no slide body means the file
    // was cut short — trim only the part *after* the closing fence so the
    // fence's own trailing newline is preserved.
    return norm.substring(end + 5).trim().isEmpty;
  }

  /// Path of the annotation sidecar next to a deck `<name>.md` → `<name>.ink.json`.
  String _sidecarPath(String mdPath) => p.setExtension(mdPath, '.ink.json');

  /// Write the annotation sidecar next to [filePath], or remove it when empty.
  Future<void> _writeSidecar(Deck deck, String filePath) async {
    final sidecar = File(_sidecarPath(filePath));
    final json = AnnotationCodec.encode(deck.slides, deck.annotations);
    if (json == null) {
      if (await sidecar.exists()) await sidecar.delete();
    } else {
      await writeStringAtomic(sidecar, json);
    }
  }

  /// Path of the user-notes sidecar next to a deck `<name>.md`.
  String _userNotesSidecarPath(String mdPath) =>
      p.setExtension(mdPath, '.user-notes.json');

  /// Write the user-notes sidecar next to [filePath], or remove it when empty.
  Future<void> _writeUserNotesSidecar(Deck deck, String filePath) async {
    final sidecar = File(_userNotesSidecarPath(filePath));
    final json = UserNotesCodec.encode(deck.slides, deck.userNotes);
    if (json == null) {
      if (await sidecar.exists()) await sidecar.delete();
    } else {
      await writeStringAtomic(sidecar, json);
    }
  }

  /// Load the external CSV of any chart slide that links one, inlining the data
  /// into the in-memory spec so the renderer has it. The markdown on disk keeps
  /// only the `source` reference (data is stripped again on save).
  Future<Deck> _hydrateCharts(Deck deck) async {
    if (deck.projectPath == null) return deck;
    var changed = false;
    final slides = <Slide>[];
    for (final s in deck.slides) {
      if (s.type != SlideType.chart) {
        slides.add(s);
        continue;
      }
      final spec = ChartSpec.parse(s.customMarkdown);
      if (spec.source == null || spec.hasInlineData) {
        slides.add(s);
        continue;
      }
      // A chart's CSV link must stay inside the project (no absolute paths or
      // `../` escapes) — otherwise an untrusted deck could read arbitrary files.
      final abs = resolveProjectRelative(deck.projectPath, spec.source!);
      final file = abs == null ? null : File(abs);
      if (file == null || !await file.exists()) {
        slides.add(s);
        continue;
      }
      try {
        final csv = await file.readAsString();
        slides.add(s.copyWith(customMarkdown: spec.withCsv(csv).toBlock()));
        changed = true;
      } catch (e) {
        logWarning('FileService._hydrateCharts: chart CSV unreadable', e);
        slides.add(s);
      }
    }
    return changed ? deck.copyWith(slides: slides) : deck;
  }

  /// For packaging: add a chart's linked CSV under data/ and rewrite its source
  /// path; if the CSV is missing, fall back to keeping the data inline.
  Slide _packChartSlide(Slide s, String? Function(String, String) addAsset) {
    final spec = ChartSpec.parse(s.customMarkdown);
    final src = spec.source;
    if (src == null) return s;
    final rel = addAsset(src, chartDataDirName);
    if (rel == null) {
      return s.copyWith(
        customMarkdown: spec.copyWith(clearSource: true).toBlock(),
      );
    }
    return s.copyWith(
      customMarkdown: spec.copyWith(source: rel).toBlock(forStorage: true),
    );
  }

  /// Copy any linked chart CSVs into [destDir]/data (used by Save As to a new
  /// location). A normal save is a no-op because source and dest coincide.
  Future<void> _copyChartData(Deck deck, String destDir) async {
    for (final s in deck.slides) {
      if (s.type != SlideType.chart) continue;
      final src = ChartSpec.parse(s.customMarkdown).source;
      if (src == null || p.isAbsolute(src) || deck.projectPath == null) {
        continue;
      }
      // Containment guard, matching _hydrateCharts: a chart source like
      // ../../../secret.csv must not be copied out of the project on Save As.
      final resolved = resolveProjectRelative(deck.projectPath, src);
      if (resolved == null) continue;
      final from = File(resolved);
      final toPath = p.join(destDir, src);
      if (from.path == toPath || !from.existsSync()) continue;
      final out = File(toPath);
      await out.parent.create(recursive: true);
      await writeBytesAtomic(out, await from.readAsBytes());
    }
  }

  Future<String?> saveDeckAs(Deck deck, {String? initialDirectory}) async {
    final safeName = deck.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(' ', '_');
    final result = await FilePicker.saveFile(
      dialogTitle: _d('Opslaan als'),
      fileName: '$safeName.md',
      initialDirectory: initialDirectory,
    );
    if (result == null) return null;
    final path = result.endsWith('.md') ? result : '$result.md';
    await _writeProject(deck, path);
    return path;
  }

  Future<Deck> saveDeck(Deck deck, String filePath) async {
    return _writeProject(deck, filePath);
  }

  // ── Draagbaar pakket (uitwisselen / op een ander systeem draaien) ──────────

  static const packageExtension = 'ocideck';

  String _safeName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return cleaned.isEmpty ? 'presentatie' : cleaned;
  }

  /// Schrijf een zelfstandig pakket (zip): de markdown + álle gebruikte assets
  /// (afbeeldingen, media, logo) en de thema-CSS, met onderling relatieve
  /// paden. Werkt ongeacht of het deck al is opgeslagen.
  Future<void> exportPackage(Deck deck, String destPath) async {
    final bytes = await buildPackageBytes(deck);
    await writeBytesAtomic(File(destPath), bytes);
  }

  /// Bouw de bytes van een zelfstandig `.ocideck`-pakket (zie [exportPackage]),
  /// zonder ze weg te schrijven. Gebruikt om hetzelfde pakket te uploaden naar
  /// een WebDAV-bron in plaats van naar schijf.
  Future<List<int>> buildPackageBytes(Deck deck) async =>
      ZipEncoder().encodeBytes(await _buildPackageArchive(deck));

  /// Pakket-leden (pad → bytes) zonder ze te zippen, zodat elk bestand los naar
  /// een WebDAV-map kan worden geüpload — een "platte" spiegel van het deck met
  /// dezelfde asset-mappen en herschreven relatieve paden als het pakket.
  Future<Map<String, List<int>>> buildPackageMembers(Deck deck) async {
    final archive = await _buildPackageArchive(deck);
    return {
      for (final f in archive.files)
        if (f.isFile) f.name: f.content,
    };
  }

  Future<Archive> _buildPackageArchive(Deck deck) async {
    final archive = Archive();
    final added = <String>{};

    /// Resolve [path] (relatief t.o.v. projectPath of absoluut), voeg het
    /// bestand toe onder `<subdir>/<bestandsnaam>` en geef dat pad terug.
    String? addAsset(String path, String subdir) {
      if (path.trim().isEmpty) return null;
      final String abs;
      if (p.isAbsolute(path)) {
        // Absolute paths come from the picker (the user explicitly chose them).
        abs = path;
      } else if (deck.projectPath != null) {
        // A relative asset must not escape the project via `../`.
        final resolved = resolveProjectRelative(deck.projectPath, path);
        if (resolved == null) return null;
        abs = resolved;
      } else {
        abs = path;
      }
      final file = File(abs);
      if (!file.existsSync()) return null;
      final rel = p.posix.join(subdir, p.basename(abs));
      if (!added.contains(rel)) {
        final bytes = file.readAsBytesSync();
        archive.add(ArchiveFile(rel, bytes.length, bytes));
        added.add(rel);
      }
      return rel;
    }

    final slides = [
      for (final s in deck.slides)
        s.copyWith(
          imagePath: addAsset(s.imagePath, 'images') ?? s.imagePath,
          imagePath2: addAsset(s.imagePath2, 'images') ?? s.imagePath2,
          videoPath: addAsset(s.videoPath, 'media') ?? s.videoPath,
          audioPath: addAsset(s.audioPath, 'media') ?? s.audioPath,
        ),
    ];

    // Chart slides link their data via a CSV path inside the JSON block; bring
    // the file along under data/ and rewrite the path to match.
    final packedSlides = [
      for (final s in slides)
        if (s.type == SlideType.chart) _packChartSlide(s, addAsset) else s,
    ];

    final logoRel = addAsset(deck.themeProfile.logoPath ?? '', 'logos');
    final profile = logoRel != null
        ? deck.themeProfile.copyWith(logoPath: logoRel)
        : deck.themeProfile;

    final packDeck = deck.copyWith(slides: packedSlides, themeProfile: profile);

    // Markdown.
    final markdown = _md.generateDeck(packDeck);
    final mdBytes = utf8.encode(markdown);
    archive.add(
      ArchiveFile('${_safeName(deck.title)}.md', mdBytes.length, mdBytes),
    );

    // Annotation layer travels as a separate sidecar (same base name as the
    // markdown), so the .md inside the package stays pure Marp.
    final ink = AnnotationCodec.encode(packDeck.slides, packDeck.annotations);
    if (ink != null) {
      final inkBytes = utf8.encode(ink);
      archive.add(
        ArchiveFile(
          '${_safeName(deck.title)}.ink.json',
          inkBytes.length,
          inkBytes,
        ),
      );
    }

    final userNotes = UserNotesCodec.encode(
      packDeck.slides,
      packDeck.userNotes,
    );
    if (userNotes != null) {
      final userNotesBytes = utf8.encode(userNotes);
      archive.add(
        ArchiveFile(
          '${_safeName(deck.title)}.user-notes.json',
          userNotesBytes.length,
          userNotesBytes,
        ),
      );
    }

    // Thema-CSS (zodat het pakket ook in Marp/CLI bruikbaar is).
    final css = await _packageThemeCss(packDeck.theme, profile, logoRel);
    if (css != null) {
      final cssBytes = utf8.encode(css);
      final themeName = packDeck.theme.trim().isEmpty
          ? 'ocideck'
          : packDeck.theme;
      archive.add(
        ArchiveFile('themes/$themeName.css', cssBytes.length, cssBytes),
      );
    }

    return archive;
  }

  Future<String?> _packageThemeCss(
    String themeName,
    ThemeProfile profile,
    String? logoRel,
  ) async {
    final safe = themeName.trim().isEmpty ? 'ocideck' : themeName;
    try {
      final base = (await rootBundle.loadString(
        'assets/themes/ocideck.css',
      )).replaceFirst('@theme ocideck', '@theme $safe');
      return _buildThemeCss(
        base,
        profile,
        logoRel == null ? null : '../$logoRel',
      );
    } catch (e) {
      logWarning('FileService._packageThemeCss: theme asset not bundled', e);
      return null;
    }
  }

  /// Cap on how much we download / extract, to bound memory and disk use.
  ///
  /// Image-heavy decks routinely exceed 64 MiB, so keep the safety guard high
  /// enough for real presentation exchange while still bounding abuse.
  /// A deck's markdown is plain text; cap it so a crafted oversized `.md`
  /// can't exhaust memory on open. Generous — real decks are well under this.
  static const maxDeckMarkdownBytes = 32 * 1024 * 1024; // 32 MiB
  static const maxPackageBytes = 512 * 1024 * 1024; // 512 MiB
  static const maxPackageEntries = 10000;
  static const maxZipEntryPathLength = 512;

  /// Pak een pakket uit in een nieuwe submap onder [destParentDir]. Geeft het
  /// pad naar het uitgepakte markdown-bestand terug (om in een tab te openen).
  Future<String?> importPackageBytes(
    List<int> zipBytes,
    String destParentDir, {
    int maxBytes = maxPackageBytes,
  }) async {
    if (zipBytes.length > maxBytes) return null;

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e, s) {
      logError('FileService.importPackageBytes: ZIP decode failed', e, s);
      return null;
    }

    if (archive.files.length > maxPackageEntries) {
      logWarning(
        'FileService.importPackageBytes: too many archive entries '
        '(${archive.files.length})',
      );
      return null;
    }

    // Kies de markdown met het ondiepste pad (de hoofd-md van het pakket).
    ArchiveFile? mdEntry;
    for (final f in archive.files) {
      if (!f.isFile || !f.name.toLowerCase().endsWith('.md')) continue;
      if (mdEntry == null ||
          '/'.allMatches(f.name).length < '/'.allMatches(mdEntry.name).length) {
        mdEntry = f;
      }
    }
    if (mdEntry == null) return null;

    final folderName = p.basenameWithoutExtension(mdEntry.name);
    final destDir = _uniqueDir(destParentDir, folderName);
    await destDir.create(recursive: true);

    // Resolve an archive entry name to a path strictly inside [destDir], or
    // null when it would escape (zip-slip: `../`, absolute paths, …).
    String? safeOutPath(String entryName) {
      final resolved = p.normalize(p.join(destDir.path, entryName));
      if (resolved != destDir.path && !p.isWithin(destDir.path, resolved)) {
        return null;
      }
      return resolved;
    }

    var extracted = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name.length > maxZipEntryPathLength) continue;
      final outPath = safeOutPath(f.name);
      if (outPath == null) continue; // skip path-traversal entries
      // Reject before inflating: an entry that declares a huge uncompressed
      // size (zip bomb) must not be materialised into memory at all.
      if (f.size < 0 || extracted + f.size > maxBytes) {
        logWarning(
          'FileService.importPackageBytes: decompressed size exceeds limit',
        );
        return null;
      }
      // Decompressing a corrupt entry can throw; skip it instead of aborting.
      final List<int> content;
      try {
        content = f.content;
      } catch (e) {
        logWarning(
          'FileService.importPackageBytes: unreadable entry skipped (${f.name})',
          e,
        );
        continue;
      }
      // Backstop in case a header understated the real uncompressed size.
      extracted += content.length;
      if (extracted > maxBytes) {
        logWarning(
          'FileService.importPackageBytes: decompressed size exceeds limit',
        );
        return null;
      }
      final out = File(outPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(content, flush: true);
    }

    // The main markdown must itself resolve inside the extraction folder.
    final mdPath = safeOutPath(mdEntry.name);
    return mdPath;
  }

  Directory _uniqueDir(String parent, String name) {
    var dir = Directory(p.join(parent, name));
    var i = 2;
    while (dir.existsSync()) {
      dir = Directory(p.join(parent, '$name ($i)'));
      i++;
    }
    return dir;
  }

  /// Download een presentatie vanaf [url]. Een zip-pakket wordt uitgepakt;
  /// platte markdown wordt als losse `.md` opgeslagen. Geeft het pad naar het
  /// markdown-bestand terug.

  /// SSRF host/address guards live in [NetGuard] so the URL-import path and the
  /// live remote-media path share exactly the same rules.
  static bool _isBlockedHost(String host) => NetGuard.isBlockedHost(host);

  static Future<List<InternetAddress>?> _safeResolve(String host) =>
      NetGuard.safeResolve(host);

  Future<String?> importFromUrl(String url, String destParentDir) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    // Only fetch over web schemes, and never reach private/loopback hosts.
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (_isBlockedHost(uri.host)) return null;
    // Resolve the hostname up front and reject internal addresses.
    final safeAddrs = await _safeResolve(uri.host);
    if (safeAddrs == null) return null;
    final pinned = safeAddrs.first;

    final List<int> bytes;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        // Pin the socket to the validated address so a DNS rebind between the
        // check above and the actual connect can't point us at an internal IP.
        // TLS (for https) still validates against the original hostname.
        ..connectionFactory = (u, proxyHost, proxyPort) =>
            Socket.startConnect(pinned, u.port);
      try {
        final request = await client.getUrl(uri);
        // Don't auto-follow redirects: a 3xx could point at a private host and
        // bypass the SSRF check above.
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 200) return null;
        if (response.contentLength > maxPackageBytes) return null;
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
          if (builder.length > maxPackageBytes) return null; // runaway body
        }
        bytes = builder.takeBytes();
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      logError('FileService.importFromUrl: download failed', e);
      return null;
    }

    // Zip-magie 'PK\x03\x04' → pakket; anders als markdown behandelen.
    final isZip =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (isZip) {
      return importPackageBytes(bytes, destParentDir);
    }

    // Platte markdown.
    return importMarkdownBytes(bytes, destParentDir, uri.path);
  }

  /// Sla losse markdown-bytes op als zelfstandig deck in een nieuwe submap van
  /// [destParentDir] en geef het pad naar het `.md`-bestand terug. Weigert
  /// inhoud die niet op een Marp-deck lijkt of niet als UTF-8 te lezen is.
  /// Gedeeld door de URL-import en de WebDAV-bron.
  Future<String?> importMarkdownBytes(
    List<int> bytes,
    String destParentDir,
    String suggestedName,
  ) async {
    if (bytes.length > maxDeckMarkdownBytes) return null;
    final String markdown;
    try {
      markdown = utf8.decode(bytes);
    } catch (e, s) {
      logError('FileService.importMarkdownBytes: UTF-8 decode failed', e, s);
      return null;
    }
    if (!markdown.contains('marp') && !markdown.contains('---')) return null;

    var base = p.basenameWithoutExtension(suggestedName);
    if (base.isEmpty) base = 'presentatie';
    final destDir = _uniqueDir(destParentDir, base);
    await destDir.create(recursive: true);
    final mdPath = p.join(destDir.path, '$base.md');
    await writeStringAtomic(File(mdPath), markdown);
    return mdPath;
  }

  Future<String?> pickPackageFile({String? initialDirectory}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: _d('Pakket importeren'),
      type: FileType.custom,
      allowedExtensions: [packageExtension, 'zip'],
      initialDirectory: initialDirectory,
    );
    return result?.files.single.path;
  }

  Future<String?> pickPackageDestination(Deck deck) async {
    return FilePicker.saveFile(
      dialogTitle: _d('Pakket exporteren'),
      fileName: '${_safeName(deck.title)}.$packageExtension',
    );
  }

  Future<Deck> _writeProject(Deck deck, String filePath) async {
    final dir = p.dirname(filePath);

    final imagesDir = Directory(p.join(dir, 'images'));
    final logosDir = Directory(p.join(dir, 'logos'));
    final themesDir = Directory(p.join(dir, 'themes'));
    await imagesDir.create(recursive: true);
    await logosDir.create(recursive: true);
    await themesDir.create(recursive: true);

    final imageSlides = await _img.copyImagesToProject(deck.slides, dir);
    final mediaSlides = await _img.copyMediaToProject(imageSlides, dir);
    var updatedDeck = deck.copyWith(slides: mediaSlides, projectPath: dir);
    final logoAsset = await _copyLogoToProject(updatedDeck.themeProfile, dir);
    updatedDeck = updatedDeck.copyWith(themeProfile: logoAsset.profile);
    await _writeImageCaptions(updatedDeck);

    await _writeTheme(
      themesDir.path,
      updatedDeck.theme,
      updatedDeck.themeProfile,
      logoAsset.cssUrl,
    );

    // Bring linked chart CSVs along when saving to a new location.
    await _copyChartData(deck, dir);

    final markdown = _md.generateDeck(updatedDeck);
    await writeStringAtomic(File(filePath), markdown);
    // Annotations and user notes live in separate sidecars so the .md stays pure.
    await _writeSidecar(updatedDeck, filePath);
    await _writeUserNotesSidecar(updatedDeck, filePath);
    return updatedDeck;
  }

  Future<Deck> _hydrateImageCaptions(Deck deck) async {
    final slides = <Slide>[];
    for (final slide in deck.slides) {
      var next = slide;
      if (slide.imagePath.isNotEmpty) {
        final caption = await _captions.getCaption(
          slide.imagePath,
          basePath: deck.projectPath,
        );
        if (caption != null) next = next.copyWith(imageCaption: caption);
      }
      if (slide.imagePath2.isNotEmpty) {
        final caption = await _captions.getCaption(
          slide.imagePath2,
          basePath: deck.projectPath,
        );
        if (caption != null) next = next.copyWith(imageCaption2: caption);
      }
      slides.add(next);
    }
    return deck.copyWith(slides: slides);
  }

  Future<void> _writeImageCaptions(Deck deck) async {
    for (final slide in deck.slides) {
      if (slide.imagePath.isNotEmpty && slide.imageCaption.trim().isNotEmpty) {
        await _captions.saveCaption(
          slide.imagePath,
          slide.imageCaption,
          basePath: deck.projectPath,
        );
      }
      if (slide.imagePath2.isNotEmpty &&
          slide.imageCaption2.trim().isNotEmpty) {
        await _captions.saveCaption(
          slide.imagePath2,
          slide.imageCaption2,
          basePath: deck.projectPath,
        );
      }
    }
  }

  Future<void> _writeTheme(
    String themesPath,
    String themeName,
    ThemeProfile profile,
    String? logoUrl,
  ) async {
    final safeThemeName = themeName.trim().isEmpty ? 'ocideck' : themeName;
    final dest = File(p.join(themesPath, '$safeThemeName.css'));
    try {
      final base = (await rootBundle.loadString(
        'assets/themes/ocideck.css',
      )).replaceFirst('@theme ocideck', '@theme $safeThemeName');
      await writeStringAtomic(dest, _buildThemeCss(base, profile, logoUrl));
    } catch (e) {
      // Asset not bundled in this build context; skip
      logWarning('FileService._writeTheme: theme asset not bundled', e);
    }
  }

  Future<_LogoProjectAsset> _copyLogoToProject(
    ThemeProfile profile,
    String projectPath,
  ) async {
    final logoPath = profile.logoPath;
    if (logoPath == null || logoPath.trim().isEmpty) {
      return _LogoProjectAsset(profile, null);
    }

    final normalized = logoPath.replaceAll('\\', '/');
    final relativeLogoPath = p.posix.isRelative(normalized)
        ? p.posix.normalize(normalized)
        : null;
    if (relativeLogoPath != null && relativeLogoPath.startsWith('logos/')) {
      return _LogoProjectAsset(
        profile.copyWith(logoPath: relativeLogoPath),
        '../$relativeLogoPath',
      );
    }

    var sourcePath = p.isAbsolute(logoPath)
        ? logoPath
        : p.normalize(p.join(projectPath, logoPath));
    var src = File(sourcePath);
    if (!await src.exists()) {
      final fallback = await _findExistingProjectLogo(projectPath, normalized);
      if (fallback == null) {
        return _LogoProjectAsset(profile, null);
      }
      sourcePath = fallback;
      src = File(sourcePath);
    }

    final filename = p.posix.basename(normalized);
    if (filename.isEmpty || filename == '.' || filename == '..') {
      return _LogoProjectAsset(profile, null);
    }

    final relativePath = p.posix.join('logos', filename);
    final dest = File(p.join(projectPath, relativePath));
    if (!p.equals(src.path, dest.path)) {
      await dest.parent.create(recursive: true);
      await src.copy(dest.path);
    }

    return _LogoProjectAsset(
      profile.copyWith(logoPath: relativePath),
      '../$relativePath',
    );
  }

  Future<String?> _findExistingProjectLogo(
    String projectPath,
    String normalizedLogoPath,
  ) async {
    final filename = p.posix.basename(normalizedLogoPath);
    if (filename.isEmpty || filename == '.' || filename == '..') return null;

    final candidates = [
      p.join(projectPath, 'logos', filename),
      p.join(projectPath, 'images', filename),
      p.join(projectPath, 'images', 'logo_$filename'),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  String _buildThemeCss(String base, ThemeProfile profile, String? logoUrl) {
    final logoCss = logoUrl == null
        ? ''
        : '''

section.logo-safe {
  ${_logoSafePaddingCss(profile)}
}

section.split.logo-safe {
  padding: 48px 0 48px var(--split-margin);
}

${_splitLogoSafeCss(profile)}

section::before {
  content: "";
  position: absolute;
  width: ${profile.logoSize}px;
  height: ${profile.logoSize}px;
  background-image: url("$logoUrl");
  background-size: contain;
  background-repeat: no-repeat;
  background-position: center;
  opacity: 0.9;
  ${_logoPositionCss(profile.logoPosition)}
}

section.no-logo::before {
  display: none;
}
''';

    return '''
$base

/* OciDeck style profile */
section {
  background: ${profile.slideBackgroundColor};
  color: ${profile.textColor};
  position: relative;
}

section h1,
section h2,
section h3,
section strong {
  color: ${profile.textColor};
}

section li::marker {
  color: ${profile.accentColor};
}

section.title {
  background: ${profile.titleBackgroundColor};
  color: ${profile.titleTextColor};
}

section.title h1,
section.title h2 {
  color: ${profile.titleTextColor};
}

section.section {
  background: ${profile.sectionBackgroundColor};
  color: ${profile.titleTextColor};
}

section.section h1 {
  color: ${profile.titleTextColor};
}

table {
  border-collapse: collapse;
  width: 100%;
  font-size: 0.72em;
}

th, td {
  border: 1px solid ${profile.accentColor};
  padding: 0.22em 0.45em;
  text-align: left;
  color: ${profile.tableTextColor};
}

thead th, tr:first-child th {
  background: ${profile.tableHeaderBackgroundColor};
  color: ${profile.tableHeaderTextColor};
}
$logoCss
''';
  }

  String _logoPositionCss(String position) {
    switch (position) {
      case 'top-left':
        return 'top: 40px;\n  left: 28px;';
      case 'top-right':
        return 'top: 40px;\n  right: 28px;';
      case 'bottom-left':
        return 'bottom: 12px;\n  left: 28px;';
      case 'bottom-right':
      default:
        return 'bottom: 12px;\n  right: 28px;';
    }
  }

  String _logoSafePaddingCss(ThemeProfile profile) {
    switch (profile.logoPosition) {
      case 'top-left':
      case 'top-right':
        final reserved = profile.logoSize + 52;
        return 'padding-top: ${reserved}px;';
      case 'bottom-left':
      case 'bottom-right':
      default:
        final reserved = profile.logoSize + 24;
        return 'padding-bottom: ${reserved}px;';
    }
  }

  String _splitLogoSafeCss(ThemeProfile profile) {
    if (profile.logoPosition.endsWith('right')) return '';
    final reserved = profile.logoSize + 24;
    if (profile.logoPosition.startsWith('top')) {
      return '''
section.split.logo-safe .split-text {
  padding-top: ${reserved}px;
}
''';
    }
    return '''
section.split.logo-safe .split-text {
  padding-bottom: ${reserved}px;
}
''';
  }
}
