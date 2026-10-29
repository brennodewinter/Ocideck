import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../services/asset_staging.dart';

/// [resolveSlideAssetPath] plus a symlink check: resolves the real (symlink-
/// followed) path and returns null if it escapes the project. This catches a
/// symlink *inside* the project that points outside it — which the lexical
/// `isWithin` guards cannot see.
///
/// It does filesystem stats (`resolveSymbolicLinksSync`), so it is meant for
/// non-hot read sinks that move file *bytes* out of the app (e.g. copy-to-
/// clipboard), NOT the per-frame render path (a stat per image per frame would
/// jank on network-mounted projects). A missing file is allowed when its
/// existing ancestors remain inside the project, so retrying image loads can
/// observe a file that arrives later.
String? resolveContainedRealPath(String path, String? projectPath) {
  final resolved = resolveSlideAssetPath(path, projectPath);
  if (resolved == null || projectPath == null) return resolved;
  try {
    return _isInsideRealBase(resolved, projectPath)
        ? File(resolved).resolveSymbolicLinksSync()
        : null;
  } on FileSystemException {
    try {
      final realBase = Directory(projectPath).resolveSymbolicLinksSync();
      var ancestor = resolved;
      while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
          FileSystemEntityType.notFound) {
        final parent = p.dirname(ancestor);
        if (parent == ancestor) return null;
        ancestor = parent;
      }
      final realAncestor = File(ancestor).resolveSymbolicLinksSync();
      return realAncestor == realBase || p.isWithin(realBase, realAncestor)
          ? resolved
          : null;
    } on FileSystemException {
      return null;
    }
  }
}

/// True when [resolved]'s real (symlink-followed) path is inside [projectPath].
/// Throws [FileSystemException] when the path is missing/unresolvable.
bool _isInsideRealBase(String resolved, String projectPath) {
  final realBase = Directory(projectPath).resolveSymbolicLinksSync();
  final real = File(resolved).resolveSymbolicLinksSync();
  return real == realBase || p.isWithin(realBase, real);
}

/// Een afbeeldingspad dat de projectgrens ontsnapt — door de beeld- en
/// medialader gegooid zodat de renderlaag de `outsideDeck`-placeholder kan
/// kiezen zonder zelf bestandssysteem-statistieken te hoeven doen.
class ProjectEscapeException implements Exception {
  const ProjectEscapeException(this.path);

  final String path;

  @override
  String toString() => 'ProjectEscapeException: $path';
}

/// De async variant van de project-containment voor de *laadgrens* (#2624):
/// resolveert het echte, symlink-gevolgde pad en levert dát doelpad terug —
/// de aanroeper leest de gecontroleerde locatie in plaats van het lexicale
/// pad, wat de TOCTOU tussen controle en open dichtmaakt. `null` betekent:
/// ontsnapt het project (een symlink in het project die buiten wijst, of een
/// pad wiens bestaande voorouder al buiten ligt).
///
/// Een ontbrekend bestand mag door wanneer zijn bestaande voorouder binnen
/// het project ligt: de `readAsBytes` daarna faalt dan als gewone
/// missend-bestand-fout en de aanroeper tekent de placeholder.
///
/// Doet `resolveSymbolicLinks` *async* — bedoeld voor de één-keer-per-decode
/// laadgrens, zodat de build zelf geen synchrone realpath meer doet (zwaar
/// op Windows: Defender, OneDrive en netwerk-mappen maken elke stat duur).
Future<String?> containedRealPathOrNull(
  String resolved,
  String projectPath,
) async {
  try {
    if (!await Directory(projectPath).exists()) {
      return p.isWithin(p.normalize(projectPath), p.normalize(resolved))
          ? resolved
          : null;
    }
    final realBase = await Directory(projectPath).resolveSymbolicLinks();
    try {
      final real = await File(resolved).resolveSymbolicLinks();
      return real == realBase || p.isWithin(realBase, real) ? real : null;
    } on FileSystemException {
      // Ontbrekend bestand: alleen doorlaten als de bestaande voorouder
      // binnen de echte projectroot ligt.
      return _existingAncestorInside(resolved, realBase) ? resolved : null;
    }
  } on FileSystemException {
    return null;
  }
}

