// Part of the file_service library — see ../file_service.dart.
// De stijlsidecar van een .ocideck-pakket: meereizen zonder het
// globale profiel te overschrijven, en zonder lokale paden te vertrouwen.
part of '../file_service.dart';

void _addCarriedStyleMember(Archive archive, ThemeProfile profile) {
  final bytes = utf8.encode(jsonEncode(portableCarriedStyle(profile).toJson()));
  archive.add(ArchiveFile(carriedStyleFileName, bytes.length, bytes));
}

/// De meegedragen dia-stijlen (#2996): één record per gebruikte profielnaam.
/// Alleen schrijven als er namen zijn — een pakket zonder wissels draagt geen
/// leeg stijlregime.
void _addCarriedStylesMember(
  Archive archive,
  Map<String, ThemeProfile> styles,
) {
  if (styles.isEmpty) return;
  final bytes = utf8.encode(
    jsonEncode({
      for (final e in styles.entries)
        e.key: portableCarriedStyle(e.value).toJson(),
    }),
  );
  archive.add(ArchiveFile(carriedStylesFileName, bytes.length, bytes));
}

ThemeProfile portableCarriedStyle(ThemeProfile profile) {
  String? image(String? path, {required bool emptyWhenUnsafe}) {
    final trimmed = path?.trim();
    if (trimmed == null) return null;
    if (trimmed.isEmpty) return '';
    if (isBundledAssetPath(trimmed)) return trimmed;
    final normalized = p.posix.normalize(trimmed.replaceAll('\\', '/'));
    // De traversal-disjunct is verdwenen: na normalize begint een pad dat
    // met '../' opent per definitie niet met 'logos/' — de eerste helft
    // dekt hem al (de mutatiesweep wees dit als dood aan).
    if (!normalized.startsWith('logos/')) {
      return emptyWhenUnsafe ? '' : null;
    }
    return normalized;
  }

  final logo = image(profile.logoPath, emptyWhenUnsafe: false);
  final dark = image(profile.logoDarkPath, emptyWhenUnsafe: false);
  final strip = image(profile.brandStripPath, emptyWhenUnsafe: false);
  final document = image(profile.documentLogoPath, emptyWhenUnsafe: true);
  return profile.copyWith(
    clearLogo: logo == null,
    logoPath: logo,
    clearLogoDark: dark == null,
    logoDarkPath: dark,
    clearBrandStrip: strip == null,
    brandStripPath: strip,
    slideBackgroundImages: profile.mapSlideBackgroundImages(
      (path) => image(path, emptyWhenUnsafe: false),
    ),
    clearDocumentLogoOverride: document == null,
    documentLogoPath: document,
  );
}

/// Leest de stijlsidecar naast een uitgepakt project. Ontbreekt hij, of is
/// hij niet te vertrouwen, dan blijft [fallback] — het lokale profiel.
Future<ThemeProfile> carriedProjectStyle(
  String? projectPath,
  ThemeProfile fallback,
) async {
  if (kIsWeb || projectPath == null) return fallback;
  final file = File(p.join(projectPath, carriedStyleFileName));
  try {
    // exists() ín de vangst: ook hij gooit bij een I/O-fout, en een
    // sidecar-fout mag nooit het openen van het deck meenemen.
    if (!await file.exists()) return fallback;
    final length = await file.length();
    if (length <= 0 || length > _carriedStyleMaxBytes) return fallback;
    final decoded = jsonDecodeGuarded(await file.readAsString());
    if (decoded is! Map) return fallback;
    final profile = ThemeProfile.fromJson(Map<String, Object?>.from(decoded));
    return _styleInsideProject(portableCarriedStyle(profile), projectPath);
  } on FormatException {
    return fallback;
  } on FileSystemException {
    return fallback;
  }
}

