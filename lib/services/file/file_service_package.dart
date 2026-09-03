// Part of the file_service library — see file_service.dart.
// Split out for navigability (portable .ocideck package building); all
// imports live in the main library file. The FileService methods relocate
// verbatim. Publieke extension: exportPackage/buildPackageBytes/
// buildPackageMembers worden buiten de library aangeroepen (tabs_provider).
part of '../file_service.dart';

extension FileServicePackage on FileService {
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
    int budgetBytes = FileService.maxPackageBytes,
  }) async {
    final bytes = await buildPackageBytes(
      deck,
      password: password,
      budgetBytes: budgetBytes,
    );
    await writeBytesAtomic(File(destPath), bytes);
  }

  /// Bouw de bytes van een zelfstandig `.ocideck`-pakket (zie [exportPackage]),
  /// zonder ze weg te schrijven. Gebruikt om hetzelfde pakket te uploaden naar
  /// een WebDAV-bron of (op web) als download aan te bieden.
  ///
  /// Met een niet-leeg [password] versleutelt de `ZipEncoder` elk lid met
  /// WinZip-AES-256. Een leeg/`null` wachtwoord levert een gewoon, onversleuteld
  /// pakket op (bestaand gedrag).
  Future<Uint8List> buildPackageBytes(
    Deck deck, {
    String? password,
    int budgetBytes = FileService.maxPackageBytes,
  }) async {
    final archive = await _buildPackageArchive(deck, budgetBytes: budgetBytes);
    final pw = (password != null && password.isNotEmpty) ? password : null;
    // Zip-compressie is CPU-zwaar (media-assets kunnen honderden MB zijn);
    // in een eigen isolate blijft de UI responsief tijdens het pakken. Op web
    // bestaan isolates niet en pakt de main thread — merkbaar, maar werkend.
    if (kIsWeb) return ZipEncoder(password: pw).encodeBytes(archive);
    return Isolate.run(() => ZipEncoder(password: pw).encodeBytes(archive));
  }

  /// Web: bouw het pakket in het geheugen en bied het de browser als download
  /// aan. In tegenstelling tot de kale `.md`-download reizen de afbeeldingen
  /// (mem:-assets) en sidecars hier mee.
  ///
  /// Retourneert de gebruikte bestandsnaam, of `null` als de browser de
  /// download niet aannam — de schil meldt dan geen pakket dat er niet is
  /// (#1902).
  Future<String?> downloadPackage(Deck deck, {String? password}) async {
    final bytes = await buildPackageBytes(deck, password: password);
    final name = _packageFileName(deck);
    return deliverAsDownload([
      (name: name, bytes: bytes),
    ], bundleName: bundleNameFor(name));
  }

  /// Pakket-leden (pad → bytes) zonder ze te zippen, zodat elk bestand los naar
  /// een WebDAV-map kan worden geüpload — een "platte" spiegel van het deck met
  /// dezelfde asset-mappen en herschreven relatieve paden als het pakket.
  Future<Map<String, List<int>>> buildPackageMembers(
    Deck deck, {
    int budgetBytes = FileService.maxPackageBytes,
  }) async {
    final archive = await _buildPackageArchive(deck, budgetBytes: budgetBytes);
    return _flatMembers(archive);
  }

  Future<Archive> _buildPackageArchive(
    Deck deck, {
    int budgetBytes = FileService.maxPackageBytes,
  }) async {
    final archive = Archive();
    final added = <String>{};
    // Cumulative package budget, aligned to the importer's ceiling so a package
    // this version writes is one this version can reopen (#1046). Every member's
    // bytes are reserved here — file assets are stat'd before they are read, so
    // an oversized one fails fast instead of being pulled fully into memory.
    final budget = _PackageBudget(budgetBytes);
    void reserve(int n) => budget.reserve(n);

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
      reserve(bytes.length);
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
      // Stat before read: reserve the on-disk size so an oversized asset trips
      // the budget without first being pulled into memory (#1046).
      reserve(await file.length());
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
    final logoDarkRel = await addAsset(
      deck.themeProfile.logoDarkPath ?? '',
      'logos',
    );
    final profile = (logoRel != null || logoDarkRel != null)
        ? deck.themeProfile.copyWith(
            logoPath: logoRel ?? deck.themeProfile.logoPath,
            logoDarkPath: logoDarkRel ?? deck.themeProfile.logoDarkPath,
          )
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
    await _addThemeCssMember(archive, packDeck, profile, logoRel);

    // Cumulative guard over every member (markdown, sidecars, theme CSS and
    // chart data on top of the reserved assets), so the total the importer will
    // weigh cannot exceed its ceiling — the compressed zip is no larger than the
    // sum of these raw bytes for the media that dominates a package (#1046).
    _assertArchiveWithinBudget(archive, budgetBytes);

    return archive;
  }

  /// Voeg de thema-CSS als lid `themes/<naam>.css` toe, zodat het pakket ook in
  /// Marp/CLI bruikbaar blijft. Zonder gebundeld thema-asset ([_packageThemeCss]
  /// gaf `null`) blijft het pakket zonder CSS.
  Future<void> _addThemeCssMember(
    Archive archive,
    Deck packDeck,
    ThemeProfile profile,
    String? logoRel,
  ) async {
    final css = await _packageThemeCss(packDeck.theme, profile, logoRel);
    if (css == null) return;
    final cssBytes = utf8.encode(css);
    final themeName = _safeThemeName(packDeck.theme);
    archive.add(
      ArchiveFile('themes/$themeName.css', cssBytes.length, cssBytes),
    );
    // Marp CLI laadt een stylesheet naast de deck niet uit zichzelf; dit
    // configuratielid registreert de thema-CSS via `themeSet`, zodat een
    // uitgepakt pakket met `marp <naam>.md` de lay-out behoudt (#1804).
    final cfgBytes = utf8.encode(
      '# OciDeck Marp CLI configuration.\n'
      '# Registers the generated theme so a plain `marp deck.md -o out.html`\n'
      '# (run from this folder) loads it. Marp does not auto-discover a\n'
      '# stylesheet placed beside the deck; this config is the standard route.\n'
      'themeSet:\n'
      '  - themes/$themeName.css\n',
    );
    archive.add(ArchiveFile('.marprc.yml', cfgBytes.length, cfgBytes));
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
    member('$base.miauw.json', MiauwCodec.encodeDisposition(packDeck.miauw));
    member('$base.seal.json', SealCodec.encode(SealRecord.of(packDeck)));
    final setAside = packDeck.dismissals;
    if (setAside != null) {
      member('$base.dismissals.json', DismissalCodec.encode(setAside));
    }
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

/// Cumulative byte budget for a package under construction. Reserving a
/// member's bytes before it is materialised lets an oversized asset trip
/// [PackageBudgetExceeded] fast, without first pulling it into memory (#1046).
class _PackageBudget {
  _PackageBudget(this.limitBytes);

  final int limitBytes;
  int _used = 0;

  void reserve(int n) {
    if (_used + n > limitBytes) {
      throw PackageBudgetExceeded(usedBytes: _used, limitBytes: limitBytes);
    }
    _used += n;
  }
}

/// Final cumulative guard over every archive member, so the total the importer
/// will weigh cannot exceed its ceiling (#1046).
void _assertArchiveWithinBudget(Archive archive, int budgetBytes) {
  final total = archive.files.fold<int>(0, (sum, f) => sum + f.content.length);
  if (total > budgetBytes) {
    throw PackageBudgetExceeded(usedBytes: total, limitBytes: budgetBytes);
  }
}

/// Maak van een deck-titel een veilige bestandsnaam-stam. Gedeelde
/// sanitizer uit `lib/utils/safe_filename.dart`; valt terug op `presentatie`.
String _safeName(String title) =>
    sanitizeFilename(title, fallback: 'presentatie');

/// Sanitize a deck-supplied theme name before it becomes a file name. The
/// `theme:` front-matter value is attacker-controlled, so `../` and other
/// separators must be stripped or a write could escape the project's
/// `themes/` directory (p.join collapses `../` on join). Falls back to
/// `ocideck`. Strips the same characters as [_safeName]; `.` and `/` are not
/// in `[\w\s-]`, so any traversal sequence is flattened away.
String _safeThemeName(String themeName) =>
    sanitizeFilename(themeName, fallback: 'ocideck');

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

/// De dia's die in een pakket horen te belanden — dezelfde regel als overal
/// elders ([slideReachesAudience]), zodat er niet opnieuw een tweede exemplaar
/// van het predicaat ontstaat. Een dia op *overslaan*, of met een strengere
/// eigen TLP dan het deck, is onzichtbaar in presenter, zaalscherm en PDF en
/// hoort dus ook niet in het pakket.
List<Slide> _packSlides(Deck deck) => [
  for (final s in deck.slides)
    if (slideReachesAudience(s, presentationTlp: deck.tlp, includeDetail: true))
      s,
];

/// Een nog vrije plek in het archief voor [abs], onder [subdir]. Twee bestanden
/// met dezelfde naam uit verschillende mappen krijgen allebei een eigen lid via
/// een oplopend volgnummer.
String _freeArchivePath(Set<String> added, String subdir, String abs) {
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

/// Thrown while building a package when the assets would push it past
/// [FileService.maxPackageBytes] — the very limit the importer enforces
/// ([tabs_provider_import]). Without this a single big video could produce a
/// package OciDeck itself then refuses to reopen, and reading it would demand
/// gigabytes of memory (#1046). Assets are stat'd before being read, so the
/// export fails fast with this rather than after materialising the bytes.
class PackageBudgetExceeded implements Exception {
  const PackageBudgetExceeded({
    required this.usedBytes,
    required this.limitBytes,
  });

  /// Bytes already reserved for the package when the limit was hit.
  final int usedBytes;

  /// The cumulative ceiling, aligned to [FileService.maxPackageBytes].
  final int limitBytes;

  @override
  String toString() =>
      'PackageBudgetExceeded(used: $usedBytes, limit: $limitBytes)';
}

/// An [OutputStream] that refuses to grow past [limit] bytes. The archive
/// inflater writes decompressed output incrementally, so throwing here stops a
/// zip bomb mid-inflation instead of after the whole entry is in memory.
class _CappedOutputStream extends OutputMemoryStream {
  _CappedOutputStream(this.limit);

  final int limit;

  void _guard(int add) {
    if (length + add > limit) throw const ExtractionLimitException();
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

/// Een archief als platte kaart pad → bytes, mappen weggelaten. Gedeeld door de
/// pakket- en dossierleden, en top-level omdat het niets van [FileService]
/// nodig heeft — de klasse zat tegen haar plafond.
Map<String, List<int>> _flatMembers(Archive archive) => {
  for (final f in archive.files)
    if (f.isFile) f.name: f.content,
};

/// De bestandsnaam van een `.ocideck`-pakket voor [deck]. Stond op drie plekken
/// letterlijk uitgeschreven.
String _packageFileName(Deck deck) =>
    '${_safeName(deck.title)}.${FileService.packageExtension}';

/// Idem voor het auditdossier, dat een eigen achtervoegsel draagt zodat het niet
/// voor een gewoon pakket wordt aangezien.
String _dossierFileName(Deck deck) =>
    '${_safeName(deck.title)}_auditdossier.${FileService.packageExtension}';