bool _existingAncestorInside(String resolved, String realBase) {
  var ancestor = resolved;
  while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(ancestor);
    if (parent == ancestor) return false;
    ancestor = parent;
  }
  try {
    final realAncestor = File(ancestor).resolveSymbolicLinksSync();
    return realAncestor == realBase || p.isWithin(realBase, realAncestor);
  } on FileSystemException {
    return false;
  }
}

/// Resolve a project-relative [path] to an absolute path strictly inside
/// [basePath], or null for absolute paths, empty paths, or `../` escapes.
String? resolveProjectRelative(String? basePath, String path) {
  if (basePath == null || path.trim().isEmpty || p.isAbsolute(path)) {
    return null;
  }
  final abs = p.normalize(p.join(basePath, path));
  if (abs != basePath && !p.isWithin(basePath, abs)) return null;
  return abs;
}

/// Resolve an absolute path only when it lies inside [basePath].
String? resolveProjectAbsolute(String? basePath, String path) {
  if (basePath == null || path.trim().isEmpty || !p.isAbsolute(path)) {
    return null;
  }
  final abs = p.normalize(path);
  if (abs != basePath && !p.isWithin(basePath, abs)) return null;
  return abs;
}

/// Resolves a slide asset path for display/playback.
///
/// When [projectPath] is set (deck opened from disk), only project-contained
/// paths are allowed — untrusted decks cannot read arbitrary files.
/// When [projectPath] is null (unsaved tab), absolute paths from the current
/// editing session are allowed.
String? resolveSlideAssetPath(String path, String? projectPath) {
  // Op web bestaat er geen lokaal bestandssysteem: elk lokaal pad is per
  // definitie onvindbaar. Null → de callers tonen hun normale placeholder,
  // in plaats van dat een dart:io-stub dieper in de keten gooit.
  if (kIsWeb) return null;
  if (path.trim().isEmpty) return null;

  if (projectPath == null || projectPath.isEmpty) {
    // An unsaved deck may render only assets that OciDeck itself copied into
    // its private staging root. Arbitrary absolute paths remain blocked: a
    // recovered/untrusted deck must not turn the preview into a file reader.
    // The staging path is replaced by a project-relative path on first save.
    return AssetStaging.isStagedPath(path) ? p.normalize(path) : null;
  }

  if (p.isAbsolute(path)) {
    return resolveProjectAbsolute(projectPath, path);
  }

  return resolveProjectRelative(projectPath, path);
}

/// Geeft [deckUrl] terug als het een absolute http(s)-URL is waar relatieve
/// paden tegen opgelost kunnen worden — zoals een `?deck=`/URL-import. Alles
/// anders (een git-label, een bestandspad, `null`) levert `null`, zodat
/// aanroepers nooit een niet-URL als resolutiebasis opslaan.
String? remoteDeckUrlOrNull(String? deckUrl) {
  final uri = deckUrl == null ? null : Uri.tryParse(deckUrl.trim());
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.toString();
}