/// Leest de meegedragen dia-stijlen naast een uitgepakt project — de
/// meervoudige tegenhanger van [carriedProjectStyle]. Ontbreekt of mislukt het
/// bestand, dan is de map leeg; onleesbare leden vallen weg terwijl de rest
/// blijft, dezelfde degradatie als elders.
Future<Map<String, ThemeProfile>> carriedProjectStyles(
  String? projectPath,
) async {
  if (kIsWeb || projectPath == null) return const {};
  final file = File(p.join(projectPath, carriedStylesFileName));
  try {
    if (!await file.exists()) return const {};
    final length = await file.length();
    if (length <= 0 || length > _carriedStyleMaxBytes) return const {};
    final decoded = jsonDecodeGuarded(await file.readAsString());
    if (decoded is! Map) return const {};
    final styles = <String, ThemeProfile>{};
    for (final entry in Map<String, Object?>.from(decoded).entries) {
      final member = entry.value;
      if (member is! Map) continue;
      styles[entry.key] = _styleInsideProject(
        portableCarriedStyle(
          ThemeProfile.fromJson(Map<String, Object?>.from(member)),
        ),
        projectPath,
      );
    }
    return styles;
  } on FormatException {
    return const {};
  } on FileSystemException {
    return const {};
  }
}

/// Bewaart de meegedragen stijl en bindt stijlen met achtergrondafbeeldingen
/// aan hun project, zodat de lokale profielkeuze ze bij heropenen niet wijzigt.
Future<void> refreshCarriedProjectStyle(
  String projectPath,
  ThemeProfile profile,
) async {
  if (kIsWeb) return;
  final file = File(p.join(projectPath, carriedStyleFileName));
  try {
    if (profile.slideBackgroundImages.isEmpty && !await file.exists()) return;
    await writeStringAtomic(
      file,
      jsonEncode(portableCarriedStyle(profile).toJson()),
    );
  } on FileSystemException catch (e) {
    // Een sidecar-verversing die faalt mag een verder geslaagde opslag niet
    // meenemen — de volgende open valt anders terug op de oude sidecar, nooit
    // op niets.
    logWarning('FileService.refreshCarriedProjectStyle', e);
  }
}

/// De meervoudige variant van [refreshCarriedProjectStyle], voor de dia-
/// stijlen. Zelfde grens: zonder bestaand bestand schrijft hij niets — een
/// gewoon project lost zijn wisselnamen op in de eigen instellingen.
Future<void> refreshCarriedProjectStyles(
  String projectPath,
  Map<String, ThemeProfile> styles,
) async {
  if (kIsWeb) return;
  final file = File(p.join(projectPath, carriedStylesFileName));
  try {
    if (!await file.exists()) return;
    await writeStringAtomic(
      file,
      jsonEncode({
        for (final e in styles.entries)
          e.key: portableCarriedStyle(e.value).toJson(),
      }),
    );
  } on FileSystemException catch (e) {
    logWarning('FileService.refreshCarriedProjectStyles', e);
  }
}

ThemeProfile _styleInsideProject(ThemeProfile profile, String projectPath) {
  String? existing(String? path, {required bool emptyWhenMissing}) {
    if (path == null) return null;
    if (path.isEmpty) return '';
    if (isBundledAssetPath(path)) return path;
    final normalized = p.posix.normalize(path.replaceAll('\\', '/'));
    if (!normalized.startsWith('logos/') || normalized.contains('..')) {
      return emptyWhenMissing ? '' : null;
    }
    final abs = p.normalize(p.join(projectPath, normalized));
    if (!p.isWithin(p.normalize(projectPath), abs)) {
      return emptyWhenMissing ? '' : null;
    }
    bool present;
    try {
      present = File(abs).existsSync();
    } on FileSystemException {
      present = false;
    }
    if (!present) return emptyWhenMissing ? '' : null;
    return normalized;
  }

  final logo = existing(profile.logoPath, emptyWhenMissing: false);
  final dark = existing(profile.logoDarkPath, emptyWhenMissing: false);
  final strip = existing(profile.brandStripPath, emptyWhenMissing: false);
  final document = existing(profile.documentLogoPath, emptyWhenMissing: true);
  return profile.copyWith(
    clearLogo: logo == null,
    logoPath: logo,
    clearLogoDark: dark == null,
    logoDarkPath: dark,
    clearBrandStrip: strip == null,
    brandStripPath: strip,
    slideBackgroundImages: profile.mapSlideBackgroundImages(
      (path) => existing(path, emptyWhenMissing: false),
    ),
    clearDocumentLogoOverride: document == null,
    documentLogoPath: document,
  );
}

