import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

/// Guards that every Markdown document under `docs/` is actually reachable by
/// the user: bundled as an asset in `pubspec.yaml` AND surfaced in the in-app
/// reader (Settings → Documentation) via a `_docTile(..., assetBase: ...)`
/// reference. Without this, dropping a new doc into `docs/` silently ships a
/// file nobody can open — exactly the gap that hid ARCHITECTURE, BUILD, CHECKS,
/// SOURCE_MAP, LICENSE_COMPLIANCE, SBOM and the design spec for a while.
///
/// Design docs (`docs/design/**`) are treated as their own class and checked
/// separately, so a missing design doc reports distinctly from a missing
/// general doc.
void main() {
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

  void expectAllRegistered(String label, List<String> docs) {
    expect(
      docs,
      isNotEmpty,
      reason: 'No $label found — broken discovery scan.',
    );
    final missingAsset = docs.where((p) => !bundledAsset(p)).toList();
    final missingTile = docs.where((p) => !surfacedInReader(p)).toList();
    expect(
      missingAsset,
      isEmpty,
      reason:
          '$label not bundled as assets in pubspec.yaml (add each under '
          '`assets:`): $missingAsset',
    );
    expect(
      missingTile,
      isEmpty,
      reason:
          '$label not shown in Settings → Documentation. Add a `_docTile(..., '
          "assetBase: '<path>')` in settings_dialog_docs.dart (and a `.d()` "
          'title translated in every language): $missingTile',
    );
  }

  test('every general doc in docs/ is bundled and surfaced in the reader', () {
    expectAllRegistered('general docs (docs/*.md)', markdownIn('docs'));
  });

  test(
    'every design doc in docs/design/ is bundled and surfaced (own class)',
    () {
      expectAllRegistered(
        'design docs (docs/design/*.md)',
        markdownIn('docs/design'),
      );
    },
  );
}
