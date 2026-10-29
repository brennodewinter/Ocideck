// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (project (.md+assets) writing & theme CSS); all imports live in the main library
// file. These are private FileService helpers — they relocate verbatim
// into an extension on FileService, same library, no behaviour change.
part of '../file_service.dart';

/// Het opslaan-spiegelbeeld van `_pickPathGated` (file_service_import.dart):
/// kies een bestemmingspad voor het opslaan van een deck, op macOS via de
/// eigen `NSSavePanel`-kiezer.
///
/// `file_picker.saveFile` gebruikt op macOS `NSSavePanel.beginSheetModal` op
/// het Flutter-venster. Die sheet erft de `CFBundleDocumentTypes`-filter van
/// de app en verschijnt niet betrouwbaar — precies de reden dat
/// `pickMarkdownFile` via `pickUnfilteredMacFile` gaat. Het opslaan-pad kreeg
/// die behandeling voorheen niet, waardoor "Kies bestandsnaam…" na de
/// bestemmingsdialoog niets deed: de sheet verscheen niet, `saveFile` keerde
/// stil terug naar `null`, en `saveAs` rapporteerde `false` zonder melding.
///
/// [picker] is de injecteerbare systeem-kiezer (`FilePicker.saveFile` in
/// productie), zodat dit onder test niet van het echte paneel afhangt.
///
/// null = de gebruiker annuleerde — níet doorvallen naar [picker], anders
/// opent er een tweede kiezer (zelfde reden als `_pickPathGated`). Alleen een
/// oude build zonder native handler (`MissingPluginException`) valt terug.
Future<String?> _saveDestinationGated({
  required SaveDestinationPicker picker,
  required String dialogTitle,
  required String fileName,
  String? initialDirectory,
}) async {
  if (!kIsWeb && Platform.isMacOS) {
    try {
      return await saveMacFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: initialDirectory,
      );
    } on MissingPluginException {
      // Oude build zonder native handler: val terug op file_picker.
    }
  }
  return picker(
    dialogTitle: dialogTitle,
    fileName: fileName,
    initialDirectory: initialDirectory,
  );
}

Future<String?> _materializeMemStyleAsset(
  String memPath,
  String projectPath, {
  required String fallbackName,
}) async {
  final bytes = WebAssetStore.bytesFor(memPath);
  if (bytes == null || ImageService.imageMimeFromBytes(bytes) == null) {
    return null;
  }
  final rawName = WebAssetStore.nameFor(memPath) ?? fallbackName;
  final basename = p.basename(rawName);
  final filename = p.extension(basename).isEmpty
      ? '${p.basenameWithoutExtension(basename)}.png'
      : basename;
  final logosDir = await createContainedProjectDirectory(projectPath, 'logos');
  final destination = await resolveAssetDestinationForBytes(
    logosDir,
    filename,
    bytes,
  );
  if (destination == null) return null;
  if (!destination.alreadyPresent) {
    await writeBytesAtomic(destination.file, bytes);
  }
  return p.posix.join('logos', p.basename(destination.file.path));
}

/// Waar een profielafbeelding na het opslaan van een project staat.
///
/// [path] is gezet wanneer de bytes in `logos/` zijn beland. Blijft het leeg,
/// dan houdt het profiel zijn oude pad: een ontbrekende bron mag een nog
/// bruikbaar absoluut pad niet stil wissen.
class _StoredStyleImage {
  final String? path;

  const _StoredStyleImage.kept() : path = null;

  const _StoredStyleImage.stored(this.path);
}

