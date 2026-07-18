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
  ///
  /// Is [password] niet-leeg, dan wordt het pakket met AES-256 versleuteld (zie
  /// [buildPackageBytes]).
  Future<void> exportPackage(
    Deck deck,
    String destPath, {
    String? password,
  }) async {
    final bytes = await buildPackageBytes(deck, password: password);
    await writeBytesAtomic(File(destPath), bytes);
  }

  /// Bouw de bytes van een zelfstandig `.ocideck`-pakket (zie [exportPackage]),
  /// zonder ze weg te schrijven. Gebruikt om hetzelfde pakket te uploaden naar
  /// een WebDAV-bron of (op web) als download aan te bieden.
  ///
  /// Met een niet-leeg [password] versleutelt de `ZipEncoder` elk lid met
  /// WinZip-AES-256. Een leeg/`null` wachtwoord levert een gewoon, onversleuteld
  /// pakket op (bestaand gedrag).
  Future<Uint8List> buildPackageBytes(Deck deck, {String? password}) async {
    final archive = await _buildPackageArchive(deck);
    final pw = (password != null && password.isNotEmpty) ? password : null;
    // Zip-compressie is CPU-zwaar (media-assets kunnen honderden MB zijn);
    // in een eigen isolate blijft de UI responsief tijdens het pakken. Op web
    // bestaan isolates niet en pakt de main thread — merkbaar, maar werkend.
    if (kIsWeb) return ZipEncoder(password: pw).encodeBytes(archive);
    return Isolate.run(() => ZipEncoder(password: pw).encodeBytes(archive));
  }

  /// Web: bouw het pakket in het geheugen en bied het de browser als download
  /// aan. Retourneert de gebruikte bestandsnaam. In tegenstelling tot de kale
  /// `.md`-download reizen de afbeeldingen (mem:-assets) en sidecars hier mee.
  Future<String> downloadPackage(Deck deck, {String? password}) async {
    final bytes = await buildPackageBytes(deck, password: password);
    final name = '${_safeName(deck.title)}.${FileService.packageExtension}';
    await FilePicker.saveFile(fileName: name, bytes: bytes);
    return name;
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

  /// Schrijf de data van één grafiek als lid onder `data/` en geef het lidpad
  /// terug; [added] houdt naamconflicten uit elkaar.
  ///
  /// Bewust uit het geheugen, en niet door het bestand van schijf te kopiëren.
  /// Het deck in de editor kan bewerkingen bevatten die nog niet zijn
  /// opgeslagen; dan is het bestand op schijf verouderd en zou exporteren
  /// stilzwijgend de oude cijfers meesturen.
  String _addChartDataTo(
    Archive archive,
    Set<String> added,
    String name,
    String content,
  ) {
    final base = _safeName(p.basenameWithoutExtension(name));
    final ext = p.extension(name).toLowerCase() == '.csv' ? '.csv' : '.json';
    var rel = p.posix.join(chartDataDirName, '$base$ext');
    var i = 2;
    while (added.contains(rel)) {
      rel = p.posix.join(chartDataDirName, '$base (${i++})$ext');
    }
    final bytes = utf8.encode(content);
    archive.add(ArchiveFile(rel, bytes.length, bytes));
    added.add(rel);
    return rel;
  }

  Future<Archive> _buildPackageArchive(Deck deck) async {
    final archive = Archive();
    final added = <String>{};
    // Stabiel lidpad per mem:-asset, zodat imagePath en imagePath2 die
    // dezelfde afbeelding delen ook hetzelfde pakket-lid krijgen.
    final memRels = <String, String>{};

    /// Voeg een in-memory asset (mem:-pad uit de WebAssetStore) toe onder een
    /// unieke naam in [subdir]. Naamconflicten tussen verschillende assets
    /// krijgen een volgnummer.
    String? addMemAsset(String path, String subdir) {
      final existing = memRels[path];
      if (existing != null) return existing;
      final bytes = WebAssetStore.bytesFor(path);
      // Store leeg (bv. pagina herladen): niets om in te pakken.
      if (bytes == null) return null;
      final original = WebAssetStore.nameFor(path) ?? 'afbeelding.png';
      final base = _safeName(p.basenameWithoutExtension(original));
      final ext = p.extension(original).toLowerCase();
      final safeExt = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext) ? ext : '.png';
      var rel = p.posix.join(subdir, '$base$safeExt');
      var i = 2;
      while (added.contains(rel)) {
        rel = p.posix.join(subdir, '$base (${i++})$safeExt');
      }
      archive.add(ArchiveFile(rel, bytes.length, bytes));
      added.add(rel);
      memRels[path] = rel;
      return rel;
    }

    /// Resolve [path] (relatief t.o.v. projectPath, absoluut, mem: of
    /// asset:), voeg het bestand toe onder `<subdir>/<bestandsnaam>` en geef
    /// dat pad terug.
    Future<String?> addAsset(String path, String subdir) async {
      if (path.trim().isEmpty) return null;
      if (WebAssetStore.isMemPath(path)) return addMemAsset(path, subdir);
      if (isBundledAssetPath(path)) {
        return _addBundledAssetTo(archive, added, path, subdir);
      }
      // Zonder bestandssysteem (web) valt hier niets meer te lezen.
      if (kIsWeb) return null;
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

    // Chart slides link their data through a path inside the JSON block; write
    // that data as its own member under data/ and point the path at it.
    final packedSlides = [
      for (final s in slides)
        if (s.type == SlideType.chart)
          await _packChartSlide(
            s,
            (name, content) => _addChartDataTo(archive, added, name, content),
          )
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

  /// Voeg een méégebundelde asset (asset:-pad, bv. het logo van een ingebouwd
  /// profiel) vanuit de rootBundle toe aan het pakket-archief.
  Future<String?> _addBundledAssetTo(
    Archive archive,
    Set<String> added,
    String path,
    String subdir,
  ) async {
    final key = bundledAssetKey(path);
    final rel = p.posix.join(subdir, p.basename(key));
    if (!added.contains(rel)) {
      try {
        final bytes = (await rootBundle.load(key)).buffer.asUint8List();
        archive.add(ArchiveFile(rel, bytes.length, bytes));
        added.add(rel);
      } catch (e) {
        logWarning('FileService._addBundledAssetTo: asset niet gebundeld', e);
        return null;
      }
    }
    return rel;
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
