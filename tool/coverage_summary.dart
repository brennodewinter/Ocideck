// Summarise line coverage from an lcov report and, optionally, enforce a floor.
//
//   flutter test --coverage
//   dart run tool/coverage_summary.dart [--min=50] [--require-instrumented]
//                                       [--per-file-floor]
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
//
// --per-file-floor closes the *second* hole: being in the denominator is not
// being executed. A file can be imported by a test and still run zero lines —
// on 2026-07-21 twenty-two lib/ files were in that state, 1.219 lines between
// them, and every one of them sailed through both checks above, because an
// 80% average absorbs a single file that never runs. A floor that looks at the
// mean cannot see the worst case; this flag looks at the worst case.

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
  // NO EXECUTABLE LINES: `media_fetch.dart` is een kale export-facade — één
  // conditional export en verder niets. PLATFORM: `media_fetch_web.dart` is de
  // web-helft daarvan; daar opent de browser de verbinding en valt er niets te
  // pinnen. De io-helft, waar de SSRF-poort zit, wordt wél getest
  // (media_fetch_test.dart).
  'lib/utils/media_fetch.dart',
  'lib/utils/media_fetch_web.dart',
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
  // PLATFORM: conditional-import facades + their io/web halves. De io-helft van
  // native_window staat hier NIET meer: dat was gewone dart:io-code met
  // negentien echte statements, geen platformnaad. Zie native_window_test.dart,
  // dat het `window_manager`-kanaal namaakt en de opstartvolgorde toetst.
  'lib/platform/native_window.dart',
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
  // PLATFORM: de webhelft van de rem op het sluiten van een tabblad. Dit is
  // `dart:js_interop`-code (`beforeunload`); de VM-runner kan haar niet laden.
  // De gevel én de io-helft worden wél uitgevoerd — zie
  // test/web_no_recovery_notice_test.dart.
  'lib/platform/unsaved_work_guard_web.dart',
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
  'lib/services/finding_templates/tr.dart',
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
  // NO EXECUTABLE LINES: the two stand-alone dark palettes — nothing but
  // `static const Color` tokens. They used to hold one unreachable line each (a
  // private constructor that existed only to block instantiation) and therefore
  // sat at 0% forever, which no test could ever fix. They are now
  // `abstract final class`, the way `finding_severity_palette.dart` already
  // did it, which says the same thing without a statement to reach.
  'lib/theme/image_picker_palette.dart',
  'lib/theme/presenter_palette.dart',
};

/// The per-file coverage floor: a lib/ file below this fraction of executed
/// lines counts as untested. RATCHET: may rise, never fall.
///
/// Why 20 and not 80: at 20% a file has at least one line in five that some
/// test really runs — enough that a behaviour change somewhere in it stands a
/// chance of turning a test red. Below that the file is decoration in the
/// report. The number is deliberately reachable today so that the *budget*
/// below is the thing that squeezes; raise it once the budget is near zero.
const int perFileFloorPercent = 20;

/// How many lib/ files may sit below [perFileFloorPercent]. RATCHET: may
/// shrink, never grow — and it must track reality, so the check also fails when
/// the budget is left standing well above the true count (see [_staleSlack]).
///
/// This is a number and not a list of blessed files on purpose. A list grows
/// quietly: every new untested file gets one more line and nobody notices. A
/// budget cannot absorb anything — a new untested file pushes the count over
/// and the gate goes red, and the only way to make it green is to write a test
/// or to visibly, deliberately edit this number upwards in a commit somebody
/// has to justify.
///
/// Where it must go: 0. Every step down is one file that went from decoration
/// to something a test can hold accountable. It started at 39 on 2026-07-21
/// (22 of those files ran not a single line). On 2026-07-22 the shell command
/// layer came down: `ai_actions`, `shell_actions_git_assets`,
/// `shell_actions_s3`, `shell_actions` and `shell_actions_connections` went
/// from decoration to tested, and only two files still run not a single line.
/// What is left is mostly the git dialogs and a handful of platform halves.
///
/// 15 and not 14: the shell work brought the count to 14, and rebasing onto a
/// main that had moved on by 76 commits added `widgets/mermaid_render_host.dart`
/// (31 lines, 12.9%). That is a shared WebView host — the kind of component a
/// headless test cannot drive — so it is counted rather than papered over. The
/// step in this change is still 21 -> 15.
const int filesBelowFloorBudget = 15;

