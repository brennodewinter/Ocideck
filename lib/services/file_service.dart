import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException, rootBundle;
import '../models/deck.dart';
import '../l10n/app_localizations.dart';
import '../models/markdown_document.dart';
import '../models/settings.dart';
import '../models/chart.dart';
import '../models/seal_record.dart';
import '../models/slide.dart';
import '../platform/platform_features.dart';
import '../utils/archive_limits.dart';
import '../utils/atomic_file.dart';
import '../utils/safe_filename.dart';
import '../utils/bundled_asset.dart';
import '../utils/log.dart';
import '../utils/markdown_files.dart';
import '../utils/json_depth_guard.dart';
import '../utils/net_guard.dart';
import '../utils/pinned_http_client.dart';
import '../utils/file_extension.dart';
import '../utils/project_path.dart';
import '../utils/zip_encryption.dart';
import 'download_delivery.dart';
import 'net/transport_failure.dart';
import 'annotation_codec.dart';
import 'document_integrity.dart';
import 'seal_codec.dart';
import 'miauw_codec.dart';
import 'privacy/dismissal_codec.dart';
import 'sidecar_format.dart';
import 'user_notes_codec.dart';
import 'caption_service.dart';
import 'image_service.dart';
import 'markdown_safety.dart';
import 'markdown_service.dart';
import 'open_file_channel.dart';
import 'slide_image_refs.dart';
import 'web_asset_store.dart';

part 'file/file_service_net.dart';
part 'file/file_service_open.dart';
part 'file/file_service_package.dart';
part 'file/file_service_dossier.dart';
part 'file/file_service_project.dart';
part 'file/file_service_import.dart';
part 'file/file_service_import_dirs.dart';
part 'file/file_service_scan.dart';
part 'file/file_service_style_profile.dart';

/// Een bewerkbaar Markdown-bestand dat op schijf is gevonden: een presentatie
/// ([deck] gevuld) of een plat document ([deck] null).
///
/// Beide soorten komen uit dezelfde mapwandeling, want dat is wat iemand zoekt
/// die zijn werk terug wil vinden: "mijn bestanden", niet "mijn decks". Welke
/// van de twee het is volgt uit de afwezigheid van `marp: true` (zie
/// [MarkdownKind]); er komt geen tweede detectiemechanisme bij.
class ScannedMarkdown {
  const ScannedMarkdown({
    required this.path,
    required this.fileName,
    this.deck,
    this.content = '',
    this.modified,
  });

  final String path;
  final String fileName;

  /// Het geparseerde deck, of null wanneer dit een plat document is.
  final Deck? deck;

  /// The raw markdown source, kept for maximal full-text search.
  final String content;

  /// Laatst-gewijzigd volgens het bestandssysteem, of null wanneer de stat
  /// mislukte. Toont bij naamgenoten met afwijkende inhoud welke kopie de
  /// recentste bewerking draagt.
  final DateTime? modified;

  /// Presentatie of document (zie [MarkdownKind]).
  MarkdownKind get kind =>
      deck == null ? MarkdownKind.document : MarkdownKind.presentation;

  /// A display label: the deck title, else the document's first heading, else
  /// the file name without its extension. Mirrors [ScanHit.displayTitle].
  String get displayTitle {
    final t = (deck?.title ?? firstMarkdownHeading(content) ?? '').trim();
    if (t.isNotEmpty) return t;
    return p.basenameWithoutExtension(fileName);
  }
}

/// A presentation found on disk while scanning a directory: een
/// [ScannedMarkdown] waarvan vaststáát dat er een deck in zit, zodat de
/// slide-zoekers (importeren, dia zoeken, netwerkbronnen) niet elk hun eigen
/// null-controle hoeven te herhalen.
class ScannedPresentation extends ScannedMarkdown {
  const ScannedPresentation({
    required super.path,
    required super.fileName,
    required Deck super.deck,
    super.content,
    super.modified,
  });

  @override
  Deck get deck => super.deck!;
}

/// Een bestand dat de brede schijfscan vond. Unlike [ScannedPresentation]
/// this is a lightweight record built from a frontmatter probe only — no full
/// parse — so scanning large folder trees stays cheap.
///
/// De scan levert zowel Marp-presentaties als platte documenten op; [kind] zegt
/// welke van de twee. Dat is geen extra detectie: het is dezelfde
/// `marp: true`-sniff die het openen gebruikt (zie [MarkdownKind]).
class ScanHit {
  final String path;
  final String fileName;

