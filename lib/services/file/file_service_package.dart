// Part of the file_service library — see file_service.dart.
// Split out for navigability (portable .ocideck package building); all
// imports live in the main library file. The FileService methods relocate
// verbatim. Publieke extension: exportPackage/buildPackageBytes/
// buildPackageMembers worden buiten de library aangeroepen (tabs_provider).
part of '../file_service.dart';

Future<void> _addThemeCssArchiveMembers(
  FileService service,
  Archive archive,
  Deck deck,
  ThemeProfile profile,
  String? logoRel,
  String? brandStripRel,
) async {
  final css = await service._packageThemeCss(
    deck.theme,
    profile,
    logoRel,
    brandStripRel,
    deck.slideSize,
  );
  if (css == null) return;
  final cssBytes = utf8.encode(css);
  final themeName = _safeThemeName(deck.theme);
  archive.add(ArchiveFile('themes/$themeName.css', cssBytes.length, cssBytes));
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

ThemeProfile _profileWithPackageAssets(
  ThemeProfile profile,
  String? logoRel,
  String? logoDarkRel,
  String? brandStripRel,
  String? documentLogoRel,
) =>
    (logoRel != null ||
        logoDarkRel != null ||
        brandStripRel != null ||
        documentLogoRel != null)
    ? profile.copyWith(
        logoPath: logoRel ?? profile.logoPath,
        logoDarkPath: logoDarkRel ?? profile.logoDarkPath,
        brandStripPath: brandStripRel ?? profile.brandStripPath,
        documentLogoPath: documentLogoRel ?? profile.documentLogoPath,
      )
    : profile;

class _PackedThemeAssets {
  final ThemeProfile profile;
  final String? logoRel;
  final String? brandStripRel;

  const _PackedThemeAssets(this.profile, this.logoRel, this.brandStripRel);
}

final _packageBackgroundUrl = RegExp(
  r'''url\(\s*(["']?)(.*?)\1\s*\)''',
  caseSensitive: false,
);

Iterable<String> _packageBackgroundPaths(String value) sync* {
  for (final match in _packageBackgroundUrl.allMatches(value)) {
    final path = match.group(2)?.trim() ?? '';
    if (path.isNotEmpty) yield path;
  }
}

String _rewritePackageBackground(
  String value,
  String? Function(String path) map,
) => value.replaceAllMapped(_packageBackgroundUrl, (match) {
  final path = match.group(2)!.trim();
  final replacement = path.isEmpty ? null : map(path);
  if (replacement == null || replacement == path) return match.group(0)!;
  return 'url(${match.group(1)}$replacement${match.group(1)})';
});

Future<_PackedThemeAssets> _packThemeAssets(
  ThemeProfile profile,
  Future<String?> Function(String, String, {bool allowExternal}) addAsset,
) async {
  final logoRel = await addAsset(
    profile.logoPath ?? '',
    'logos',
    allowExternal: true,
  );
  final logoDarkRel = await addAsset(
    profile.logoDarkPath ?? '',
    'logos',
    allowExternal: true,
  );
  final brandStripRel = await addAsset(
    profile.brandStripPath ?? '',
    'logos',
    allowExternal: true,
  );
  final documentLogoRel = await addAsset(
    profile.documentLogoPath ?? '',
    'logos',
    allowExternal: true,
  );
  return _PackedThemeAssets(
    _profileWithPackageAssets(
      profile,
      logoRel,
      logoDarkRel,
      brandStripRel,
      documentLogoRel,
    ),
    logoRel,
    brandStripRel,
  );
}

Future<MarpStyle?> _packDeckBackground(
  Deck deck,
  Future<String?> Function(String, String) addAsset,
) async {
  final packed = <String, String>{};
  for (final path in _packageBackgroundPaths(deck.marpStyle.backgroundImage)) {
    final rel = await addAsset(path, 'images');
    if (rel != null) packed[path] = rel;
  }
  final rewritten = _rewritePackageBackground(
    deck.marpStyle.backgroundImage,
    (path) => packed[path],
  );
  return rewritten == deck.marpStyle.backgroundImage
      ? null
      : deck.marpStyle.copyWith(backgroundImage: rewritten);
}

List<PackageEntry>? _decodePackageEntries(
  List<int> zipBytes, {
  required int maxBytes,
  String? password,
  bool strictIntegrity = false,
}) {
  if (zipBytes.length > maxBytes) return null;

  // AES-ontsleuteling muteert de invoerbuffer. Een kopie houdt de bytes van de
  // aanroeper intact voor een eventuele nieuwe poging.
  final input = password != null ? Uint8List.fromList(zipBytes) : zipBytes;
  final Archive archive;
  try {
    final entryCount = readZipEntryCount(
      zipBytes,
      stopAfter: FileService.maxPackageEntries + 1,
    );
    if (entryCount == null || entryCount > FileService.maxPackageEntries) {
      logWarning('FileService.decodePackageEntries: too many archive entries');
      return null;
    }
    if (zipContainsSymlinkMetadata(zipBytes)) {
      logWarning(
        'FileService.decodePackageEntries: symbolic-link metadata rejected',
      );
      return null;
    }
    archive = ZipDecoder().decodeBytes(input, password: password);
  } catch (e, s) {
    logError('FileService.decodePackageEntries: ZIP decode failed', e, s);
    return null;
  }

  if (archive.files.length > FileService.maxPackageEntries) {
    logWarning(
      'FileService.decodePackageEntries: too many archive entries '
      '(${archive.files.length})',
    );
    return null;
  }

  final entries = <PackageEntry>[];
  final names = <String>{};
  var extracted = 0;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final normalizedName = p.posix.normalize(file.name);
    final invalidName =
        file.name.length > FileService.maxZipEntryPathLength ||
        p.posix.isAbsolute(file.name) ||
        normalizedName == '..' ||
        normalizedName.startsWith('../') ||
        !names.add(normalizedName);
    if (invalidName) {
      if (strictIntegrity) {
        logWarning(
          'FileService.decodePackageEntries: invalid or duplicate member',
        );
        return null;
      }
      continue;
    }
    // De gedeclareerde grootte is alleen een snelle eerste begrenzing; de
    // writer hieronder stopt ook een lid dat tijdens uitpakken groter blijkt.
    if (file.size < 0 || extracted + file.size > maxBytes) {
      logWarning(
        'FileService.decodePackageEntries: decompressed size exceeds limit',
      );
      return null;
    }
    final Uint8List content;
    final capped = _CappedOutputStream(maxBytes - extracted);
    try {
      _writePackageEntryCapped(file, capped);
      // De stream geeft al een zicht op zijn buffer; kopiëren verdubbelt de
      // geheugenpiek bij een groot uitgepakt lid.
      content = capped.getBytes();
    } on ExtractionLimitException {
      logWarning(
        'FileService.decodePackageEntries: entry exceeds decompression '
        'limit (possible zip bomb): ${file.name}',
      );
      return null;
    } catch (e) {
      if (password != null || strictIntegrity) {
        logWarning(
          'FileService.decodePackageEntries: unreadable entry in strict '
          'package, refusing all members',
          e,
        );
        return null;
      }
      logWarning(
        'FileService.decodePackageEntries: unreadable entry skipped '
        '(${file.name})',
        e,
      );
      continue;
    }
    extracted += content.length;
    entries.add((name: file.name, bytes: content));
  }
  return entries;
}

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
    // Reserve bytes before reading assets so oversized packages fail fast (#1046).
    final budget = _PackageBudget(budgetBytes);
    void reserve(int n) => budget.reserve(n);
    // Bronpad → archiefpad, zodat dubbele bronnen maar eenmaal meegaan.
    final byAbsolutePath = <String, String>{};
    // Stabiel lidpad per mem:-asset, zodat imagePath en imagePath2 die
    // dezelfde afbeelding delen ook hetzelfde pakket-lid krijgen.
    final memRels = <String, String>{};

    // Add a mem asset under a unique name in [subdir].
    String? addMemAsset(String path, String subdir) {
      final existing = memRels[path];
      if (existing != null) return existing;
      final bytes = WebAssetStore.bytesFor(path);
      // Store leeg (bv. pagina herladen): niets om in te pakken.
      if (bytes == null || !_packageAssetAllowed(bytes, subdir)) return null;
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

    /// Resolve [path] and add it under `<subdir>/<filename>`.
    Future<String?> addAsset(
      String path,
      String subdir, {
      bool allowExternal = false,
    }) async {
      if (path.trim().isEmpty) return null;
      if (WebAssetStore.isMemPath(path)) return addMemAsset(path, subdir);
      if (isBundledAssetPath(path)) {
        return _addBundledAssetTo(archive, added, path, subdir);
      }
      // URLs and other URI-backed assets are not local files for this packer;
      // leave them untouched rather than treating them as project paths.
      if (!p.isAbsolute(path) && Uri.tryParse(path)?.hasScheme == true) {
        return null;
      }
      // Zonder bestandssysteem (web) valt hier niets meer te lezen.
      if (kIsWeb) return null;
      final String abs;
      if (deck.projectPath != null && !allowExternal) {
        // Package export is a file-reading sink: follow symlinks as well as
        // lexical segments, so a project asset cannot escape its project.
        final resolved = resolveContainedRealPath(path, deck.projectPath);
        if (resolved == null) return '';
        abs = resolved;
      } else if (deck.projectPath != null && allowExternal) {
        final resolved = resolveTrustedAssetPath(path, deck.projectPath);
        if (resolved == null) return '';
        abs = resolved;
      } else if (AssetStaging.isStagedPath(path)) {
        final resolved = resolveContainedRealPath(path, AssetStaging.rootPath);
        if (resolved == null) return '';
        abs = resolved;
      } else if (allowExternal && p.isAbsolute(path)) {
        abs = path;
      } else {
        return '';
      }
      final file = File(abs);
      if (!await file.exists()) return null;
      final existing = byAbsolutePath[abs];
      if (existing != null) return existing;
      final rel = _freeArchivePath(added, subdir, abs);
      // Stat before read: reserve the on-disk size so an oversized asset trips
      // the budget without first being pulled into memory (#1046).
      reserve(await file.length());
      final bytes = await _readPkg(abs, subdir);
      if (bytes == null || !_packageAssetAllowed(bytes, subdir)) return '';
      archive.add(ArchiveFile(rel, bytes.length, bytes));
      added.add(rel);
      byAbsolutePath[abs] = rel;
      return rel;
    }

    final slides = await _packSlideAssets(
      deck: deck,
      archive: archive,
      added: added,
      byAbsolutePath: byAbsolutePath,
      reserve: reserve,
      addAsset: addAsset,
    );

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

    final themeAssets = await _packThemeAssets(deck.themeProfile, addAsset);
    final profile = themeAssets.profile;

    final packedDeckStyle = await _packDeckBackground(deck, addAsset);
    final packDeck = deck.copyWith(
      slides: packedSlides,
      themeProfile: profile,
      marpStyle: packedDeckStyle,
    );

    // Markdown.
    final markdown = _md.generateDeck(packDeck);
    final mdBytes = utf8.encode(markdown);
    archive.add(
      ArchiveFile('${_safeName(deck.title)}.md', mdBytes.length, mdBytes),
    );

    // De lagen naast de markdown (inkt, notities, MIAUW-dispositie) reizen als
    // eigen leden mee, zodat de `.md` in het pakket pure Marp blijft.
    _addSidecarMembers(archive, packDeck, _safeName(deck.title));

    // Het stijlrecord van de maker reist mee als `theme.json` — dezelfde vorm
    // als bij een OciServe-lespakket. Bij het openen geldt dit profiel voor
    // díe presentatie, zonder het globale actieve profiel van de ontvanger
    // te wijzigen (#2644). Alleen paden die de ontvanger kan betekenen
    // (gebundeld of pakket-relatief) gaan het record in. Marp leest dit lid
    // niet; daarvoor is de thema-CSS hieronder.
    final themeJson = utf8.encode(
      jsonEncode(<String, Object?>{
        'name': profile.name,
        'definition': packageProfileForThemeJson(profile).toJson(),
      }),
    );
    archive.add(ArchiveFile('theme.json', themeJson.length, themeJson));

    // Thema-CSS (zodat het pakket ook in Marp/CLI bruikbaar is).
    await _addThemeCssArchiveMembers(
      this,
      archive,
      packDeck,
      profile,
      themeAssets.logoRel,
      themeAssets.brandStripRel,
    );

    // Cumulative guard over every member (markdown, sidecars, theme CSS and
    // chart data on top of the reserved assets), so the total the importer will
    // weigh cannot exceed its ceiling — the compressed zip is no larger than the
    // sum of these raw bytes for the media that dominates a package (#1046).
    _assertArchiveWithinBudget(archive, budgetBytes);

    return archive;
  }

  /// Add exact evidence-PDF bytes after containment, size and magic checks.
  Future<String?> _addPdfEvidenceTo({
    required String path,
    required Deck deck,
    required Archive archive,
    required Set<String> added,
    required Map<String, String> byAbsolutePath,
    required void Function(int) reserve,
  }) async {
    if (kIsWeb || deck.projectPath == null) return null;
    // A Windows absolute path must not become a project-relative filename on
    // another host (where the native path parser treats backslashes literally).
    if (p.windows.isAbsolute(path) && !p.isAbsolute(path)) return null;
    final abs = resolveContainedRealPath(path, deck.projectPath);
    if (abs == null) return null;
    final existing = byAbsolutePath[abs];
    if (existing != null) return existing;
    final bytes = await _readPackagePdfEvidence(abs);
    if (bytes == null) return null;
    final rel = _freeArchivePath(added, 'evidence', abs);
    reserve(bytes.length);
    archive.add(ArchiveFile(rel, bytes.length, bytes));
    added.add(rel);
    byAbsolutePath[abs] = rel;
    return rel;
  }

  Future<List<Slide>> _packSlideAssets({
    required Deck deck,
    required Archive archive,
    required Set<String> added,
    required Map<String, String> byAbsolutePath,
    required void Function(int) reserve,
    required Future<String?> Function(String path, String subdir) addAsset,
  }) async {
    final slides = <Slide>[];
    for (final slide in _packSlides(deck)) {
      final packed = <String, String>{};
      final paths = {
        ...slideImagePaths(slide),
        ...htmlImagePaths(slide.customMarkdown),
        ..._packageBackgroundPaths(slide.marpStyle.backgroundImage),
      };
      for (final path in paths) {
        final rel = await addAsset(path, 'images');
        if (rel != null) packed[path] = rel;
      }
      var withImages = rewriteSlideImagePaths(slide, (path) => packed[path]);
      withImages = withImages.copyWith(
        customMarkdown: rewriteHtmlImagePaths(
          withImages.customMarkdown,
          (path) => packed[path],
        ),
        marpStyle:
            _rewritePackageBackground(
                  withImages.marpStyle.backgroundImage,
                  (path) => packed[path],
                ) ==
                withImages.marpStyle.backgroundImage
            ? null
            : withImages.marpStyle.copyWith(
                backgroundImage: _rewritePackageBackground(
                  withImages.marpStyle.backgroundImage,
                  (path) => packed[path],
                ),
              ),
      );
      final pdf = PdfEvidenceService.attachmentFromMarkdown(
        withImages.customMarkdown,
      );
      final pdfRel = pdf == null
          ? null
          : await _addPdfEvidenceTo(
              path: pdf.path,
              deck: deck,
              archive: archive,
              added: added,
              byAbsolutePath: byAbsolutePath,
              reserve: reserve,
            );
      final withEvidence = pdf == null
          ? withImages
          : pdfRel == null
          ? withImages.copyWith(customMarkdown: '')
          : withImages.copyWith(
              customMarkdown: PdfEvidenceService.markdownFor(
                pdfRel,
                label: pdf.label,
              ),
            );
      slides.add(
        withEvidence.copyWith(
          videoPath:
              await addAsset(slide.videoPath, 'media') ?? slide.videoPath,
          audioPath:
              await addAsset(slide.audioPath, 'media') ?? slide.audioPath,
        ),
      );
    }
    return slides;
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
    String? brandStripRel,
    PageSizeSpec? slideSize,
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
        brandStripRel == null ? null : '../$brandStripRel',
        slideSize,
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

  @override
  void writeBackReference(int distance, int count) {
    _guard(count);
    super.writeBackReference(distance, count);
  }
}

