// Summarise line coverage from an lcov report and, optionally, enforce a floor.
//
//   flutter test --coverage
//   dart run tool/coverage_summary.dart [--min=50] [--require-instrumented]
//   (or: make coverage)
//
// Reads coverage/lcov.info, prints overall line coverage, and exits non-zero
// when --min=<percent> is given and the coverage is below it, so it can gate CI.
//
// --require-instrumented closes the hole in that percentage. lcov only records
// files a test actually imported, so a file NO test imports is not 0% — it is
// absent from the denominator entirely. Add a brand-new, wholly untested file
// and the percentage does not move a hair: the one thing a coverage floor is
// supposed to catch is the one thing it structurally cannot see. This flag
// enumerates lib/ from disk instead and fails on any file missing from the
// report that is not in [uncoveredBaseline].

import 'dart:io';

/// lib/ files legitimately absent from lcov. RATCHET: may shrink, never grow.
///
/// There are exactly two legitimate reasons to be here:
///
///   * PLATFORM — a conditional-import facade or its web half. The VM test
///     runner cannot load `dart:js_interop` code at all, so these can never be
///     instrumented, no matter how many tests you write.
///   * NO EXECUTABLE LINES — a bare `export` barrel, a lone enum, or a const
///     data table. lcov emits no record for a file with nothing to execute.
///
/// A file that is merely *untested* does not belong here: write the test.
const Set<String> uncoveredBaseline = {
  // NO EXECUTABLE LINES: `StorageOrigin` is een abstract interface met twee
  // getters en verder niets — het contract dat WebdavOrigin, S3Origin en
  // GitOrigin delen. De implementaties worden wél getest
  // (tab_storage_origin_test.dart), maar lcov schrijft geen record voor een
  // bestand zonder uitvoerbare regels.
  'lib/models/storage_origin.dart',
  // NO EXECUTABLE LINES: `PresentationSource` is idem een abstract interface —
  // één getter en één methode, verder niets — het contract dat de zoekbronnen
  // van 'Slide zoeken' delen. De implementaties worden wél getest
  // (git_presentation_source_test.dart, remote_presentation_source_test.dart),
  // maar lcov schrijft geen record voor een bestand zonder uitvoerbare regels.
  'lib/services/presentation_search/presentation_source.dart',
  // NO EXECUTABLE LINES: the generated MASTG index — two `part` files holding
  // nothing but a const list of 186 MastgTest literals. They are exercised
  // (mastg_catalog_test.dart reads every entry) but lcov emits no record for a
  // file with nothing to execute. Split in two only because 186 entries in one
  // file crosses the 1000-line ratchet.
  'lib/services/mastg_catalog_android.dart',
  'lib/services/mastg_catalog_ios.dart',
  // NO EXECUTABLE LINES: idem voor de gegenereerde MASWE-lijst, gesplitst op
  // uitgeschreven versus concept omdat dat het onderscheid is dat de catalogus
  // zelf maakt.
  'lib/services/maswe_catalog_written.dart',
  'lib/services/maswe_catalog_draft.dart',
  // NO EXECUTABLE LINES: idem voor de WSTG-index, sinds die uit
  // tool/build_wstg_catalog.dart komt in plaats van met de hand overgetikt.
  'lib/services/wstg_catalog_data.dart',
  // NO EXECUTABLE LINES: de woordenlijst van de markdown-checker — een `part`
  // met alleen const sets (class-tokens, front-matter sleutels, directives).
  // Ruim gedekt via markdown_validator_test.dart, maar lcov ziet niets om uit
  // te voeren. Afgesplitst omdat de validator anders de 1000-regel-ratchet
  // overschrijdt.
  'lib/services/markdown_validator_vocabulary.dart',
  // PLATFORM: entrypoint — runApp() never executes under the test runner.
  'lib/main.dart',
  // PLATFORM: conditional-import facades + their io/web halves.
  'lib/platform/native_window.dart',
  'lib/platform/native_window_io.dart',
  'lib/platform/native_window_stub.dart',
  'lib/platform/platform_features_web.dart',
  'lib/platform/presenter_fullscreen_web.dart',
  'lib/services/cve_transport_factory.dart',
  'lib/services/cve_transport_web.dart',
  // PLATFORM: the git transport's conditional-export facade (its two halves are
  // exercised via the forge contract). A one-line `export … if …` barrel with
  // no statement to reach — the same seam as cve_transport_factory above.
  'lib/services/git/git_transport_factory.dart',
  // PLATFORM: the native-git CLI's conditional-export facade + its web stub. The
  // io half (NativeGitCli) is exercised directly by git_cli_test.dart; the web
  // stub and the one-line barrel are the platform seam the VM runner can't load.
  'lib/services/git/git_cli_factory.dart',
  'lib/services/git/git_cli_web.dart',
  // PLATFORM: the native git mirror's conditional-export facade + its web stub.
  // The io half is exercised by native_git_mirror_test.dart against a real repo.
  'lib/services/git/native_git_mirror_factory.dart',
  'lib/services/git/native_git_mirror_stub.dart',
  // PLATFORM: the git draft store's conditional-export facade. Both halves
  // (FileDraftStore, PrefsDraftStore) are exercised by the DeckMirror contract
  // in test/git_deck_mirror_contract_test.dart; only this one-line barrel has no
  // statement for a line counter to reach.
  'lib/services/git/draft_store_factory.dart',
  // PLATFORM: the local CVE database's conditional-export facade + its web half
  // (the feature is desktop-only; the io half is exercised by the ingest tests).
  'lib/services/cve/local_cve_database.dart',
  'lib/services/cve/local_cve_database_web.dart',
  'lib/utils/file_download.dart',
  'lib/utils/file_download_web.dart',
  // NO EXECUTABLE LINES: const data table (345 lines, zero statements).
  'lib/services/cvss/cvss4_lookup.dart',
  // NO EXECUTABLE LINES: const data tables — the finding templates, one file
  // per language, plus the map that gathers them. Their *content* is asserted
  // hard in test/finding_template_languages_test.dart, which parses every
  // template in every language and checks the fixed parts field by field;
  // there is simply no statement here for a line counter to reach.
  'lib/services/finding_templates/all.dart',
  'lib/services/finding_templates/bg.dart',
  'lib/services/finding_templates/cs.dart',
  'lib/services/finding_templates/da.dart',
  'lib/services/finding_templates/de.dart',
  'lib/services/finding_templates/el.dart',
  'lib/services/finding_templates/en.dart',
  'lib/services/finding_templates/es.dart',
  'lib/services/finding_templates/et.dart',
  'lib/services/finding_templates/fi.dart',
  'lib/services/finding_templates/fr.dart',
  'lib/services/finding_templates/fy.dart',
  'lib/services/finding_templates/ga.dart',
  'lib/services/finding_templates/gsw.dart',
  'lib/services/finding_templates/hr.dart',
  'lib/services/finding_templates/hu.dart',
  'lib/services/finding_templates/id.dart',
  'lib/services/finding_templates/it.dart',
  'lib/services/finding_templates/la.dart',
  'lib/services/finding_templates/lt.dart',
  'lib/services/finding_templates/lv.dart',
  'lib/services/finding_templates/mt.dart',
  'lib/services/finding_templates/nl.dart',
  'lib/services/finding_templates/pap.dart',
  'lib/services/finding_templates/pl.dart',
  'lib/services/finding_templates/pt.dart',
  'lib/services/finding_templates/ro.dart',
  'lib/services/finding_templates/sk.dart',
  'lib/services/finding_templates/sl.dart',
  'lib/services/finding_templates/sv.dart',
  'lib/services/finding_templates/tlh.dart',
  'lib/services/finding_templates/uk.dart',
  // NO EXECUTABLE LINES: const data table — the settings search index. The
  // entries themselves are asserted in test/settings_search_test.dart, which
  // also guards that every section title in here is still rendered.
  'lib/widgets/dialogs/parts/settings_dialog_search_index.dart',
  // NO EXECUTABLE LINES: a single `export`.
  'lib/widgets/markdown_notes_editor.dart',
  // NO EXECUTABLE LINES: an abstract interface (the local CVE database as the
  // UI sees it). Its two implementations are covered separately.
  'lib/services/cve/local_cve_database_api.dart',
  // NO EXECUTABLE LINES: a single enum declaration.
  'lib/widgets/markdown_editor/notes_editor_mode.dart',
};

