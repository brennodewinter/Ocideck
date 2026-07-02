// Part of the file_service library — see file_service.dart.
// Split out for navigability (portable .ocideck package building); all
// imports live in the main library file. The FileService methods relocate
// verbatim. Publieke extension: exportPackage/buildPackageBytes/
// buildPackageMembers worden buiten de library aangeroepen (tabs_provider).
part of '../file_service.dart';

extension FileServicePackage on FileService {
  String _safeName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return cleaned.isEmpty ? 'presentatie' : cleaned;
  }

  /// Sanitize a deck-supplied theme name before it becomes a file name. The
  /// `theme:` front-matter value is attacker-controlled, so `../` and other
  /// separators must be stripped or a write could escape the project's
  /// `themes/` directory (p.join collapses `../` on join). Falls back to
  /// `ocideck`. Strips the same characters as [_safeName]; `.` and `/` are not
  /// in `[\w\s-]`, so any traversal sequence is flattened away.
  String _safeThemeName(String themeName) {
    final cleaned = themeName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return cleaned.isEmpty ? 'ocideck' : cleaned;
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
  Future<List<int>> buildPackageBytes(Deck deck) async {
    final archive = await _buildPackageArchive(deck);
    // Zip-compressie is CPU-zwaar (media-assets kunnen honderden MB zijn);
    // in een eigen isolate blijft de UI responsief tijdens het pakken.
    return Isolate.run(() => ZipEncoder().encodeBytes(archive));
  }

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
    Future<String?> addAsset(String path, String subdir) async {
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
      if (!await file.exists()) return null;
      final rel = p.posix.join(subdir, p.basename(abs));
      if (!added.contains(rel)) {
        final bytes = await file.readAsBytes();
        archive.add(ArchiveFile(rel, bytes.length, bytes));
        added.add(rel);
      }
      return rel;
    }

    final slides = [
      for (final s in deck.slides)
        s.copyWith(
          imagePath: await addAsset(s.imagePath, 'images') ?? s.imagePath,
          imagePath2: await addAsset(s.imagePath2, 'images') ?? s.imagePath2,
          videoPath: await addAsset(s.videoPath, 'media') ?? s.videoPath,
          audioPath: await addAsset(s.audioPath, 'media') ?? s.audioPath,
        ),
    ];

    // Chart slides link their data via a CSV path inside the JSON block; bring
    // the file along under data/ and rewrite the path to match.
    final packedSlides = [
      for (final s in slides)
        if (s.type == SlideType.chart)
          await _packChartSlide(s, addAsset)
        else
          s,
    ];

    final logoRel = await addAsset(deck.themeProfile.logoPath ?? '', 'logos');
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
      final themeName = _safeThemeName(packDeck.theme);
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
    final safe = _safeThemeName(themeName);
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
}