/// Bewaart logo, donkere variant, documentlogo en merkstrook naast elkaar.
///
/// Twee bronnen met dezelfde bestandsnaam maar andere bytes krijgen een eigen
/// naam (`brand_2.png`). Identieke bytes delen één bestand. `null` op het
/// documentlogo blijft "gedeeld met de presentatie"; `''` blijft "bewust uit".
Future<({ThemeProfile profile, String? logoCssUrl, String? brandCssUrl})>
materializeProjectStyleImages(
  ThemeProfile profile,
  String projectPath, {
  String? sourceProjectPath,
}) async {
  final logo = await _storeProjectStyleImage(
    profile.logoPath,
    projectPath,
    sourceProjectPath: sourceProjectPath,
    fallbackName: 'logo.png',
  );
  var next = logo.path == null
      ? profile
      : profile.copyWith(logoPath: logo.path);
  final dark = await _storeProjectStyleImage(
    next.logoDarkPath,
    projectPath,
    sourceProjectPath: sourceProjectPath,
    fallbackName: 'logo-donker.png',
  );
  if (dark.path != null) next = next.copyWith(logoDarkPath: dark.path);
  final documentPath = next.documentLogoPath;
  if (documentPath != null && documentPath.trim().isNotEmpty) {
    final document = await _storeProjectStyleImage(
      documentPath,
      projectPath,
      sourceProjectPath: sourceProjectPath,
      fallbackName: 'document-logo.png',
    );
    if (document.path != null) {
      next = next.copyWith(documentLogoPath: document.path);
    }
  }
  final strip = await _storeProjectStyleImage(
    next.brandStripPath,
    projectPath,
    sourceProjectPath: sourceProjectPath,
    fallbackName: 'merkstrook.png',
  );
  if (strip.path != null) next = next.copyWith(brandStripPath: strip.path);
  return (
    profile: next,
    logoCssUrl: logo.path == null ? null : '../${logo.path}',
    brandCssUrl: strip.path == null ? null : '../${strip.path}',
  );
}

Future<_StoredStyleImage> _storeProjectStyleImage(
  String? rawPath,
  String projectPath, {
  required String? sourceProjectPath,
  required String fallbackName,
}) async {
  final path = rawPath?.trim();
  if (path == null || path.isEmpty || isBundledAssetPath(path)) {
    return const _StoredStyleImage.kept();
  }
  if (WebAssetStore.isMemPath(path)) {
    final stored = await _materializeMemStyleAsset(
      path,
      projectPath,
      fallbackName: fallbackName,
    );
    return stored == null
        ? const _StoredStyleImage.kept()
        : _StoredStyleImage.stored(stored);
  }
  final bytes = await _readProjectStyleImage(
    path,
    projectPath,
    sourceProjectPath,
  );
  if (bytes == null) return const _StoredStyleImage.kept();
  final stored = await _writeStyleImageBytes(
    bytes,
    _styleImageFileName(path, fallbackName),
    projectPath,
  );
  return stored == null
      ? const _StoredStyleImage.kept()
      : _StoredStyleImage.stored(stored);
}

String _styleImageFileName(String path, String fallbackName) {
  final base = p.posix.basename(path.replaceAll('\\', '/'));
  if (base.isEmpty || base == '.' || base == '..') return fallbackName;
  return p.extension(base).isEmpty ? '$base.png' : base;
}

Future<Uint8List?> _readProjectStyleImage(
  String path,
  String projectPath,
  String? sourceProjectPath,
) async {
  final normalized = path.replaceAll('\\', '/');
  final candidates = <String>[
    if (p.isAbsolute(path)) path,
    p.normalize(p.join(projectPath, path)),
    if (sourceProjectPath != null) p.normalize(p.join(sourceProjectPath, path)),
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (await file.exists()) {
      final bytes = await _styleImageBytes(file);
      if (bytes != null) return bytes;
    }
  }
  final fallback = await _findExistingProjectLogo(projectPath, normalized);
  if (fallback == null) return null;
  return _styleImageBytes(File(fallback));
}