void _writePackageEntryCapped(ArchiveFile file, _CappedOutputStream output) {
  if (!kIsWeb) {
    file.writeContent(output);
    return;
  }
  // archive 4.3.0 negeert op web de meegegeven output bij DEFLATE en bouwt
  // eerst zelf de volledige body op. Gebruik daar zijn directe inflater.
  final raw = file.rawContent;
  if (raw is! ZipFile) throw const FormatException('ongeldig ZIP-lid');
  final compressed = raw.getStream(decompress: false); // Controleert AES-MAC.
  switch (file.compression) {
    case CompressionType.deflate:
      Inflate.stream(compressed, output: output);
      return;
    case CompressionType.bzip2:
      if (!BZip2Decoder().decodeStream(compressed, output)) {
        throw const FormatException('ongeldige BZip2-inhoud');
      }
      return;
    case CompressionType.none:
      output.writeStream(compressed);
      return;
    case null:
      throw const FormatException('onbekende ZIP-compressie');
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

bool _packageAssetAllowed(List<int> bytes, String subdir) => subdir == 'media'
    ? bytes.length <= ImageService.maxMediaBytes
    : bytes.length <= ImageService.maxImageBytes;

Future<List<int>?> _readPkg(String path, String subdir) async {
  final maxBytes = subdir == 'media'
      ? ImageService.maxMediaBytes
      : ImageService.maxImageBytes;
  final file = File(path);
  try {
    if (await file.length() > maxBytes) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (builder.length + chunk.length > maxBytes) return null;
      builder.add(chunk);
    }
    return builder.takeBytes();
  } on FileSystemException {
    return null;
  }
}

Future<Uint8List?> _readPackagePdfEvidence(String path) async {
  final file = File(path);
  try {
    final size = await file.length();
    if (size < 5 || size > maxPdfEvidenceBytes) return null;
    final bytes = Uint8List.fromList(await file.readAsBytes());
    return isSupportedPdfEvidence(bytes) ? bytes : null;
  } on FileSystemException {
    return null;
  }
}
