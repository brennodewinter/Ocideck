// Part of the file_service library — see ../file_service.dart.
// De stijlsidecar van een .ocideck-pakket: meereizen zonder het
// globale profiel te overschrijven, en zonder lokale paden te vertrouwen.
part of '../file_service.dart';

void _addCarriedStyleMember(Archive archive, ThemeProfile profile) {
  final bytes = utf8.encode(jsonEncode(portableCarriedStyle(profile).toJson()));
  archive.add(ArchiveFile(carriedStyleFileName, bytes.length, bytes));
}

ThemeProfile portableCarriedStyle(ThemeProfile profile) {
  String? image(String? path, {required bool emptyWhenUnsafe}) {
    final trimmed = path?.trim();
    if (trimmed == null) return null;
    if (trimmed.isEmpty) return '';
    if (isBundledAssetPath(trimmed)) return trimmed;
    final normalized = p.posix.normalize(trimmed.replaceAll('\\', '/'));
    if (!normalized.startsWith('logos/') || normalized.startsWith('../')) {
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
  if (!await file.exists()) return fallback;
  try {
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

/// Herschrijft een bestaande sidecar na opslaan, zodat een bewerking van de
/// meegekregen stijl het heropenen overleeft. Een gewoon project zonder
/// sidecar krijgt er geen: dat blijft het lokale profiel volgen.
Future<void> refreshCarriedProjectStyle(
  String projectPath,
  ThemeProfile profile,
) async {
  if (kIsWeb) return;
  final file = File(p.join(projectPath, carriedStyleFileName));
  if (!await file.exists()) return;
  await writeStringAtomic(
    file,
    jsonEncode(portableCarriedStyle(profile).toJson()),
  );
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
    if (!File(abs).existsSync()) return emptyWhenMissing ? '' : null;
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
    clearDocumentLogoOverride: document == null,
    documentLogoPath: document,
  );
}

/// Web: de sidecar uit de pakketleden, met logobytes als `mem:`-pad.
/// Zonder sidecar blijft het deck zoals het binnenkwam.
Deck applyCarriedStyleMembers(Deck deck, List<PackageEntry> entries) {
  PackageEntry? style;
  for (final entry in entries) {
    if (p.posix.normalize(entry.name) == carriedStyleFileName) style = entry;
  }
  if (style == null || style.bytes.length > _carriedStyleMaxBytes) return deck;
  try {
    final text = utf8.decode(style.bytes);
    final decoded = jsonDecodeGuarded(text);
    if (decoded is! Map) return deck;
    final profile = portableCarriedStyle(
      ThemeProfile.fromJson(Map<String, Object?>.from(decoded)),
    );
    return deck.copyWith(themeProfile: _styleMembersToMemory(profile, entries));
  } on FormatException {
    return deck;
  }
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
    if (!normalized.startsWith('logos/') || normalized.contains('..')) {
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
    clearDocumentLogoOverride: document == null,
    documentLogoPath: document,
  );
}