/// Lost een deck-relatieve assetverwijzing (`images/foto.png`) op tegen de URL
/// waar het deck zélf vandaan kwam — bijvoorbeeld een plat Markdown-deck dat op
/// web via `?deck=` of URL-import is geopend (#2282). Dat is de web-tegenhanger
/// van [resolveProjectRelative]: een bestand naast het deck op de server is de
/// dezelfde verwijzing als een bestand naast het deck op schijf.
///
/// De uitkomst blijft same-origin én binnen de map van het deck — dezelfde
/// project-containment die desktop afdwingt, zodat deck-inhoud geen
/// willekeurige URL's kan laten ophalen. Fail-closed `null` voor een
/// verwijzing met eigen scheme/authority (`https://…`, `//host/…`, `mem:`,
/// `data:` — die takken lopen eerder) en voor een [deckUrl] die geen absolute
/// http(s)-URL is.
String? resolveDeckAssetUrl(String? path, String? deckUrl) {
  if (remoteDeckUrlOrNull(deckUrl) == null) return null;
  final base = Uri.parse(deckUrl!.trim());
  final ref = path?.trim();
  if (ref == null || ref.isEmpty) return null;
  // Een verwijzing mét eigen scheme hoort bij een eerder tak (URL, mem:,
  // asset:, data:). Toestaan zou deck-inhoud elke gewenste URL laten ophalen.
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(ref)) return null;
  final dir = base.resolve('./');
  final resolved = base.resolve(ref);
  // `//host/…` wisselt van autoriteit; alles anders erft scheme+host+port.
  if (resolved.scheme != dir.scheme || resolved.authority != dir.authority) {
    return null;
  }
  // Dot-segmenten zijn door resolve al weggenormaliseerd, maar `Uri.path`
  // laat `%2F` gecodeerd terwijl de server hem als `/` leest — daarom draait
  // de map-containment op het gedecodeerde, genormaliseerde pad.
  final dirPath = p.posix.normalize(Uri.decodeComponent(dir.path));
  final resolvedPath = p.posix.normalize(Uri.decodeComponent(resolved.path));
  final prefix = dirPath.endsWith('/') ? dirPath : '$dirPath/';
  if (!resolvedPath.startsWith(prefix)) return null;
  return resolved.toString();
}

/// Resolve a TRUSTED asset path (the active style-profile logo) for display.
///
/// Unlike [resolveSlideAssetPath], an absolute path is allowed even when it
/// lies outside [projectPath]. The logo comes from the user's style profile
/// (app configuration the app forces onto every opened deck), not from the
/// deck markdown, so the project-containment guard — which exists to stop an
/// untrusted deck from reading arbitrary files — must not apply to it. A
/// relative path still resolves inside the project (the profile loader has
/// already made a found relative logo absolute via the home fallback).
String? resolveTrustedAssetPath(String path, String? projectPath) {
  if (kIsWeb) return null;
  if (path.trim().isEmpty) return null;
  if (p.isAbsolute(path)) return p.normalize(path);
  return resolveProjectRelative(projectPath, path);
}

/// Resolve an image path for editor/carousel use (may join relative paths).
String? resolveEditorAssetPath(String path, String? basePath) {
  if (kIsWeb) return null;
  if (path.trim().isEmpty) return null;
  if (basePath == null || basePath.isEmpty) {
    return p.isAbsolute(path) ? p.normalize(path) : path;
  }
  // Intentionally permissive for the EDITOR: a user can pick an image from
  // anywhere on disk and the editor must display it before it is copied into
  // the project. Security-sensitive sinks (e.g. copy-to-clipboard) must NOT use
  // this resolver for a deck-opened-from-disk; use resolveSlideAssetPath, which
  // enforces project containment.
  if (p.isAbsolute(path)) {
    return resolveProjectAbsolute(basePath, path) ?? p.normalize(path);
  }
  return resolveProjectRelative(basePath, path);
}

/// Resolve a generated project path before creating files or directories.
/// Existing symlinks, including dangling ones, must resolve inside the project.
String? resolveContainedWritePath(String path, String projectPath) {
  final resolved = p.isAbsolute(path)
      ? resolveProjectAbsolute(projectPath, path)
      : resolveProjectRelative(projectPath, path);
  if (resolved == null) return null;
  try {
    final realBase = Directory(projectPath).resolveSymbolicLinksSync();
    var ancestor = resolved;
    while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(ancestor);
      if (parent == ancestor) return null;
      ancestor = parent;
    }
    final real = File(ancestor).resolveSymbolicLinksSync();
    if (real != realBase && !p.isWithin(realBase, real)) return null;
    return resolved;
  } on FileSystemException {
    return null;
  }
}

/// Create a generated asset directory only within the real project root.
Future<Directory> createContainedProjectDirectory(
  String projectPath,
  String relativePath,
) async {
  final target = resolveContainedWritePath(relativePath, projectPath);
  if (target == null) {
    throw const FileSystemException('Asset directory escapes project');
  }
  final directory = await Directory(target).create(recursive: true);
  if (resolveContainedWritePath(directory.path, projectPath) == null) {
    throw const FileSystemException('Asset directory escapes project');
  }
  return directory;
}
