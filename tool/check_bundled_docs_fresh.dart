// Release gate: verify the documentation *inside a freshly built artifact*
// matches the documentation on disk, byte for byte.
//
// Why this exists. The bundled docs are plain assets (docs/**.md, LICENSE.md,
// CONTRIBUTORS.md — whatever pubspec.yaml declares), so a *clean* build always
// carries the current text. But the project deliberately avoids `flutter clean`
// between builds (it throws away the platform build and forces a slow rebuild —
// see the Makefile), and the forge's macOS runner is persistent, so `build/`
// survives from one tag to the next. An incremental build that fails to re-copy
// a changed asset would then ship *stale* documentation while everything else is
// current — exactly the "the docs in the app are out of date" complaint.
//
// This gate closes that gap by construction: it reads the docs that actually
// landed in the built bundle and compares them to the source. A mismatch fails
// the release with the offending files named, so the fix (a clean rebuild) is
// forced rather than hoped for. It rewrites nothing — it only checks freshness.
//
// Usage: dart run tool/check_bundled_docs_fresh.dart <build-root>
//   <build-root> is a directory to search for the built Flutter assets, e.g.
//   build/web, build/macos, build/linux. The tool locates the assets directory
//   beneath it (web: assets/, desktop: .../flutter_assets/) by a sentinel doc,
//   so the caller need not know the platform-specific nesting.

import 'dart:io';

/// The outcome of comparing the declared bundled docs against the copies found
/// in a built artifact. Pure data, so the comparison is unit-testable without
/// touching the filesystem.
class DocFreshnessResult {
  DocFreshnessResult({
    required this.checked,
    required this.missing,
    required this.stale,
  });

  /// Number of declared docs that were compared.
  final int checked;

  /// Declared docs with no copy in the built bundle.
  final List<String> missing;

  /// Declared docs whose built copy differs from the on-disk source.
  final List<String> stale;

  bool get ok => missing.isEmpty && stale.isEmpty;
}

/// Compares each declared doc's [source] bytes against its [bundled] bytes
/// (`null` = not present in the build). Pure; the entry point does the IO.
DocFreshnessResult compareDocs({
  required Map<String, List<int>> source,
  required Map<String, List<int>?> bundled,
}) {
  final missing = <String>[];
  final stale = <String>[];
  for (final entry in source.entries) {
    final built = bundled[entry.key];
    if (built == null) {
      missing.add(entry.key);
    } else if (!_bytesEqual(entry.value, built)) {
      stale.add(entry.key);
    }
  }
  missing.sort();
  stale.sort();
  return DocFreshnessResult(
    checked: source.length,
    missing: missing,
    stale: stale,
  );
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Every Markdown asset declared under `flutter: assets:` in [pubspec], e.g.
/// `docs/USER_GUIDE.md`, `LICENSE.md`. These are the docs that ride along in a
/// build, so these are the ones whose freshness matters.
List<String> declaredMarkdownAssets(String pubspec) {
  final re = RegExp(r'^\s*-\s+(\S+\.md)\s*$', multiLine: true);
  return [for (final m in re.allMatches(pubspec)) m.group(1)!]..sort();
}

/// The sentinel used to locate the built assets directory: a doc that is always
/// bundled, so wherever its copy sits, its grandparent is the assets root.
const _sentinel = 'docs/USER_GUIDE.md';

/// Finds the built assets directory under [root] — the one holding the sentinel
/// doc — regardless of platform nesting (web `assets/`, desktop `flutter_assets/`).
/// Returns null when no built docs are found (wrong directory, or no build).
Directory? findAssetsDir(Directory root) {
  if (!root.existsSync()) return null;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File &&
        entity.path.replaceAll('\\', '/').endsWith(_sentinel)) {
      // <assetsDir>/docs/USER_GUIDE.md → strip the trailing `docs/USER_GUIDE.md`.
      final p = entity.path.replaceAll('\\', '/');
      return Directory(p.substring(0, p.length - _sentinel.length - 1));
    }
  }
  return null;
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/check_bundled_docs_fresh.dart <build-root>',
    );
    exit(2);
  }
  final root = Directory(args.single);

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln(
      'check-bundled-docs-fresh: run from the repository root '
      '(no pubspec.yaml here).',
    );
    exit(2);
  }
  final assets = declaredMarkdownAssets(pubspec.readAsStringSync());
  if (assets.isEmpty) {
    stderr.writeln(
      'check-bundled-docs-fresh: no Markdown assets declared in '
      'pubspec.yaml — nothing to check (broken scan?).',
    );
    exit(2);
  }

  final assetsDir = findAssetsDir(root);
  if (assetsDir == null) {
    stderr.writeln(
      'check-bundled-docs-fresh: found no built docs under '
      "'${root.path}'. Point this at a build output (build/web, build/macos, "
      'build/linux) after building.',
    );
    exit(2);
  }

  final source = <String, List<int>>{};
  final bundled = <String, List<int>?>{};
  for (final asset in assets) {
    final src = File(asset);
    if (!src.existsSync()) {
      // A declared asset with no source file is a pubspec bug, not a stale
      // build; surface it plainly rather than reporting it as "missing".
      stderr.writeln(
        "check-bundled-docs-fresh: declared asset '$asset' has no "
        'source file on disk.',
      );
      exit(2);
    }
    source[asset] = src.readAsBytesSync();
    final built = File('${assetsDir.path}/$asset');
    bundled[asset] = built.existsSync() ? built.readAsBytesSync() : null;
  }

  final result = compareDocs(source: source, bundled: bundled);
  if (result.ok) {
    stdout.writeln(
      'Bundled docs fresh: ${result.checked} document(s) in '
      "'${assetsDir.path}' match the source.",
    );
    return;
  }

  stderr.writeln(
    '== Bundled documentation is STALE or MISSING in the build ==',
  );
  stderr.writeln("Assets directory: '${assetsDir.path}'");
  if (result.stale.isNotEmpty) {
    stderr.writeln('Stale (built copy differs from source):');
    for (final p in result.stale) {
      stderr.writeln('  - $p');
    }
  }
  if (result.missing.isNotEmpty) {
    stderr.writeln('Missing (declared but not in the build):');
    for (final p in result.missing) {
      stderr.writeln('  - $p');
    }
  }
  stderr.writeln(
    '\nThe build did not re-bundle the current docs. Do a clean '
    'rebuild (`flutter clean` then rebuild) so the release ships the current '
    'documentation, and re-run this check.',
  );
  exit(1);
}
