import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import '../models/deck.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../models/chart.dart';
import '../models/slide.dart';
import '../utils/atomic_file.dart';
import '../utils/bundled_asset.dart';
import '../utils/file_download.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';
import '../utils/project_path.dart';
import '../utils/zip_encryption.dart';
import 'annotation_codec.dart';
import 'user_notes_codec.dart';
import 'caption_service.dart';
import 'image_service.dart';
import 'markdown_safety.dart';
import 'markdown_service.dart';
import 'web_asset_store.dart';

part 'parts/file_service_net.dart';
part 'parts/file_service_open.dart';
part 'parts/file_service_package.dart';
part 'parts/file_service_dossier.dart';
part 'parts/file_service_project.dart';
part 'parts/file_service_import.dart';
part 'parts/file_service_style_profile.dart';

/// A presentation found on disk while scanning a directory.
class ScannedPresentation {
  final String path;
  final String fileName;
  final Deck deck;

  /// The raw markdown source, kept for maximal full-text search.
  final String content;

  /// Laatst-gewijzigd volgens het bestandssysteem, of null wanneer de stat
  /// mislukte. Toont bij naamgenoten met afwijkende inhoud welke kopie de
  /// recentste bewerking draagt.
  final DateTime? modified;

  const ScannedPresentation({
    required this.path,
    required this.fileName,
    required this.deck,
    this.content = '',
    this.modified,
  });

  /// A display label: the deck title, falling back to the file name without
  /// its extension. Mirrors [ScanHit.displayTitle].
  String get displayTitle {
    final t = deck.title.trim();
    if (t.isNotEmpty) return t;
    return p.basenameWithoutExtension(fileName);
  }
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

  /// Bestandsgrootte in bytes; voorfilter voor duplicaatdetectie (alleen
  /// even grote bestanden kúnnen identiek zijn, dus alleen die worden
  /// volledig gelezen en gehasht).
  final int size;

  /// Laatst-gewijzigd volgens het bestandssysteem, of null wanneer de stat
  /// mislukte. Toont bij naamgenoten met afwijkende inhoud welke kopie de
  /// recentste bewerking draagt.
  final DateTime? modified;