/// Translation data carries no logic; it is gated by the l10n tests instead.
bool _isTranslationData(String path) => path.contains('lib/l10n/translations/');

void main(List<String> args) {
  final report = File('coverage/lcov.info');
  if (!report.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info not found — run "flutter test --coverage" first.',
    );
    exit(1);
  }

  var found = 0;
  var hit = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      found += int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      hit += int.tryParse(line.substring(3)) ?? 0;
    }
  }

  final pct = found == 0 ? 0.0 : hit / found * 100;
  stdout.writeln(
    'Line coverage: $hit/$found (${pct.toStringAsFixed(1)}%) '
    'across ${_fileCount(report)} instrumented files.',
  );

  double? min;
  var requireInstrumented = false;
  for (final arg in args) {
    if (arg.startsWith('--min=')) min = double.tryParse(arg.substring(6));
    if (arg == '--require-instrumented') requireInstrumented = true;
  }

  var failed = false;

  if (requireInstrumented && !_checkInstrumented(report)) failed = true;

  if (min != null && pct < min) {
    stderr.writeln(
      'Coverage ${pct.toStringAsFixed(1)}% is below the required '
      '${min.toStringAsFixed(1)}%.',
    );
    failed = true;
  }

  if (failed) exit(1);
}

/// Fails when a lib/ file is absent from the report and not baselined — i.e. no
/// test imports it at all. Returns true when the tree is clean.
bool _checkInstrumented(File report) {
  final instrumented = <String>{};
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) instrumented.add(line.substring(3).trim());
  }

  final absent = <String>[];
  for (final entry in Directory('lib').listSync(recursive: true)) {
    if (entry is! File || !entry.path.endsWith('.dart')) continue;
    final path = entry.path.replaceAll(r'\', '/');
    if (_isTranslationData(path)) continue;
    if (instrumented.contains(path)) continue;
    if (uncoveredBaseline.contains(path)) continue;
    absent.add(path);
  }
  absent.sort();

  if (absent.isNotEmpty) {
    stderr.writeln(
      '${absent.length} lib/ file(s) are in no test at all, so they never reach '
      'the coverage denominator — the percentage above cannot see them. Write a '
      'test, or (only for a platform half or a file with no executable lines) '
      'add it to uncoveredBaseline in tool/coverage_summary.dart:\n'
      '    ${absent.join('\n    ')}',
    );
    return false;
  }

  // Ratchet the other way: a baselined file that got covered should leave.
  final covered = uncoveredBaseline.where(instrumented.contains).toList()
    ..sort();
  if (covered.isNotEmpty) {
    stdout.writeln(
      'Tip: ${covered.length} baselined file(s) are now instrumented — drop '
      'them from uncoveredBaseline (tool/coverage_summary.dart) to lock in the '
      'win:\n    ${covered.join('\n    ')}',
    );
  }
  return true;
}

int _fileCount(File report) {
  var n = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) n++;
  }
  return n;
}