/// Leest de bytes die het profiel al aanwijst. De kiezer heeft een
/// niet-afbeelding al geweigerd; hier opnieuw op handtekening toetsen zou een
/// bestaand logo (of een testbestand) als afwezig zien en het absolute pad
/// laten staan, zodat het project niet meeneembaar is.
Future<Uint8List?> _styleImageBytes(File file) async {
  try {
    final length = await file.length();
    if (length <= 0 || length > FileService.maxStyleProfileLogoBytes) {
      return null;
    }
    return await file.readAsBytes();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _writeStyleImageBytes(
  List<int> bytes,
  String filename,
  String projectPath,
) async {
  final logosDir = await createContainedProjectDirectory(projectPath, 'logos');
  final destination = await resolveAssetDestinationForBytes(
    logosDir,
    filename,
    bytes,
  );
  if (destination == null) return null;
  if (!destination.alreadyPresent) {
    await writeBytesAtomic(destination.file, bytes);
  }
  return p.posix.join('logos', p.basename(destination.file.path));
}

/// Zoekt een al gekopieerd logobestand terug wanneer het opgeslagen pad zelf
/// weg is — dezelfde volgorde als vóór de botsingsvrije kopie.
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

/// Relatieve `logos/`-paden van merkstrook en documentlogo worden absoluut
/// gemaakt tegen het project, net als het presentatielogo. Een leeg
/// documentlogo blijft leeg: dat is "bewust uit", niet "gedeeld".
ThemeProfile _resolveProjectRelativeStylePaths(
  ThemeProfile profile,
  String? projectPath,
  String? Function() homeDirectory,
) {
  final withStrip = _resolveOneRelativeStylePath(
    profile,
    profile.brandStripPath,
    projectPath,
    homeDirectory,
    (next, path) => next.copyWith(brandStripPath: path),
  );
  return _resolveOneRelativeStylePath(
    withStrip,
    withStrip.documentLogoPath,
    projectPath,
    homeDirectory,
    (next, path) => next.copyWith(documentLogoPath: path),
  );
}

ThemeProfile _resolveOneRelativeStylePath(
  ThemeProfile profile,
  String? rawPath,
  String? projectPath,
  String? Function() homeDirectory,
  ThemeProfile Function(ThemeProfile profile, String path) apply,
) {
  final path = rawPath?.trim();
  if (path == null ||
      path.isEmpty ||
      isBundledAssetPath(path) ||
      kIsWeb ||
      p.isAbsolute(path)) {
    return profile;
  }
  final bases = [?projectPath, ?homeDirectory()];
  for (final base in bases) {
    final candidate = p.normalize(p.join(base, path));
    if (File(candidate).existsSync()) return apply(profile, candidate);
  }
  return profile;
}

String _brandStripCss(
  ThemeProfile profile,
  String brandStripUrl,
  double slideHeightPx,
) {
  final edge = profile.logoPosition.startsWith('top') ? 'top' : 'bottom';
  final height = (slideHeightPx * profile.brandStripHeight).round();
  final safePadding = profile.logoPosition.startsWith('top')
      ? 'padding-top'
      : 'padding-bottom';
  final titleSubtitle = profile.titleSubtitleInBrandStrip
      ? '''
section.title.logo-safe h2 {
  position: absolute;
  left: 58px;
  $edge: ${(height * 0.30).round()}px;
  z-index: 2;
  color: ${profile.accentColor};
  font-size: 18px;
}
'''
      : '';
  return '''
section.logo-safe {
  $safePadding: ${height}px;
}

section.logo-safe::before {
  content: "";
  position: absolute;
  left: 0;
  $edge: 0;
  width: 100%;
  height: ${height}px;
  background: url("$brandStripUrl") center / 100% 100% no-repeat;
  opacity: 1;
  pointer-events: none;
  z-index: 1;
}

$titleSubtitle''';
}

/// Een letterfamilienaam in een stylesheet. Alleen het tekenarsenaal dat de
/// profielkiezer ook toelaat, zodat een naam de CSS niet kan sluiten.
String _cssFontFamily(String family) {
  final cleaned = family.replaceAll(RegExp(r'[^A-Za-z0-9 .,_-]'), '').trim();
  final name = cleaned.isEmpty ? 'Arial' : cleaned;
  return '"$name", sans-serif';
}

/// Tabelstijl van het profiel in de Marp-CSS. De standaard (omrand, geen
/// zebra, geen kopaccent) blijft een volle tabel; een randloze of
/// zebragestreepte keuze moet hier zichtbaar zijn, niet alleen in de app.
String _marpTableCss(ThemeProfile profile) {
  final border = switch (profile.tableBorderStyle) {
    TableBorderStyle.boxed => 'border: 1px solid ${profile.tableBorderColor};',
    TableBorderStyle.lined =>
      'border: none; border-bottom: 1px solid ${profile.tableBorderColor};',
    TableBorderStyle.none => 'border: none;',
  };
  final padding = profile.tableCellPaddingPx.toStringAsFixed(0);
  final zebra = profile.tableZebraStriped
      ? '''
tbody tr:nth-child(even) td {
  background: ${profile.tableZebraColor};
}
'''
      : '';
  final accent = profile.tableAccentHeaderBorder
      ? '''
thead th, tr:first-child th {
  border-bottom: 2px solid ${profile.accentColor};
}
'''
      : '';
  return '''
table {
  border-collapse: collapse;
  width: 100%;
  font-size: 0.72em;
}

th, td {
  $border
  padding: ${padding}px;
  text-align: left;
  color: ${profile.tableTextColor};
}

thead th, tr:first-child th {
  background: ${profile.tableHeaderBackgroundColor};
  color: ${profile.tableHeaderTextColor};
}
$zebra$accent''';
}

extension _FileServiceProject on FileService {
  Future<({Deck deck, List<String> chartWarnings})> _writeProject(
    Deck deck,
    String filePath,
  ) async {
    final dir = p.dirname(filePath);

    await createContainedProjectDirectory(dir, 'images');
    await createContainedProjectDirectory(dir, 'logos');
    final themesDir = await createContainedProjectDirectory(dir, 'themes');
    await createContainedProjectDirectory(dir, chartDataDirName);

    final imageSlides = await _img.copyImagesToProject(
      deck.slides,
      dir,
      sourceProjectPath: deck.projectPath,
    );
    final mediaSlides = await _img.copyMediaToProject(
      imageSlides,
      dir,
      sourceProjectPath: deck.projectPath,
    );
    var updatedDeck = deck.copyWith(slides: mediaSlides, projectPath: dir);
    final styled = await materializeProjectStyleImages(
      updatedDeck.themeProfile,
      dir,
      sourceProjectPath: deck.projectPath == dir ? null : deck.projectPath,
    );
    updatedDeck = updatedDeck.copyWith(themeProfile: styled.profile);
    await refreshCarriedProjectStyle(dir, updatedDeck.themeProfile);
    await _writeImageCaptions(updatedDeck);

    final writtenTheme = await _writeTheme(
      themesDir.path,
      updatedDeck.theme,
      updatedDeck.themeProfile,
      updatedDeck.marpStyle.footer,
      styled.logoCssUrl,
      styled.brandCssUrl,
      updatedDeck.slideSize,
    );
    // Marp CLI laadt een stylesheet naast de deck niet uit zichzelf; de
    // standaardroute is een Marp-configuratiebestand dat de CSS via `themeSet`
    // registreert. Zonder dit valt `marp deck.md` terug op het standaardthema
    // en gaat de `section.split`-lay-out verloren (#1804). Alleen schrijven
    // als de thema-CSS er echt staat.
    if (writtenTheme != null) {
      await _writeMarpConfig(dir, writtenTheme);
    }

    // Bring linked chart data files along when saving to a new location, then
    // write back what the user changed in the grid. Order matters: the copy
    // seeds a fresh location, the write updates it.
    await _copyChartData(deck, dir);
    // Charts that still carry their numbers inline move to a data file here,
    // before the markdown is generated — so the .md that follows keeps only
    // the reference. This is what makes the conversion invisible.
    updatedDeck = await _externalizeCharts(updatedDeck, dir);
    final chartWarnings = await _writeChartData(
      updatedDeck,
      dir,
      deckPath: filePath,
    );
    await _pruneChartData(updatedDeck, dir, deckPath: filePath);
    // Een grafiek waarvan het databestand niet geschreven kon worden, staat
    // hierna nergens meer: [_externalizeCharts] heeft de cijfers zojuist uit de
    // markdown gehaald. Loggen alleen was daarom te weinig — de aanroeper krijgt
    // ze terug en zet er [chartDataWarningProvider] mee, zodat de gebruiker het
    // ziet in plaats van een geslaagde opslag te lezen.
    if (chartWarnings.isNotEmpty) {
      logWarning(
        'FileService._writeProject: chart data files not cleanly written',
        chartWarnings.join(', '),
      );
    }

    // De markdown wordt hier gegenereerd (en de zegelhash vastgelegd) vóór de
    // sidecars worden geschreven: het zegel heeft de hash van de nieuwe `.md`
    // nodig. De `.md` zelf wordt pas als laatste atomair weggeschreven — dat
    // is het commit-punt. Faalt een sidecar, dan staat de oude `.md` nog op
    // schijf met de oude sidecars — consistent (#1949).
    final markdown = _md.generateDeck(
      updatedDeck,
      // #1950: kon een databestand niet geschreven worden, dan houdt de
      // `.md` de cijfers inline — een `source:`-verwijzing naar een
      // ontbrekend bestand is gegevensverlies.
      inlineChartData: chartWarnings.isNotEmpty,
    );
    updatedDeck = DocumentIntegrity.recordWrittenBytes(updatedDeck, markdown);
    // Annotaties, notities, de MIAUW-dispositie en het zegel leven in eigen
    // sidecars, zodat de `.md` pure, leesbare Marp blijft.
    await _writeSidecar(updatedDeck, filePath);
    await _writeUserNotesSidecar(updatedDeck, filePath);
    await _writeMiauwSidecar(updatedDeck, filePath);
    await _writeSealSidecar(updatedDeck, filePath);
    await _writeDismissalsSidecar(updatedDeck, filePath);
    await writeStringAtomic(File(filePath), markdown);
    return (deck: updatedDeck, chartWarnings: chartWarnings);
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
    final captions = <String, String>{};
    for (final slide in deck.slides) {
      if (slide.imagePath.isNotEmpty && slide.imageCaption.trim().isNotEmpty) {
        captions[slide.imagePath] = slide.imageCaption;
      }
      if (slide.imagePath2.isNotEmpty &&
          slide.imageCaption2.trim().isNotEmpty) {
        captions[slide.imagePath2] = slide.imageCaption2;
      }
    }
    await _captions.saveCaptions(captions, basePath: deck.projectPath);
  }

  /// Schrijft de gegenereerde thema-CSS en geeft de veilige themanaam terug
  /// (of `null` als de thema-asset niet gebundeld is in deze build-context —
  /// dan is er geen CSS om te registreren).
  Future<String?> _writeTheme(
    String themesPath,
    String themeName,
    ThemeProfile profile,
    String footerText,
    String? logoUrl,
    String? brandStripUrl,
    PageSizeSpec? slideSize,
  ) async {
    final safeThemeName = _safeThemeName(themeName);
    final dest = File(p.join(themesPath, '$safeThemeName.css'));
    try {
      final base = (await rootBundle.loadString(
        'assets/themes/ocideck.css',
      )).replaceFirst('@theme ocideck', '@theme $safeThemeName');
      await writeStringAtomicIfChanged(
        dest,
        _buildThemeCss(
          base,
          themeWithFooterSafeLogo(profile, footerText),
          logoUrl,
          brandStripUrl,
          slideSize,
        ),
      );
      return safeThemeName;
    } catch (e) {
      // Asset not bundled in this build context; skip
      logWarning('FileService._writeTheme: theme asset not bundled', e);
      return null;
    }
  }

  /// Schrijft `.marprc.yml` naast de `.md` zodat een gewone
  /// `marp deck.md -o out.html` (gedraaid vanuit deze map) de gegenereerde
  /// thema-CSS laadt. Het pad is relatief, dus verhuizen van de projectmap
  /// blijft werken. Zie #1804.
  Future<void> _writeMarpConfig(String projectDir, String themeName) async {
    await writeStringAtomicIfChanged(
      File(p.join(projectDir, '.marprc.yml')),
      '# OciDeck Marp CLI configuration.\n'
      '# Registers the generated theme so a plain `marp deck.md -o out.html`\n'
      '# (run from this folder) loads it. Marp does not auto-discover a\n'
      '# stylesheet placed beside the deck; this config is the standard route.\n'
      'themeSet:\n'
      '  - themes/$themeName.css\n',
    );
  }

  String _buildThemeCss(
    String base,
    ThemeProfile profile,
    String? logoUrl,
    String? brandStripUrl,
    PageSizeSpec? slideSize,
  ) {
    // De strookhoogte is een fractie van de diahoogte, niet van 720px.
    final slideHeightPx = slideDesignHeight(slideSize);
    final logoCss = logoUrl == null
        ? ''
        : brandStripUrl != null && profile.brandStripHeight > 0
        ? _brandStripCss(profile, brandStripUrl, slideHeightPx)
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
${marpSizeDirective(slideSize)}
/* OciDeck style profile */
section {
  background: ${profile.slideBackgroundColor};
  color: ${profile.textColor};
  font-family: ${_cssFontFamily(profile.fontFamily)};
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

${_marpTableCss(profile)}
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
