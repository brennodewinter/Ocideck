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
import 'annotation_codec.dart';
import 'caption_service.dart';
import 'image_service.dart';
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
      } catch (_) {
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
          } catch (_) {
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

  Future<String?> pickMarkdownFile({String? initialDirectory}) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: _d('Presentatie openen'),
      type: FileType.custom,
      allowedExtensions: ['md'],
      initialDirectory: initialDirectory,
    );
    return result?.files.single.path;
  }

  Future<Deck?> openDeck(String filePath, {String? content}) async {
    String raw;
    if (content != null) {
      raw = content;
    } else {
      final file = File(filePath);
      if (!await file.exists()) return null;
      raw = await file.readAsString();
    }
    final deck = _md.parseDeck(raw, filePath: filePath);
    if (deck == null) return null;
    final hydrated = await _hydrateCharts(await _hydrateImageCaptions(deck));
    // Re-attach the separate annotation layer from its sidecar, if present.
    if (content == null) {
      final sidecar = File(_sidecarPath(filePath));
      if (await sidecar.exists()) {
        try {
          final map = AnnotationCodec.decode(
            await sidecar.readAsString(),
            hydrated.slides,
          );
          if (map.isNotEmpty) return hydrated.copyWith(annotations: map);
        } catch (_) {
          // A broken sidecar must never block opening the deck.
        }
      }
    }
    return hydrated;
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
      await sidecar.writeAsString(json, flush: true);
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
      final abs = p.isAbsolute(spec.source!)
          ? spec.source!
          : p.join(deck.projectPath!, spec.source!);
      final file = File(abs);
      if (!await file.exists()) {
        slides.add(s);
        continue;
      }
      try {
        final csv = await file.readAsString();
        slides.add(s.copyWith(customMarkdown: spec.withCsv(csv).toBlock()));
        changed = true;
      } catch (_) {
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
      final from = File(p.join(deck.projectPath!, src));
      final toPath = p.join(destDir, src);
      if (from.path == toPath || !from.existsSync()) continue;
      final out = File(toPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(await from.readAsBytes(), flush: true);
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
    final archive = Archive();
    final added = <String>{};

    /// Resolve [path] (relatief t.o.v. projectPath of absoluut), voeg het
    /// bestand toe onder `<subdir>/<bestandsnaam>` en geef dat pad terug.
    String? addAsset(String path, String subdir) {
      if (path.trim().isEmpty) return null;
      final abs = p.isAbsolute(path)
          ? path
          : (deck.projectPath != null ? p.join(deck.projectPath!, path) : path);
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

    final bytes = ZipEncoder().encodeBytes(archive);
    await File(destPath).writeAsBytes(bytes, flush: true);
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
    } catch (_) {
      return null;
    }
  }

  /// Pak een pakket uit in een nieuwe submap onder [destParentDir]. Geeft het
  /// pad naar het uitgepakte markdown-bestand terug (om in een tab te openen).
  Future<String?> importPackageBytes(
    List<int> zipBytes,
    String destParentDir,
  ) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
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

    for (final f in archive.files) {
      if (!f.isFile) continue;
      final out = File(p.join(destDir.path, f.name));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: true);
    }

    return p.join(destDir.path, mdEntry.name);
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
  Future<String?> importFromUrl(String url, String destParentDir) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;

    final List<int> bytes;
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != 200) return null;
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
        }
        bytes = builder.takeBytes();
      } finally {
        client.close(force: true);
      }
    } catch (_) {
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
    final String markdown;
    try {
      markdown = utf8.decode(bytes);
    } catch (_) {
      return null;
    }
    if (!markdown.contains('marp') && !markdown.contains('---')) return null;

    var base = p.basenameWithoutExtension(uri.path);
    if (base.isEmpty) base = 'presentatie';
    final destDir = _uniqueDir(destParentDir, base);
    await destDir.create(recursive: true);
    final mdPath = p.join(destDir.path, '$base.md');
    await File(mdPath).writeAsString(markdown);
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
    await File(filePath).writeAsString(markdown);
    // Annotations live in a separate sidecar so the Marp .md stays pure.
    await _writeSidecar(updatedDeck, filePath);
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
      await dest.writeAsString(_buildThemeCss(base, profile, logoUrl));
    } catch (_) {
      // Asset not bundled in this build context; skip
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
  background: ${profile.accentColor};
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
    final reserved = profile.logoSize + 64;
    switch (profile.logoPosition) {
      case 'top-left':
      case 'top-right':
        return 'padding-top: ${reserved}px;';
      case 'bottom-left':
      case 'bottom-right':
      default:
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
