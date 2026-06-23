import 'dart:io';

import 'package:path/path.dart' as p;

/// [resolveSlideAssetPath] plus a symlink check: resolves the real (symlink-
/// followed) path and returns null if it escapes the project. This catches a
/// symlink *inside* the project that points outside it — which the lexical
/// `isWithin` guards cannot see.
///
/// It does filesystem stats (`resolveSymbolicLinksSync`), so it is meant for
/// non-hot read sinks that move file *bytes* out of the app (e.g. copy-to-
/// clipboard), NOT the per-frame render path (a stat per image per frame would
/// jank on network-mounted projects). Returns null when the file is missing or
/// the realpath can't be taken.
String? resolveContainedRealPath(String path, String? projectPath) {
  final resolved = resolveSlideAssetPath(path, projectPath);
  if (resolved == null || projectPath == null) return resolved;
  try {
    final realBase = Directory(projectPath).resolveSymbolicLinksSync();
    final real = File(resolved).resolveSymbolicLinksSync();
    if (real == realBase || p.isWithin(realBase, real)) return resolved;
    return null;
  } on FileSystemException {
    return null;
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
  if (path.trim().isEmpty) return null;

  if (projectPath == null) {
    return p.isAbsolute(path) ? p.normalize(path) : null;
  }

  if (p.isAbsolute(path)) {
    return resolveProjectAbsolute(projectPath, path);
  }

  return resolveProjectRelative(projectPath, path);
}

/// Resolve an image path for editor/carousel use (may join relative paths).
String? resolveEditorAssetPath(String path, String? basePath) {
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
