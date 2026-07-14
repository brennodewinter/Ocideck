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
  'lib/services/secmodule/sec_pack_platform.dart',
  'lib/services/secmodule/sec_pack_platform_web.dart',
  'lib/utils/file_download.dart',
  'lib/utils/file_download_web.dart',
  // NO EXECUTABLE LINES: const data table (345 lines, zero statements).
  'lib/services/cvss/cvss4_lookup.dart',
  // NO EXECUTABLE LINES: const configuration only.
  'lib/services/secmodule/sec_pack_config.dart',
  // NO EXECUTABLE LINES: a single `export`.
  'lib/widgets/markdown_notes_editor.dart',
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
