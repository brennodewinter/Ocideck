import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

/// Guards the deliberate split between the documentation the app **bundles** and
/// the documentation that lives **only in the repository**.
///
/// The app ships a curated subset, surfaced in Settings → Documentation: the
/// user-facing docs, licence/compliance, and the technical docs that bear on
/// *using and running* OciDeck (performance, security design, hosting,
/// migration). The developer-internal docs (architecture, build, checks, source
/// map, API, contributing, dev setup) and every forward-looking design spec
/// (`docs/design/**`) are **not** bundled — they are reachable from the reader's
/// repository footer instead of riding along in every build.
///
/// Two ways this can go wrong, both closed here:
///   * a **bundled** doc that isn't registered (missing asset line or missing
///     tile) → shipped but unopenable, the gap that once hid ARCHITECTURE,
///     BUILD, CHECKS, SOURCE_MAP, LICENSE_COMPLIANCE, SBOM and a design spec;
///   * a **repo-only** doc that leaked back into the bundle (asset line or tile)
///     → the "everything ships" state this split removed.
///
/// A new doc under `docs/` defaults to *must be bundled*, so dropping one in
/// fails this gate until it is either registered (asset + tile) or listed in
/// [repoOnlyDocs]. The decision is forced, never silent — and `docs/design/**`
/// is repo-only wholesale, so a new design spec needs no test change.
void main() {
  // Top-level docs that live in the repository only, not in the app bundle.
  // Everything else directly under `docs/` (that is not a translated variant)
  // must be bundled and surfaced. `docs/design/**` is repo-only by location and
  // needs no entry here.
  const repoOnlyDocs = {
    'docs/ARCHITECTURE.md',
    'docs/BUILD.md',
    'docs/CHECKS.md',
    'docs/SOURCE_MAP.md',
    'docs/API_DOCUMENTATION.md',
    'docs/CONTRIBUTING_GUIDELINES.md',
    'docs/DEVELOPMENT_SETUP_GUIDE.md',
  };

  final languageCodes = AppLocalizations.languageNames.keys.toSet();

  // `NAME.<lang>.md` variants are alternative translations of an existing base
  // document, picked up automatically by DocumentationService — they must NOT
  // get their own asset line or tile, so exclude them from the guard.
  bool isTranslatedVariant(String path) {
    final name = path.split('/').last;
    final parts = name.split('.');
    return parts.length >= 3 &&
        parts[parts.length - 1] == 'md' &&
        languageCodes.contains(parts[parts.length - 2]);
  }

  List<String> markdownIn(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .where((p) => p.endsWith('.md') && !isTranslatedVariant(p))
        .toList()
      ..sort();
  }

  final pubspec = File('pubspec.yaml').readAsStringSync();
  final tab = File(
    'lib/widgets/dialogs/parts/settings_dialog_docs.dart',
  ).readAsStringSync();

  bool bundledAsset(String path) {
    return RegExp(
      '^\\s*-\\s+${RegExp.escape(path)}\\s*\$',
      multiLine: true,
    ).hasMatch(pubspec);
  }

  bool surfacedInReader(String path) => tab.contains("'$path'");

  test('every bundled doc is an asset and surfaced in the reader', () {
    final bundled = markdownIn(
      'docs',
    ).where((p) => !repoOnlyDocs.contains(p)).toList();
    expect(
      bundled,
      isNotEmpty,
      reason: 'No bundled docs found — broken discovery scan.',
    );
    final missingAsset = bundled.where((p) => !bundledAsset(p)).toList();
    final missingTile = bundled.where((p) => !surfacedInReader(p)).toList();
    expect(
      missingAsset,
      isEmpty,
      reason:
          'Bundled docs not declared as assets in pubspec.yaml (add each under '
          '`assets:`, or move to repoOnlyDocs if it should not ship): '
          '$missingAsset',
    );
    expect(
      missingTile,
      isEmpty,
      reason:
          'Bundled docs not shown in Settings → Documentation. Add a '
          "`DocEntry(..., assetBase: '<path>')` in settings_dialog_docs.dart "
          '(and a `.d()` title translated in every language), or move to '
          'repoOnlyDocs: $missingTile',
    );
  });

  test('repo-only docs are neither bundled nor surfaced', () {
    // The explicit top-level list plus every design doc: `docs/design/**` is
    // repo-only wholesale. Each must have left the bundle entirely — no asset
    // line and no tile — otherwise a doc the split removed crept back in.
    final designDocs = markdownIn('docs/design');
    expect(
      designDocs,
      isNotEmpty,
      reason: 'No design docs found — broken discovery scan.',
    );
    final repoOnly = <String>{...repoOnlyDocs, ...designDocs};
    final leakedAsset = repoOnly.where(bundledAsset).toList()..sort();
    final leakedTile = repoOnly.where(surfacedInReader).toList()..sort();
    expect(
      leakedAsset,
      isEmpty,
      reason:
          'Repo-only docs are still bundled as assets in pubspec.yaml — remove '
          'the asset line; the repository is their home: $leakedAsset',
    );
    expect(
      leakedTile,
      isEmpty,
      reason:
          'Repo-only docs are still shown in Settings → Documentation — remove '
          'the DocEntry tile: $leakedTile',
    );
  });

  test('every repo-only entry names a file that exists', () {
    // Keep [repoOnlyDocs] honest: a stale entry (a doc renamed or removed) would
    // silently stop guarding a path that no longer exists, and a future doc of
    // the same name would be excluded by accident.
    final missing = repoOnlyDocs.where((p) => !File(p).existsSync()).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'repoOnlyDocs names files that no longer exist: $missing',
    );
  });
}
