import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import '../models/deck.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../models/chart.dart';
import '../models/slide.dart';
import '../utils/atomic_file.dart';
import '../utils/file_download.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';
import '../utils/project_path.dart';
import 'annotation_codec.dart';
import 'user_notes_codec.dart';
import 'caption_service.dart';
import 'image_service.dart';
import 'markdown_safety.dart';
import 'markdown_service.dart';

part 'parts/file_service_open.dart';
part 'parts/file_service_package.dart';
part 'parts/file_service_project.dart';

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

/// Why [FileService.openDeckDetailed] could not open a file. Lets a caller tell
/// the user *why* (e.g. "this isn't a presentation") instead of a single
/// catch-all "couldn't open".
enum OpenFailure {
  /// The file does not exist.
  notFound,

  /// The file is larger than the deck-size cap.
  tooLarge,

  /// The file could not be read (stat failed, not valid UTF-8, …).
  unreadable,

  /// The file carries executable content and was refused (security).
  unsafe,

  /// The file is not a Marp/OciDeck presentation (no `marp: true`).
  notPresentation,

  /// The markdown is present but truncated or unparseable.
  corrupt,
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
    // Op web is er geen bestandssysteem om een relatief logopad in op te
    // zoeken; laat het profiel ongemoeid (het logo rendert dan als afwezig).
    if (kIsWeb ||
        logoPath == null ||
        logoPath.trim().isEmpty ||
        p.isAbsolute(logoPath)) {
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
    // FileType.any, not a custom-extension filter: on macOS an
    // `allowedExtensions: ['md']` filter greys out .md files in the native
    // panel, so a loose presentation anywhere on disk can't be picked. Any file
    // is selectable here; [openDeck] then validates that it is a Marp/OciDeck
    // presentation (front matter `marp: true`) and refuses anything else.
    final result = await FilePicker.pickFiles(
      dialogTitle: _d('Presentatie openen'),
      type: FileType.any,
      initialDirectory: initialDirectory,
    );
    return result?.files.single.path;
  }

