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

extension _FileServiceProject on FileService {
  Future<({Deck deck, List<String> chartWarnings})> _writeProject(
    Deck deck,
    String filePath,
  ) async {
    final dir = p.dirname(filePath);

    final imagesDir = Directory(p.join(dir, 'images'));
    final logosDir = Directory(p.join(dir, 'logos'));
    final themesDir = Directory(p.join(dir, 'themes'));
    await imagesDir.create(recursive: true);
    await logosDir.create(recursive: true);
    await themesDir.create(recursive: true);
    // data/ hoort bij de vaste mapindeling; hij werd tot nu toe alleen
    // toevallig aangemaakt door wie een CSV koppelde.
    await Directory(p.join(dir, chartDataDirName)).create(recursive: true);

    final imageSlides = await _img.copyImagesToProject(deck.slides, dir);
    final mediaSlides = await _img.copyMediaToProject(imageSlides, dir);
    var updatedDeck = deck.copyWith(slides: mediaSlides, projectPath: dir);
    final logoAsset = await _copyLogoToProject(updatedDeck.themeProfile, dir);
    updatedDeck = updatedDeck.copyWith(themeProfile: logoAsset.profile);
    await _writeImageCaptions(updatedDeck);

    final writtenTheme = await _writeTheme(
      themesDir.path,
      updatedDeck.theme,
      updatedDeck.themeProfile,
      logoAsset.cssUrl,
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

  /// Schrijft de gegenereerde thema-CSS en geeft de veilige themanaam terug
  /// (of `null` als de thema-asset niet gebundeld is in deze build-context —
  /// dan is er geen CSS om te registreren).
  Future<String?> _writeTheme(
    String themesPath,
    String themeName,
    ThemeProfile profile,
    String? logoUrl,
  ) async {
    final safeThemeName = _safeThemeName(themeName);
    final dest = File(p.join(themesPath, '$safeThemeName.css'));
    try {
      final base = (await rootBundle.loadString(
        'assets/themes/ocideck.css',
      )).replaceFirst('@theme ocideck', '@theme $safeThemeName');
      await writeStringAtomic(dest, _buildThemeCss(base, profile, logoUrl));
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
    await writeStringAtomic(
      File(p.join(projectDir, '.marprc.yml')),
      '# OciDeck Marp CLI configuration.\n'
      '# Registers the generated theme so a plain `marp deck.md -o out.html`\n'
      '# (run from this folder) loads it. Marp does not auto-discover a\n'
      '# stylesheet placed beside the deck; this config is the standard route.\n'
      'themeSet:\n'
      '  - themes/$themeName.css\n',
    );
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
  background: ${profile.tableHeaderBackgroundColor};
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