  /// Title from the frontmatter, or null when the deck omits one.
  final String? title;

  /// The declared `theme:` value, or null when absent. Een document draagt er
  /// geen (die sleutel is Marp-eigen), dus daar is dit altijd null.
  final String? theme;

  /// Presentatie of document. Standaard [MarkdownKind.presentation], zodat
  /// bestaande aanroepers die alleen decks kennen ongewijzigd blijven werken.
  final MarkdownKind kind;

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
    this.kind = MarkdownKind.presentation,
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

  /// De browserstore heeft geen ruimte meer voor de assets uit dit deck.
  memoryBudgetExceeded,

  /// The file could not be read (stat failed, not valid UTF-8, …).
  unreadable,

  /// The file carries executable content and was refused (security).
  unsafe,

  /// The file is not a Marp/OciDeck presentation (no `marp: true`).
  notPresentation,

  /// The markdown is present but truncated or unparseable.
  corrupt,
}

/// Vraagt (interactief) het wachtwoord van een versleuteld pakket. [retry] is
/// waar na een onjuiste poging. Retourneert `null` als de gebruiker afbreekt.
/// De service kent geen UI; de shell levert een concrete implementatie aan.
typedef PackagePasswordResolver =
    Future<String?> Function({required bool retry});

/// Vraagt of de web-import mag terugvallen op het same-origin fetch-hulppunt.
///
/// Die terugval stuurt de hele URL naar de origin die de app serveert — een
/// partij die de gebruiker niet zelf heeft aangewezen, en de URL kan een
/// deelsleutel bevatten. Daarom een vraag en geen automatisme. [host] is de
/// bronhost, zodat de vraag concreet kan zijn. De service kent geen UI; de
/// shell levert de implementatie. Geen implementatie = geen toestemming.
typedef ProxyFallbackConfirm = Future<bool> Function({required String host});

/// Uitkomst van een import: het pad naar de hoofd-markdown bij succes, anders
/// een [failure] met de reden.
class ImportOutcome {
  final String? mdPath;
  final ImportFailure? failure;

  const ImportOutcome.ok(this.mdPath) : failure = null;
  const ImportOutcome.failed(this.failure) : mdPath = null;
}

/// Vraagt de gebruiker waar een bestand naartoe moet. Standaard het
/// systeemvenster (`FilePicker.saveFile`).
///
/// Eén dunne indirectie, met opzet niet meer dan dat: het bewaar-venster is het
/// enige stuk van het uitvoerpad dat onder `flutter test` niet bestaat — de
/// plugin wordt daar niet geregistreerd — en zonder deze naad is álles
/// eráchter onbereikbaar: de classificatiepoort, het wachtwoorddialoog, het
/// wegschrijven en de meldingen aan de gebruiker. Volgt het patroon dat
/// [FileService] al gebruikt voor `homeDirectory` en `libraryPaths`.
typedef SaveDestinationPicker =
    Future<String?> Function({
      String? dialogTitle,
      String? fileName,
      String? initialDirectory,
    });

Future<String?> _systemSaveDestination({
  String? dialogTitle,
  String? fileName,
  String? initialDirectory,
}) async {
  // file_picker 12's saveFile requires bytes and writes them non-atomically.
  // file_selector's getSaveLocation gives just a path, preserving writeBytesAtomic.
  final location = await getSaveLocation(
    suggestedName: fileName,
    initialDirectory: initialDirectory,
  );
  return location?.path;
}