/// Slack on the downward ratchet. Coverage of a file that sits near the floor
/// can wobble by one when an optional dependency (the native OpenCV library
/// behind DARTCV_LIB_PATH) is absent, so demanding an exact match would make
/// the gate depend on the machine. More than this and the budget is stale.
const int _staleSlack = 2;

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
  var perFileFloor = false;
  for (final arg in args) {
    if (arg.startsWith('--min=')) min = double.tryParse(arg.substring(6));
    if (arg == '--require-instrumented') requireInstrumented = true;
    if (arg == '--per-file-floor') perFileFloor = true;
  }

  var failed = false;

  if (requireInstrumented && !_checkInstrumented(report)) failed = true;

  if (perFileFloor && !_checkPerFileFloor(report)) failed = true;

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

/// One file's line tally, as lcov reports it.
typedef _FileCoverage = ({String path, int hit, int found});

/// Reads every per-file record from the lcov report. Files with no executable
/// line at all are dropped: they carry no percentage to speak of.
List<_FileCoverage> _perFile(File report) {
  final result = <_FileCoverage>[];
  String? path;
  var found = 0;
  var hit = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      path = line.substring(3).trim();
      found = 0;
      hit = 0;
    } else if (line.startsWith('LF:')) {
      found = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      hit = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.trim() == 'end_of_record' && path != null && found > 0) {
      result.add((path: path, hit: hit, found: found));
    }
  }
  return result;
}

/// Fails when more lib/ files sit below [perFileFloorPercent] than
/// [filesBelowFloorBudget] allows, and equally when the budget has been left
/// standing above the truth. Returns true when the tree is clean.
bool _checkPerFileFloor(File report) {
  final below =
      _perFile(report)
          .where((f) => !_isTranslationData(f.path))
          .where((f) => f.hit * 100 < perFileFloorPercent * f.found)
          .toList()
        ..sort((a, b) {
          final byShare = (a.hit / a.found).compareTo(b.hit / b.found);
          return byShare != 0 ? byShare : a.path.compareTo(b.path);
        });

  final dead = below.where((f) => f.hit == 0).length;
  stdout.writeln(
    'Per-file floor: ${below.length}/$filesBelowFloorBudget file(s) below '
    '$perFileFloorPercent% executed lines ($dead of them at zero).',
  );

  if (below.length > filesBelowFloorBudget) {
    stderr.writeln(
      '${below.length} lib/ file(s) run less than $perFileFloorPercent% of '
      'their lines, but only $filesBelowFloorBudget are budgeted. A test that '
      'imports a file without running it keeps the file in the denominator and '
      'the average hides it — that is what this floor is for. Write a test for '
      'one of these, or (deliberately, and with a reason in the commit) raise '
      'filesBelowFloorBudget in tool/coverage_summary.dart:\n'
      '${below.map(_describe).join('\n')}',
    );
    return false;
  }

  if (below.length < filesBelowFloorBudget - _staleSlack) {
    stderr.writeln(
      'Only ${below.length} lib/ file(s) are below $perFileFloorPercent%, but '
      'filesBelowFloorBudget still says $filesBelowFloorBudget. A ratchet that '
      'lags reality gives back the ground you just won: set '
      'filesBelowFloorBudget in tool/coverage_summary.dart to ${below.length}.',
    );
    return false;
  }
  return true;
}

String _describe(_FileCoverage f) {
  final pct = (f.hit / f.found * 100).toStringAsFixed(1).padLeft(5);
  return '    $pct%  ${f.hit}/${f.found}  ${f.path}';
}

int _fileCount(File report) {
  var n = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) n++;
  }
  return n;
}