/// Web: de sidecar uit de pakketleden, met logobytes als `mem:`-pad.
/// Zonder sidecar blijft het deck zoals het binnenkwam.
Deck applyCarriedStyleMembers(Deck deck, List<PackageEntry> entries) {
  PackageEntry? style;
  PackageEntry? styles;
  for (final entry in entries) {
    final name = p.posix.normalize(entry.name);
    if (name == carriedStyleFileName) style = entry;
    if (name == carriedStylesFileName) styles = entry;
  }
  var styled = deck;
  if (style != null && style.bytes.length <= _carriedStyleMaxBytes) {
    try {
      final decoded = jsonDecodeGuarded(utf8.decode(style.bytes));
      if (decoded is Map) {
        final profile = portableCarriedStyle(
          ThemeProfile.fromJson(Map<String, Object?>.from(decoded)),
        );
        styled = styled.copyWith(
          themeProfile: _styleMembersToMemory(profile, entries),
        );
      }
    } on FormatException {
      // De sidecar mag het openen niet meenemen; de deckstijl blijft staan.
    }
  }
  // De dia-stijlen (#2996): elk profiel uit `ocideck-styles.json` krijgt zijn
  // logo's als `mem:`-pad, net als het basisprofiel.
  if (styles != null && styles.bytes.length <= _carriedStyleMaxBytes) {
    try {
      final decoded = jsonDecodeGuarded(utf8.decode(styles.bytes));
      if (decoded is Map) {
        final carried = <String, ThemeProfile>{};
        for (final e in Map<String, Object?>.from(decoded).entries) {
          final member = e.value;
          if (member is! Map) continue;
          carried[e.key] = _styleMembersToMemory(
            portableCarriedStyle(
              ThemeProfile.fromJson(Map<String, Object?>.from(member)),
            ),
            entries,
          );
        }
        if (carried.isNotEmpty) {
          styled = styled.copyWith(slideStyles: carried);
        }
      }
    } on FormatException {
      // Zelfde grens: een corrupt lid degradeert naar de deckstijl.
    }
  }
  return styled;
}

ThemeProfile _styleMembersToMemory(
  ThemeProfile profile,
  List<PackageEntry> entries,
) {
  final byName = {for (final e in entries) p.posix.normalize(e.name): e.bytes};
  String? mem(String? path, {required bool emptyWhenMissing}) {
    if (path == null) return null;
    if (path.isEmpty) return '';
    if (isBundledAssetPath(path) || WebAssetStore.isMemPath(path)) return path;
    final normalized = p.posix.normalize(path.replaceAll('\\', '/'));
    // 'logos/'-containment leeft in portableCarriedStyle, die hier altijd
    // aan voorafgaat — de prefixcheck was daardoor onbereikbaar (dood,
    // wees de mutatiesweep aan). '..' kan een pakket-entry wél letterlijk
    // als sleutel hebben, dus die check blijft lokaal dragen.
    if (normalized.contains('..')) {
      return emptyWhenMissing ? '' : null;
    }
    final bytes = byName[normalized];
    if (bytes == null ||
        bytes.length > FileService.maxStyleProfileLogoBytes ||
        ImageService.imageMimeFromBytes(bytes) == null) {
      return emptyWhenMissing ? '' : null;
    }
    return WebAssetStore.put(bytes, name: p.posix.basename(normalized));
  }

  final logo = mem(profile.logoPath, emptyWhenMissing: false);
  final dark = mem(profile.logoDarkPath, emptyWhenMissing: false);
  final strip = mem(profile.brandStripPath, emptyWhenMissing: false);
  final document = mem(profile.documentLogoPath, emptyWhenMissing: true);
  return profile.copyWith(
    clearLogo: logo == null,
    logoPath: logo,
    clearLogoDark: dark == null,
    logoDarkPath: dark,
    clearBrandStrip: strip == null,
    brandStripPath: strip,
    slideBackgroundImages: profile.mapSlideBackgroundImages(
      (path) => mem(path, emptyWhenMissing: false),
    ),
    clearDocumentLogoOverride: document == null,
    documentLogoPath: document,
  );
}
