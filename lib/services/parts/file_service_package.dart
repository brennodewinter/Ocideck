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
    // Bronpad → archiefpad, zodat hetzelfde bestand één keer wordt opgenomen en
    // twéé verschillende bestanden met dezelfde naam allebei meegaan.
    final byAbsolutePath = <String, String>{};
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
      final existing = byAbsolutePath[abs];
      if (existing != null) return existing;
      final rel = _freeArchivePath(added, subdir, abs);
      final bytes = await file.readAsBytes();
      archive.add(ArchiveFile(rel, bytes.length, bytes));
      added.add(rel);
      byAbsolutePath[abs] = rel;
      return rel;
    }

    final reaching = _packSlides(deck);
    final slides = <Slide>[];
    for (final s in reaching) {
      // Élke afbeelding gaat het archief in, ook een `![…](…)` in de vrije
      // tekst. Een pakket is bedoeld om weg te geven: wat er niet in zit, ziet
      // de ontvanger niet. Inpakken is asynchroon en herschrijven niet, dus
      // eerst elk pad naar zijn plek in het archief, dan de dia in haar geheel.
      final packed = <String, String>{};
      for (final path in slideImagePaths(s).toSet()) {
        final rel = await addAsset(path, 'images');
        if (rel != null) packed[path] = rel;
      }
      final withImages = rewriteSlideImagePaths(s, (path) => packed[path]);
      slides.add(
        withImages.copyWith(
          videoPath: await addAsset(s.videoPath, 'media') ?? s.videoPath,
          audioPath: await addAsset(s.audioPath, 'media') ?? s.audioPath,
        ),
      );
    }

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

    // De lagen naast de markdown (inkt, notities, MIAUW-dispositie) reizen als
    // eigen leden mee, zodat de `.md` in het pakket pure Marp blijft.
    _addSidecarMembers(archive, packDeck, _safeName(deck.title));

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

  /// Voeg de sidecar-leden van [packDeck] toe onder [base]: dezelfde
  /// bestandsnamen als naast een `.md` op schijf, zodat het openen van een
  /// pakket en het openen van een map dezelfde lagen terugvinden.
  ///
  /// Een lege laag levert geen lid op — een pakket zonder aantekeningen hoort
  /// geen leeg `.ink.json` mee te dragen.
  void _addSidecarMembers(Archive archive, Deck packDeck, String base) {
    void member(String name, String? json) {
      if (json == null) return;
      final bytes = utf8.encode(json);
      archive.add(ArchiveFile(name, bytes.length, bytes));
    }

    member(
      '$base.ink.json',
      AnnotationCodec.encode(packDeck.slides, packDeck.annotations),
    );
    member(
      '$base.user-notes.json',
      UserNotesCodec.encode(packDeck.slides, packDeck.userNotes),
    );
    member(
      '$base.miauw.json',
      MiauwCodec.encode(packDeck.miauwWaivers, packDeck.miauwConfirmations),
    );
  }

  /// Voeg een méégebundelde asset (asset:-pad, bv. het logo van een ingebouwd
  /// profiel) vanuit de rootBundle toe aan het pakket-archief.
  /// Een nog vrije plek in het archief voor [abs], onder [subdir].
  ///
  /// Twee bestanden met dezelfde naam uit verschillende mappen — een
  /// `screenshot.png` van het bureaublad en één uit Downloads — kregen dezelfde
  /// plek. De tweede werd dan niet geschreven maar kreeg wél dat pad terug, dus
  /// beide dia's wezen naar de inhoud van de eerste: het bewijs van de ene dia
  /// stond onder de andere, en van het origineel zat niets in het pakket. De
  /// `mem:`-tak hiernaast telde al door; deze niet.
  /// De dia's die in een pakket horen te belanden.
  ///
  /// Dit pad serialiseerde `deck.slides` rechtstreeks, en een pakket is de meest
  /// complete uitvoer die de app kent: de volledige markdown plus élke asset.
  /// Een dia die de auteur op *overslaan* zette, of waarvan de eigen TLP
  /// strenger is dan die van het deck, is onzichtbaar in de presenter, op het
  /// zaalscherm én in de PDF — en ging hier gewoon mee. Daar was geen
  /// instelling voor nodig: dit gebeurde bij een standaardinstallatie.
  ///
  /// Dezelfde regel als overal elders ([slideReachesAudience]), zodat er niet
  /// opnieuw een tweede exemplaar van het predicaat ontstaat.
  static List<Slide> _packSlides(Deck deck) => [
    for (final s in deck.slides)
      if (slideReachesAudience(
        s,
        presentationTlp: deck.tlp,
        includeDetail: true,
      ))
        s,
  ];

  static String _freeArchivePath(Set<String> added, String subdir, String abs) {
    final base = p.basenameWithoutExtension(abs);
    final ext = p.extension(abs);
    var rel = p.posix.join(subdir, '$base$ext');
    var i = 2;
    while (added.contains(rel)) {
      rel = p.posix.join(subdir, '$base ($i)$ext');
      i++;
    }
    return rel;
  }

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
