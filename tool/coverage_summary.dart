// Summarise line coverage from an lcov report and, optionally, enforce a floor.
//
//   flutter test --coverage
//   dart run tool/coverage_summary.dart [--min=50]   (or: make coverage)
//
// Reads coverage/lcov.info, prints overall line coverage, and exits non-zero
// when --min=<percent> is given and the coverage is below it, so it can gate CI.
//
// Note: lcov only lists files that a test imported, so files with no test at all
// are absent from the denominator — treat the number as a trend, not an absolute.

import 'dart:io';

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
  for (final arg in args) {
    if (arg.startsWith('--min=')) min = double.tryParse(arg.substring(6));
  }
  if (min != null && pct < min) {
    stderr.writeln(
      'Coverage ${pct.toStringAsFixed(1)}% is below the required '
      '${min.toStringAsFixed(1)}%.',
    );
    exit(1);
  }
}

int _fileCount(File report) {
  var n = 0;
  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) n++;
  }
  return n;
}