/// Everything that reaches the filesystem on a deck's behalf: opening and
/// saving, the project folder around a `.md`, the sidecars, the `.ocideck`
/// package, and scanning a library for decks.
///
/// The invariant worth knowing before you change anything here: **a save must
/// never leave a half-written deck on disk.** Writes go to a temporary file and
/// are moved into place, because the alternative — a truncated `.md` where the
/// user's presentation used to be — is the one failure this application cannot
/// apologise its way out of.
///
/// The second rule is containment: an asset path that resolves outside the
/// project folder is refused rather than followed. A deck is something people
/// exchange, so its paths are untrusted input.
///
/// What not to expect: it does not know the Markdown format ([MarkdownService]
/// does) and it does not decide *when* to save — that is [DeckNotifier] and the
/// tab layer. On web most of this degrades to in-memory behaviour; the platform
/// gates in `lib/platform/` say which parts.
class FileService {
  final MarkdownService _md;
  final ImageService _img;
  final ThemeProfile Function() _themeProfile;
  final String Function() _languageCode;
  final String? Function() _homeDirectory;
  final List<String> Function() _libraryPaths;
  final SaveDestinationPicker _saveDestination;
  final CaptionService _captions = CaptionService();

  /// Deck (zijn eigen `.md`, via [_deckChartKey]) → { absoluut pad van een
  /// grafiekdatabestand → de data zoals die erin stond toen hij werd gelezen
  /// ([_hydrateCharts]), canoniek als [ChartSpec.dataToJson] }.
  ///
  /// De ijklijn waartegen [_writeChartData] bepaalt of de gebruiker de grafiek
  /// heeft bewerkt. Zonder die ijklijn zou elk opslaan het bestand overschrijven
  /// en dus elke bewerking van buiten de app — het spreadsheet-werkpad — stil
  /// ongedaan maken.
  ///
  /// De buitenste laag is er omdat [FileService] één instantie is voor de hele
  /// app ([fileServiceProvider]) terwijl er meerdere decks tegelijk openstaan.
  /// Eén platte map maakte "de bestanden van dit deck" niet te onderscheiden
  /// van "de bestanden van elk deck dat deze sessie heeft geopend", en
  /// [_pruneChartData] wist dan het databestand van het ene deck bij het
  /// opslaan van het andere. Twee decks in dezelfde map is genoeg om dat te
  /// laten gebeuren, dus de sleutel is het deckpad en niet de projectmap.
  final Map<String, Map<String, String>> _chartDataAtOpen = {};

  /// De sleutel waaronder een deck zijn ijklijnen bewaart: zijn eigen `.md`,
  /// genormaliseerd zodat twee schrijfwijzen van hetzelfde pad samenvallen.
  static String _deckChartKey(String deckPath) => p.canonicalize(deckPath);

