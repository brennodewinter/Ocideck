import 'dart:io';

import 'package:flutter/foundation.dart';
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
    return _isInsideRealBase(resolved, projectPath) ? resolved : null;
  } on FileSystemException {
    return null; // missing/unresolvable → refuse (can't copy anyway)
  }
}

/// True when [resolved]'s real (symlink-followed) path is inside [projectPath].
/// Throws [FileSystemException] when the path is missing/unresolvable.
bool _isInsideRealBase(String resolved, String projectPath) {
  final realBase = Directory(projectPath).resolveSymbolicLinksSync();
  final real = File(resolved).resolveSymbolicLinksSync();
  return real == realBase || p.isWithin(realBase, real);
}

final Set<String> _renderBlockedPaths = {};

/// Symlink-containment check for the hot render path: blocks a project-internal
/// symlink that points outside the project.
///
/// Only blocked paths are cached. A positive result must be revalidated because
/// a regular/missing path can be replaced by an escaping symlink while the app
/// is running. A stale negative is deliberately fail-closed until the session
/// or project cache is reset. Missing paths return `true` but are never cached;
/// the normal load path renders their placeholder.
bool isRenderPathContained(String resolved, String projectPath) {
  final cacheKey = '$projectPath\u0000$resolved';
  if (_renderBlockedPaths.contains(cacheKey)) return false;
  bool ok;
  try {
    ok = _isInsideRealBase(resolved, projectPath);
  } on FileSystemException {
    return true;
  }
  if (!ok) {
    if (_renderBlockedPaths.length >= 1024) {
      _renderBlockedPaths.remove(_renderBlockedPaths.first);
    }
    _renderBlockedPaths.add(cacheKey);
  }
  return ok;
}

/// Clears the [isRenderPathContained] cache (tests).
void resetRenderContainedCache() => _renderBlockedPaths.clear();

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

  if (projectPath == null) {
    return p.isAbsolute(path) ? p.normalize(path) : null;
  }

  if (p.isAbsolute(path)) {
    return resolveProjectAbsolute(projectPath, path);
  }

  return resolveProjectRelative(projectPath, path);
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