  /// Kies een presentatiebestand en lever de inhoud als bytes — het open-pad
  /// voor web, waar bestanden geen pad hebben. `withData` laat de browser de
  /// gekozen file in het geheugen aanleveren; desktop werkt ook (leest de
  /// bytes), maar gebruikt normaliter [pickMarkdownFile].
  Future<({String name, Uint8List bytes})?> pickDeckFileBytes() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: _d('Presentatie openen'),
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    return (name: file.name, bytes: bytes);
  }

  /// Web-opslaan: serialiseer het deck en laat de browser het als `.md`
  /// downloaden. Bewust alleen de markdown-inhoud — sidecars (annotaties,
  /// sprekersnotities) en assets horen bij het desktop-projectmodel en gaan in
  /// een download niet mee. Geeft `false` terug als de download niet startte.
  bool downloadDeckAsFile(Deck deck) {
    final markdown = _md.generateDeck(deck);
    return downloadTextFile('${_safeName(deck.title)}.md', markdown);
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
  Future<Deck?> openDeck(String filePath, {String? content}) async =>
      (await openDeckDetailed(filePath, content: content)).deck;

  /// Like [openDeck], but reports *why* it could not open a file so callers can
  /// tell the user (e.g. "this isn't a presentation") instead of a generic
  /// failure. Returns `(deck: <deck>, failure: null)` on success, or
  /// `(deck: null, failure: <reason>)` on any refusal.
  Future<({Deck? deck, OpenFailure? failure})> openDeckDetailed(
    String filePath, {
    String? content,
  }) async {
    String raw;
    if (content != null) {
      raw = content;
    } else {
      final file = File(filePath);
      if (!await file.exists()) {
        return (deck: null, failure: OpenFailure.notFound);
      }
      // A deck is plain text (images/media are sidecar files), so a huge .md is
      // pathological. Cap it to avoid loading/parsing an attacker-sized file.
      try {
        if (await file.length() > maxDeckMarkdownBytes) {
          logWarning(
            'FileService.openDeck: file exceeds ${maxDeckMarkdownBytes ~/ (1024 * 1024)} MiB cap',
          );
          return (deck: null, failure: OpenFailure.tooLarge);
        }
      } catch (e) {
        logWarning('FileService.openDeck: cannot stat file', e);
        return (deck: null, failure: OpenFailure.unreadable);
      }
      try {
        raw = await file.readAsString();
      } catch (e) {
        // Non-UTF8 / unreadable bytes must not crash the open flow.
        logWarning('FileService.openDeck: file not readable as UTF-8', e);
        return (deck: null, failure: OpenFailure.unreadable);
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
      return (deck: null, failure: OpenFailure.unsafe);
    }
    // Only open Marp/OciDeck presentations. Every deck declares `marp: true` in
    // its front matter (the serializer always writes it), so this rejects an
    // arbitrary file picked via the now-unfiltered open dialog — a plain
    // README.md, a renamed binary, etc. — instead of opening it as a blank or
    // garbled deck.
    if (!_md.sniffFrontmatter(raw).marp) {
      logWarning(
        'FileService.openDeck: not a Marp/OciDeck presentation '
        '(no `marp: true` front matter)',
        filePath,
      );
      return (deck: null, failure: OpenFailure.notPresentation);
    }
    final parsed = _md.parseDeck(raw, filePath: filePath);
    if (parsed == null) return (deck: null, failure: OpenFailure.corrupt);
    // Guard against silently opening a truncated/corrupt file as a blank deck:
    // a valid save always emits at least one slide block after the frontmatter,
    // so a complete header with an empty body means the source was cut short.
    if (content == null && _looksTruncated(raw, parsed)) {
      logWarning(
        'FileService.openDeck: frontmatter present but no slide body',
        filePath,
      );
      return (deck: null, failure: OpenFailure.corrupt);
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
    return (deck: hydrated, failure: null);
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

  // ── Draagbaar pakket ── zie parts/file_service_package.dart voor de
  // pakket-bouw (exportPackage/buildPackageBytes/buildPackageMembers).

  static const packageExtension = 'ocideck';

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
      // Cheap early reject on the *declared* uncompressed size (a zip bomb can
      // understate this, so it is only a fast path, not the real guard).
      if (f.size < 0 || extracted + f.size > maxBytes) {
        logWarning(
          'FileService.importPackageBytes: decompressed size exceeds limit',
        );
        return null;
      }
      // Inflate into a capped stream that aborts the moment the entry exceeds
      // the remaining budget. This bounds peak memory per entry: unlike
      // `f.content` (which decodes the whole entry into memory before we can
      // check its size), the underlying inflater writes incrementally, so a
      // deflate bomb that understated its header size is stopped mid-inflation.
      final remaining = maxBytes - extracted;
      final capped = _CappedOutputStream(remaining);
      final List<int> content;
      try {
        f.writeContent(capped);
        content = capped.getBytes();
      } on _ExtractionLimitException {
        logWarning(
          'FileService.importPackageBytes: entry exceeds decompression limit '
          '(possible zip bomb): ${f.name}',
        );
        return null;
      } catch (e) {
        // Decompressing a corrupt entry can throw; skip it instead of aborting.
        logWarning(
          'FileService.importPackageBytes: unreadable entry skipped (${f.name})',
          e,
        );
        continue;
      }
      extracted += content.length;
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
}

/// Thrown by [_CappedOutputStream] when a decompressed entry would exceed its
/// byte budget — the signal that a package entry is a decompression bomb.
class _ExtractionLimitException implements Exception {
  const _ExtractionLimitException();
}

/// An [OutputStream] that refuses to grow past [limit] bytes. The archive
/// inflater writes decompressed output incrementally, so throwing here stops a
/// zip bomb mid-inflation instead of after the whole entry is in memory.
class _CappedOutputStream extends OutputMemoryStream {
  _CappedOutputStream(this.limit);

  final int limit;

  void _guard(int add) {
    if (length + add > limit) throw const _ExtractionLimitException();
  }

  @override
  void writeByte(int value) {
    _guard(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _guard(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _guard(stream.length);
    super.writeStream(stream);
  }
}