  FileService(
    this._md,
    this._img,
    this._themeProfile, {
    String Function()? languageCode,
    String? Function()? homeDirectory,
    List<String> Function()? libraryPaths,
    SaveDestinationPicker? saveDestination,
  }) : _languageCode = languageCode ?? (() => 'nl'),
       _homeDirectory = homeDirectory ?? (() => null),
       _libraryPaths = libraryPaths ?? (() => const []),
       _saveDestination = saveDestination ?? _systemSaveDestination;

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
      return _resolveLogoDarkPath(profile, projectPath);
    }

    final bases = [?projectPath, ?_homeDirectory()];
    for (final base in bases) {
      final candidate = p.normalize(p.join(base, logoPath));
      if (File(candidate).existsSync()) {
        return _resolveLogoDarkPath(
          profile.copyWith(logoPath: candidate),
          projectPath,
        );
      }
    }
    return _resolveLogoDarkPath(profile, projectPath);
  }

  /// Resolveert [ThemeProfile.logoDarkPath] op dezelfde manier als het lichte
  /// logo in [resolveThemeProfile]: relatief t.o.v. het project, tenzij het
  /// al absoluut, gebundeld of leeg is.
  ThemeProfile _resolveLogoDarkPath(ThemeProfile profile, String? projectPath) {
    final darkPath = profile.logoDarkPath;
    if (darkPath == null ||
        darkPath.trim().isEmpty ||
        isBundledAssetPath(darkPath) ||
        kIsWeb ||
        p.isAbsolute(darkPath)) {
      return profile;
    }
    final bases = [?projectPath, ?_homeDirectory()];
    for (final base in bases) {
      final candidate = p.normalize(p.join(base, darkPath));
      if (File(candidate).existsSync()) {
        return profile.copyWith(logoDarkPath: candidate);
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

  /// Recursively scan [directory] for editable Markdown files and read them:
  /// Marp presentations are parsed into decks, plain Markdown documents are
  /// kept as source. [excludePath] (typically the currently open file) is
  /// skipped. Directories such as images/ and themes/ are ignored. The walk
  /// descends the full tree (up to [maxDepth], effectively unbounded for real
  /// folders) but is capped at [maxFilesVisited] read files so a pathological
  /// tree can't hang the UI — each file here is fully read, which is costlier
  /// than the frontmatter probe used by [scanKnownLocations]. Two size guards
  /// ([maxDeckMarkdownBytes] per file, [maxScanBytes] cumulative) keep a
  /// pathological tree from exhausting memory; see [_scanOneFile].
  ///
  /// [includeDocuments] laat de platte documenten weg voor de aanroepers die
  /// per se dia's nodig hebben (dia zoeken, slides importeren) — zie
  /// [scanPresentations].
  Future<List<ScannedMarkdown>> scanMarkdownFiles(
    String directory, {
    String? excludePath,
    bool includeDocuments = true,
    int maxDepth = 32,
    int maxFilesVisited = 5000,
    int maxScanBytes = 256 * 1024 * 1024,
  }) => walkMarkdownFiles(
    this,
    directory,
    excludePath: excludePath,
    includeDocuments: includeDocuments,
    maxDepth: maxDepth,
    maxFilesVisited: maxFilesVisited,
    maxScanBytes: maxScanBytes,
  );

  /// Alleen de presentaties uit [scanMarkdownFiles] — voor de aanroepers die
  /// dia's nodig hebben en dus niets aan een plat document hebben.
  Future<List<ScannedPresentation>> scanPresentations(
    String directory, {
    String? excludePath,
    int maxDepth = 32,
    int maxFilesVisited = 5000,
    int maxScanBytes = 256 * 1024 * 1024,
  }) async => (await scanMarkdownFiles(
    directory,
    excludePath: excludePath,
    includeDocuments: false,
    maxDepth: maxDepth,
    maxFilesVisited: maxFilesVisited,
    maxScanBytes: maxScanBytes,
  )).whereType<ScannedPresentation>().toList();

  /// Directories the broad scan never descends into, on top of [_ignoredDirs]:
  /// large system trees that can't hold user presentations.
  static const _scanDenylistDirs = {
    'Library',
    'Applications',
    'System',
    'Pods',
    'Caches',
  };

  /// Only the first slice of each file is read for the frontmatter probe; the
  /// header always lives at the very top, so 64 KiB is plenty.
  static const _scanHeadBytes = 64 * 1024;

  /// Scan a fixed set of well-known locations (parent folders of [recentFiles],
  /// plus the user's Documents/Desktop/Downloads/iCloud and configured home
  /// directory) for editable Markdown files, using a cheap frontmatter probe
  /// rather than a full parse.
  ///
  /// Zowel presentaties als platte documenten komen terug ([ScanHit.kind] zegt
  /// welke); [includeDocuments] laat de documenten weg voor een aanroeper die
  /// per se dia's nodig heeft. OciDeck-themed decks are flagged via
  /// [ScanHit.isOcideckTheme] and sorted first. The walk is bounded by
  /// [maxDepth], [maxFilesVisited] and [maxMatches] so a pathological tree
  /// can't hang the UI; [onProgress] reports the current folder and match count,
  /// and [isCancelled] lets the caller abort.
  Future<List<ScanHit>> scanKnownLocations({
    List<String> recentFiles = const [],
    void Function(String phase, int found)? onProgress,
    bool Function()? isCancelled,
    bool includeDocuments = true,
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
          if (!isEditableMarkdownFile(entity.path)) continue;
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
          final hit = await _probeMarkdown(
            entity,
            includeDocuments: includeDocuments,
          );
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

    // Presentaties eerst (OciDeck-thema vooraan), dan de documenten, elk op
    // weergavetitel. Het is één lijst met twee soorten erin; op soort groeperen
    // scheelt de gebruiker het uit elkaar houden van rijen die er anders om en
    // om staan — en het filter in het scherm haalt de andere soort weg.
    hits.sort((a, b) {
      if (a.kind != b.kind) return a.kind.isPresentation ? -1 : 1;
      if (a.isOcideckTheme != b.isOcideckTheme) {
        return a.isOcideckTheme ? -1 : 1;
      }
      return a.displayTitle.toLowerCase().compareTo(
        b.displayTitle.toLowerCase(),
      );
    });
    return hits;
  }

  Future<String?> pickMarkdownFile({String? initialDirectory}) async {
    // Geen extensiefilter op macOS: zie [_pickPathGated] (eigen NSOpenPanel die
    // onthouden UTI-filters wist). Elders FileType.any via file_picker. De
    // inhoudspoort ([openFileByPath]) bepaalt daarna deck vs. document.
    //
    // Op web levert dit null: zie [_pickPathGated]. De aanroepers sturen daar
    // al naar [pickDeckFileBytes], dat met bytes werkt in plaats van een pad.
    return _pickPathGated(
      dialogTitle: _d('Presentatie openen'),
      type: FileType.any,
      initialDirectory: initialDirectory,
    );
  }

  /// Kies een presentatiebestand en lever de inhoud als bytes — het open-pad
  /// voor web, waar bestanden geen pad hebben. `withData` laat de browser de
  /// gekozen file in het geheugen aanleveren; desktop werkt ook (leest de
  /// bytes), maar gebruikt normaliter [pickMarkdownFile].
  Future<({String name, Uint8List bytes})?> pickDeckFileBytes() =>
      _pickBytes(dialogTitle: _d('Presentatie openen'));

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
    return deliverTextAsDownload(name, markdown);
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

  /// #1951: de laatste-wijzigingstijd van [filePath], of null als het bestand
  /// niet bestaat of niet gelezen kan worden. Gebruikt om te detecteren of
  /// een ander venster of programma het bestand ondertussen heeft geschreven.
  Future<DateTime?> fileMtime(String filePath) async {
    try {
      return await File(filePath).lastModified();
    } on FileSystemException {
      return null;
    }
  }

  /// #1951: of het bestand op [filePath] sinds [knownMtime] is gewijzigd of
  /// verwijderd. Geeft false als er niets om te vergelijken is (geen mtime
  /// bij openen) of als het bestand niet gelezen kan worden — kan het niet
  /// vaststellen, dus niet blokkeren.
  Future<bool> fileChangedSince(String filePath, DateTime? knownMtime) async {
    if (knownMtime == null) return false;
    try {
      final file = File(filePath);
      if (!await file.exists()) return true;
      return await file.lastModified() != knownMtime;
    } on FileSystemException {
      return false;
    }
  }

  /// Like [openDeck], but reports *why* it could not open a file so callers can
  /// tell the user (e.g. "this isn't a presentation") instead of a generic
  /// failure. Returns `(deck: <deck>, failure: null)` on success, or
  /// `(deck: null, failure: <reason>)` on any refusal.
  Future<DeckOpenResult> openDeckDetailed(
    String filePath, {
    String? content,
  }) async {
    // Cap → exists → UTF-8 read → fail-closed safety scan. Shared verbatim with
    // the document-open path so both inherit the same order and the same guards
    // (the scan runs on the exact bytes each path parses next).
    final read = await _readAndScanMarkdown(filePath, content);
    if (read.failure != null) {
      return DeckOpenResult.failed(read.failure!);
    }
    final raw = read.raw!;
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
      return const DeckOpenResult.failed(OpenFailure.notPresentation);
    }
    final parsed = _md.parseDeck(raw, filePath: filePath);
    if (parsed == null) {
      return const DeckOpenResult.failed(OpenFailure.corrupt);
    }
    // Front matter zonder body is een lége presentatie, geen kapotte. Hier
    // stond de omgekeerde regel (#1350: een afgebroken download opent niet stil
    // als een bijna-leeg deck), maar die rustte op een aanname die niet klopte —
    // "een geldige opslag schrijft altijd minstens één diablok". Een dia die nog
    // leeg is serialiseert naar niets, dus dít is precies de vorm die OciDeck
    // zélf wegschrijft voor een presentatie waarvan de enige dia nog leeg is.
    // Gevolg was #1909: het opslaan las zijn eigen zojuist geschreven bestand
    // niet meer terug en meldde dat aan de gebruiker als een fout.
    //
    // Afgekapt en leeg zijn in de bytes niet te onderscheiden — ze zijn
    // identiek — dus er viel niets te verfijnen, alleen te kiezen. De keuze
    // valt om drie redenen deze kant op: wat we schrijven moeten we kunnen
    // teruglezen; front matter zonder body is geldige Marp die een andere
    // editor ons mag aanreiken, en die weigeren breekt de uitwisselbelofte; en
    // waarschuwen bij élke lege presentatie zou de normale toestand tot
    // uitzondering maken. Wat we opgeven is de melding, niet de inhoud: bij een
    // echt afgekapt bestand was de body al weg vóór wij hem lazen, en de
    // gebruiker ziet een lege presentatie.

    // The file carries only content; apply the active style profile on open.
    final deck = parsed.copyWith(
      themeProfile: activeProfileFor(projectPath: parsed.projectPath),
    );
    final chartWarnings = <String>[];
    final skipped = <String>[];
    var hydrated = await _hydrateCharts(
      await _hydrateImageCaptions(deck),
      chartWarnings,
      deckPath: filePath,
    );
    // Losse lagen naast de markdown; alleen bij lezen van schijf.
    if (content == null) {
      hydrated = await _attachSidecars(hydrated, filePath, skipped);
    }
    // Automatische zegelverificatie bij het openen: na hydratatie van de
    // seal-sidecar (die sealHash zet) de fileHash berekenen uit de raw bytes
    // en verifiëren. Read-only — een veranderd deck mag nog steeds openen,
    // maar de gebruiker moet weten dat het zegel niet meer klopt.
    IntegrityStatus? integrity;
    if (content == null) {
      final fileHash = DocumentIntegrity.hashMarkdown(raw);
      integrity = DocumentIntegrity(
        _md,
      ).verify(hydrated.copyWith(fileHash: fileHash));
      if (integrity == IntegrityStatus.notSealed ||
          integrity == IntegrityStatus.notVerifiable) {
        integrity = null;
      }
    }
    return DeckOpenResult(
      deck: hydrated,
      warnings: chartWarnings,
      skippedSidecars: skipped,
      integrity: integrity,
    );
  }

  /// Als [saveDeckAs], maar mét de grafiekdata-waarschuwingen.
  ///
  /// Zie [saveDeckDetailed]: een grafiek waarvan het databestand niet geschreven
  /// kon worden, houdt zijn cijfers nergens meer, dus dat moet de gebruiker
  /// horen. `path` is null wanneer de gebruiker het venster wegklikte.
  Future<({String? path, List<String> chartWarnings})> saveDeckAsDetailed(
    Deck deck, {
    String? initialDirectory,
  }) async {
    final safeName = deck.title
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), '')
        .replaceAll(' ', '_');
    final result = await _saveDestinationGated(
      picker: _saveDestination,
      dialogTitle: _d('Opslaan als'),
      fileName: '$safeName.md',
      initialDirectory: initialDirectory,
    );
    if (result == null) return (path: null, chartWarnings: const <String>[]);
    final path = withExtension(result, '.md');
    final written = await _writeProject(deck, path);
    return (path: path, chartWarnings: written.chartWarnings);
  }

  Future<String?> saveDeckAs(Deck deck, {String? initialDirectory}) async =>
      (await saveDeckAsDetailed(deck, initialDirectory: initialDirectory)).path;

  /// Sla op én vertel welke grafieken hun cijfers niet kwijt konden.
  ///
  /// Het opslaan haalt de cijfers uit de markdown en zet ze in `data/`; mislukt
  /// dat tweede deel — pad buiten de projectmap, schijf vol, geen rechten, of
  /// het bestand is ondertussen buiten de app gewijzigd — dan bestaan die
  /// cijfers alleen nog in dit venster. De aanroeper hoort dat te melden;
  /// zwijgen zou een geslaagde opslag voorspiegelen. Spiegelbeeld van
  /// [openDeckDetailed], dat hetzelfde doet voor het lezen.
  Future<({Deck deck, List<String> chartWarnings})> saveDeckDetailed(
    Deck deck,
    String filePath,
  ) => _writeProject(deck, filePath);

  Future<Deck> saveDeck(Deck deck, String filePath) async =>
      (await _writeProject(deck, filePath)).deck;

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
  /// Grens voor een los grafiekdatabestand (`data/*.json`, of CSV).
  ///
  /// Grafiekdata reist naast het deck mee — uit een pakket, een repo of iemands
  /// map — en werd bij het openen onbegrensd ingelezen, met een tweede kopie
  /// bovenop zodra de CSV geparseerd werd. Het gaat om een handvol rijen; 8 MiB
  /// is ruim genoeg voor elke grafiek die een mens leest, en houdt een
  /// opgeblazen bestand buiten het geheugen van een app die nog aan het openen
  /// is en dus nog niets kan afbreken.
  static const maxChartDataBytes = 8 * 1024 * 1024; // 8 MiB

  /// Grens voor één sidecar naast een deck (`.ink.json`, `.user-notes.json`,
  /// `.miauw.json`, `.seal.json`).
  ///
  /// Dezelfde herkomst als grafiekdata — een sidecar reist met het deck mee uit
  /// een pakket, een repo of iemands map — en werd bij het openen onbegrensd
  /// ingelezen, met de kopie die `jsonDecode` erbovenop legt. De inkt-sidecar is
  /// veruit de grootste van de vier (punten per streek per slide) en blijft bij
  /// zwaar annoteren nog ruim onder deze grens; notities, MIAUW en het zegel
  /// tellen in kilobytes.
  static const maxDeckSidecarBytes = 16 * 1024 * 1024; // 16 MiB

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
          // **Fail-closed.** WinZip-AES toetst per lid een HMAC; `archive`
          // gooit hier ("macs don't match") zodra die niet klopt. Dat is geen
          // leesfout maar een bewijs van wijziging ná het versleutelen.
          //
          // Dit lid overslaan en doorgaan leverde stil een pakket op waar één
          // bestand uit verdwenen was — precies het lid dat een aanvaller
          // eruit wilde hebben. Wie een pakket versleutelt, doet dat om te
          // kunnen vertrouwen wat eruit komt; dan is een half pakket zonder
          // melding de verkeerde uitkomst. Het hele pakket wordt geweigerd.
          logError(
            'FileService.decodePackageEntries: encrypted entry failed its '
            'integrity check, refusing the package (${f.name})',
            e,
          );
          return null;
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
        } on ExtractionLimitException {
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
  /// chart-databestanden, dus die hydratatie wordt bewust overgeslagen. [sourceName]
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
    // Geen truncatie-check meer, om dezelfde reden als op het schijf-pad: een
    // lege body is een lege presentatie (#1909). Dit pad opende ook decks die
    // uit git of WebDAV terugkomen — dáár trof de weigering de gebruiker in
    // zijn eigen, keurig opgeslagen werk.
    // Inhoud draagt geen opmaak; pas het actieve stijlprofiel toe bij openen.
    return (
      deck: parsed.copyWith(themeProfile: activeProfileFor(projectPath: null)),
      failure: null,
    );
  }

  Future<String?> pickPackageFile({String? initialDirectory}) async {
    // FileType.any, geen `allowedExtensions`: dat filter grijst de zelfverzonnen
    // `.ocideck` juist úit op macOS (geen UTI) — zelfde reden als bij
    // [pickMarkdownFile]; [importPackageFile] toetst daarna de zip-kop.
    // Op web null (zie [_pickPathGated]); daar pakt `_openWithBytesPicker` uit.
    return _pickPathGated(
      dialogTitle: _d('Pakket importeren'),
      type: FileType.any,
      initialDirectory: initialDirectory,
    );
  }

  Future<String?> pickPackageDestination(Deck deck) async {
    return _saveDestination(
      dialogTitle: _d('Pakket exporteren'),
      fileName: _packageFileName(deck),
    );
  }
}

/// Vraagt waar een document-export (§11.2) naartoe moet. Anders dan een deck
/// (dat naast zijn `.md` landt) prompt een document om een pad: het is een
/// afgeleide, geredigeerde kopie voor een ontvanger — niet de meester.
/// [fileName] draagt al de juiste extensie (`.md`/`.html`) en het profiel
/// (`…-geredigeerd`), zodat een verwisseling zichtbaar is in de naam.
///
/// Top-level en niet op [FileService]: precies zoals [_systemSaveDestination] al
/// [FilePicker.saveFile] omhult, en omdat die klasse tegen haar plafond zit.
Future<String?> pickDocumentExportDestination({
  required String dialogTitle,
  required String fileName,
  String? initialDirectory,
}) async {
  final location = await getSaveLocation(
    suggestedName: fileName,
    initialDirectory: initialDirectory,
  );
  return location?.path;
}