  const ScanHit({
    required this.path,
    required this.fileName,
    required this.title,
    required this.theme,
    required this.isOcideckTheme,
    this.size = 0,
    this.modified,
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

/// Eén lid van een `.ocideck`-pakket: archiefnaam plus uitgepakte bytes.
/// Het resultaat van de veilige zip-decodering ([FileService.decodePackageEntries]).
typedef PackageEntry = ({String name, Uint8List bytes});

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

/// Waarom een import (URL, pakket, WebDAV) geen deck opleverde — voor een
/// gerichte melding in plaats van een generiek "kon niet importeren".
enum ImportFailure {
  /// Bestand of pakket is groter dan de toegestane limiet.
  tooLarge,

  /// ZIP of tekst is beschadigd/onleesbaar.
  corrupt,

  /// Wel opgehaald, maar geen Marp/OciDeck-presentatie.
  unsupported,

  /// Veiligheidslimiet geraakt (zip-bomb, te veel entries).
  limitExceeded,

  /// Ophalen zelf mislukte (URL, verbinding, statuscode).
  network,

  /// Pakket is versleuteld maar er kon niet om een wachtwoord worden gevraagd
  /// (geen resolver geregistreerd — vooral in tests/headless).
  needsPassword,

  /// Pakket is versleuteld en de gebruiker brak de wachtwoordvraag af. Geen
  /// echte fout: de aanroeper toont hierbij géén foutmelding.
  encryptedCancelled,
}

/// Vraagt (interactief) het wachtwoord van een versleuteld pakket. [retry] is
/// waar na een onjuiste poging. Retourneert `null` als de gebruiker afbreekt.
/// De service kent geen UI; de shell levert een concrete implementatie aan.
typedef PackagePasswordResolver =
    Future<String?> Function({required bool retry});

/// Uitkomst van een import: het pad naar de hoofd-markdown bij succes, anders
/// een [failure] met de reden.
class ImportOutcome {
  final String? mdPath;
  final ImportFailure? failure;

  const ImportOutcome.ok(this.mdPath) : failure = null;
  const ImportOutcome.failed(this.failure) : mdPath = null;
}

class FileService {
  final MarkdownService _md;
  final ImageService _img;
  final ThemeProfile Function() _themeProfile;
  final String Function() _languageCode;
  final String? Function() _homeDirectory;
  final List<String> Function() _libraryPaths;
  final CaptionService _captions = CaptionService();

  /// Absoluut pad van een grafiekdatabestand → de data zoals die erin stond
  /// toen hij werd gelezen ([_hydrateCharts]), canoniek als [ChartSpec.dataToJson].
  ///
  /// De ijklijn waartegen [_writeChartData] bepaalt of de gebruiker de grafiek
  /// heeft bewerkt. Zonder die ijklijn zou elk opslaan het bestand overschrijven
  /// en dus elke bewerking van buiten de app — het spreadsheet-werkpad — stil
  /// ongedaan maken.
  final Map<String, String> _chartDataAtOpen = {};

  FileService(
    this._md,
    this._img,
    this._themeProfile, {
    String Function()? languageCode,
    String? Function()? homeDirectory,
    List<String> Function()? libraryPaths,
  }) : _languageCode = languageCode ?? (() => 'nl'),
       _homeDirectory = homeDirectory ?? (() => null),
       _libraryPaths = libraryPaths ?? (() => const []);

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
    // Een asset:-logo (ingebouwd profiel) is al overal laadbaar; op web is er
    // verder geen bestandssysteem om een relatief logopad in op te zoeken —
    // laat het profiel dan ongemoeid (het logo rendert als afwezig).
    if (logoPath == null ||
        logoPath.trim().isEmpty ||
        isBundledAssetPath(logoPath) ||
        kIsWeb ||
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
  /// skipped. Directories such as images/ and themes/ are ignored. The walk
  /// descends the full tree (up to [maxDepth], effectively unbounded for real
  /// folders) but is capped at [maxFilesVisited] parsed decks so a pathological
  /// tree can't hang the UI — each `.md` here is fully read and parsed, which is
  /// costlier than the frontmatter probe used by [scanKnownLocations].
  Future<List<ScannedPresentation>> scanPresentations(
    String directory, {
    String? excludePath,
    int maxDepth = 32,
    int maxFilesVisited = 5000,
  }) async {
    final root = Directory(directory);
    if (!await root.exists()) return [];

    final results = <ScannedPresentation>[];
    var visited = 0;
    var capped = false;
    Future<void> walk(Directory dir, int depth) async {
      if (capped) return;
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
        if (capped) return;
        if (entity is File) {
          if (!entity.path.toLowerCase().endsWith('.md')) continue;
          if (excludePath != null && p.equals(entity.path, excludePath)) {
            continue;
          }
          if (++visited > maxFilesVisited) {
            capped = true;
            logWarning(
              'FileService.scanPresentations: visited cap reached '
              '($maxFilesVisited files) — results truncated',
            );
            return;
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
            DateTime? modified;
            try {
              modified = (await entity.stat()).modified;
            } catch (e) {
              logWarning('FileService.scanPresentations: stat failed', e);
            }
            results.add(
              ScannedPresentation(
                path: entity.path,
                fileName: p.basename(entity.path),
                deck: deck,
                content: content,
                modified: modified,
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
  /// een download niet mee. Geeft de gebruikte bestandsnaam terug als de
  /// download startte, of `null` als dat mislukte. De statusbalk toont die naam
  /// zodat het deck na een download niet als "nog niet opgeslagen" oogt.
  ///
  /// Juist omdat er één los bestand vertrekt, gaat grafiekdata wél mee: een
  /// `source`-verwijzing naar `data/…` zou in de download een dood pad zijn en
  /// de grafiek leeg achterlaten.
  String? downloadDeckAsFile(Deck deck) {
    final markdown = _md.generateDeck(deck, inlineChartData: true);
    final name = '${_safeName(deck.title)}.md';
    return downloadTextFile(name, markdown) ? name : null;
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

  // ── Zelfstandig stijlprofiel ── zie parts/file_service_style_profile.dart.

  static const styleProfileExtension = 'ocideckstyle';

  /// Een stijlprofiel is een handvol kleuren plus hooguit één ingesloten logo;
  /// beide caps zijn ruim voor echt gebruik en begrenzen een gemaakt bestand.
  static const maxStyleProfileBytes = 16 * 1024 * 1024; // 16 MiB
  static const maxStyleProfileLogoBytes = 8 * 1024 * 1024; // 8 MiB

  // Import (URL/pakket/markdown) leeft in parts/file_service_import.dart;
  // hieronder staat alleen de gedeelde decode-/hergebruik-infrastructuur.

  /// Decodeer een pakket-zip veilig naar (naam → bytes)-leden, met dezelfde
  /// verdediging als de schijf-import: totale omvang, aantal entries,
  /// padlengte en een begrensde inflater die een zip-bom mid-decompressie
  /// stopt. Retourneert null bij elke weigering. Gedeeld door de schijf-import
  /// ([importPackageBytes]) en de in-memory pakket-open van de webversie.
  List<PackageEntry>? decodePackageEntries(
    List<int> zipBytes, {
    int maxBytes = maxPackageBytes,
    String? password,
  }) {
    if (zipBytes.length > maxBytes) return null;

    // AES-ontsleuteling muteert de invoerbuffer; werk op een kopie zodat de
    // bytes van de aanroeper (die deze soms opnieuw gebruikt) intact blijven.
    final input = password != null ? Uint8List.fromList(zipBytes) : zipBytes;
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(input, password: password);
    } catch (e, s) {
      logError('FileService.decodePackageEntries: ZIP decode failed', e, s);
      return null;
    }

    if (archive.files.length > maxPackageEntries) {
      logWarning(
        'FileService.decodePackageEntries: too many archive entries '
        '(${archive.files.length})',
      );
      return null;
    }

    final entries = <PackageEntry>[];
    var extracted = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name.length > maxZipEntryPathLength) continue;
      // Cheap early reject on the *declared* uncompressed size (a zip bomb can
      // understate this, so it is only a fast path, not the real guard).
      if (f.size < 0 || extracted + f.size > maxBytes) {
        logWarning(
          'FileService.decodePackageEntries: decompressed size exceeds limit',
        );
        return null;
      }
      final Uint8List content;
      if (password != null) {
        // Versleutelde leden: WinZip-AES wordt alleen door de content-getter
        // ontsleuteld — de streaming `writeContent` inflate-weg past de
        // AES-laag niet toe en zou onleesbare bytes opleveren. De begrenzing
        // valt hier terug op de gedeclareerde grootte (hierboven gecheckt) plus
        // de lopende totaalsom; de streaming-cap vervalt, wat aanvaardbaar is
        // voor pakketten die de gebruiker zelf versleutelde en ontgrendelde.
        final List<int> raw;
        try {
          raw = f.content;
        } catch (e) {
          logWarning(
            'FileService.decodePackageEntries: unreadable encrypted entry '
            'skipped (${f.name})',
            e,
          );
          continue;
        }
        if (extracted + raw.length > maxBytes) {
          logWarning(
            'FileService.decodePackageEntries: decrypted size exceeds limit',
          );
          return null;
        }
        content = raw is Uint8List ? raw : Uint8List.fromList(raw);
      } else {
        // Inflate into a capped stream that aborts the moment the entry exceeds
        // the remaining budget. This bounds peak memory per entry: unlike
        // `f.content` (which decodes the whole entry into memory before we can
        // check its size), the underlying inflater writes incrementally, so a
        // deflate bomb that understated its header size is stopped mid-inflation.
        final remaining = maxBytes - extracted;
        final capped = _CappedOutputStream(remaining);
        try {
          f.writeContent(capped);
          content = Uint8List.fromList(capped.getBytes());
        } on _ExtractionLimitException {
          logWarning(
            'FileService.decodePackageEntries: entry exceeds decompression '
            'limit (possible zip bomb): ${f.name}',
          );
          return null;
        } catch (e) {
          // Decompressing a corrupt entry can throw; skip it instead of aborting.
          logWarning(
            'FileService.decodePackageEntries: unreadable entry skipped '
            '(${f.name})',
            e,
          );
          continue;
        }
      }
      extracted += content.length;
      entries.add((name: f.name, bytes: content));
    }
    return entries;
  }

  /// De hoofd-markdown van een pakket: het `.md`-lid met het ondiepste pad.
  static PackageEntry? mainMarkdownEntry(List<PackageEntry> entries) {
    PackageEntry? mdEntry;
    for (final e in entries) {
      if (!e.name.toLowerCase().endsWith('.md')) continue;
      if (mdEntry == null ||
          '/'.allMatches(e.name).length < '/'.allMatches(mdEntry.name).length) {
        mdEntry = e;
      }
    }
    return mdEntry;
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

  /// Zip-magie 'PK\x03\x04' — herkent een .ocideck/zip-pakket aan zijn kop.
  static bool looksLikeZipBytes(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  /// True als [bytes] een met wachtwoord versleuteld pakket is (zie
  /// [isEncryptedZip]). Puur byte-inspectie, zonder het wachtwoord te kennen.
  static bool isEncryptedPackage(List<int> bytes) => isEncryptedZip(bytes);

  // ── Netwerk ── zie parts/file_service_net.dart voor de URL-import
  // (desktop, met SSRF-pinning) en de web-fetch met hulppunt-terugval.

  /// Open een deck puur uit in-memory markdown: dezelfde fail-closed volgorde
  /// als [openDeckDetailed] (veiligheidsscan → marp-sniff → parse → actief
  /// stijlprofiel), maar zonder enige bestandssysteemtoegang. Gebruikt door de
  /// web-URL-import: achter een URL zitten geen sidecars, projectmap of
  /// chart-CSV's, dus die hydratatie wordt bewust overgeslagen. [sourceName]
  /// labelt alleen de logregels.
  ({Deck? deck, OpenFailure? failure}) openDeckFromContent(
    String raw, {
    String? sourceName,
  }) {
    final findings = MarkdownSafetyScanner.scan(raw);
    if (findings.isNotEmpty) {
      logWarning(
        'FileService.openDeckFromContent: refused — executable content '
        '(${findings.length} finding(s))',
        sourceName,
      );
      return (deck: null, failure: OpenFailure.unsafe);
    }
    if (!_md.sniffFrontmatter(raw).marp) {
      logWarning(
        'FileService.openDeckFromContent: not a Marp/OciDeck presentation '
        '(no `marp: true` front matter)',
        sourceName,
      );
      return (deck: null, failure: OpenFailure.notPresentation);
    }
    final parsed = _md.parseDeck(raw);
    if (parsed == null) return (deck: null, failure: OpenFailure.corrupt);
    // Inhoud draagt geen opmaak; pas het actieve stijlprofiel toe bij openen.
    return (
      deck: parsed.copyWith(themeProfile: activeProfileFor(projectPath: null)),
      failure: null,
    );
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
