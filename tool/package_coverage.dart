// The line-coverage floor for one package under packages/ (FORM_INTAKE.md §17).
//
//   dart run tool/package_coverage.dart --package=packages/ocideck_form_core \
//       --min=90 --per-file-floor=60
//
// Reads <package>/coverage/lcov.info, which `make test-packages` writes. The
// app's own tool (`coverage_summary.dart`) is tied to the app's lib/ and carries
// a ratchet of historical exceptions; a new package starts with none, so it gets
// the same three guarantees without that machinery:
//
//   * an overall floor — the average;
//   * every lib/ file is in at least one test — lcov omits a file no test
//     imports, so such a file is not 0%, it is *outside* the fraction, and no
//     percentage can ever see it;
//   * a per-file floor — a file a test imports but never calls hides inside a
//     healthy average.
//
// A "barrel" (a file that only declares `library`, `export`s and comments) has
// nothing to execute and so no lcov record; it is exempt from the second rule.

import 'dart:io';

/// Whether [source] holds nothing but `library`, `export`, `part` and comments,
/// i.e. has no executable line for lcov to record.
bool isBarrelFile(String source) {
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('//')) continue;
    if (line.startsWith('library') ||
        line.startsWith('export ') ||
        line.startsWith('part ') ||
        line.startsWith('part of ')) {
      continue;
    }
    return false;
  }
  return true;
}

/// One file's tally from an lcov report.
typedef _Tally = ({int found, int hit});

Map<String, _Tally> _parse(String lcov, String packageRoot) {
  final prefix = '${packageRoot.replaceAll(r'\', '/')}/';
  final out = <String, _Tally>{};
  String? file;
  var found = 0;
  var hit = 0;
  for (final raw in lcov.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      var path = line.substring(3).replaceAll(r'\', '/');
      if (path.startsWith(prefix)) path = path.substring(prefix.length);
      file = path;
      found = 0;
      hit = 0;
    } else if (line.startsWith('LF:')) {
      found = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      hit = int.tryParse(line.substring(3)) ?? 0;
    } else if (line == 'end_of_record' && file != null) {
      out[file] = (found: found, hit: hit);
      file = null;
    }
  }
  return out;
}

/// Every way [lcov] falls short of the floors, one readable line each. Empty
/// means clean. [sources] maps a package-relative path (`lib/src/a.dart`) to its
/// text; [packageRoot] is stripped from the absolute paths lcov writes.
List<String> packageCoverageProblems({
  required String lcov,
  required Map<String, String> sources,
  required String packageRoot,
  required double minPercent,
  required int perFileFloorPercent,
}) {
  final tallies = _parse(lcov, packageRoot);
  final measurable = {
    for (final e in sources.entries)
      if (!isBarrelFile(e.value)) e.key,
  };
  if (measurable.isEmpty) return const [];

  final problems = <String>[];

  // Files in no test at all: absent from the report.
  final absent = measurable.where((f) => !tallies.containsKey(f)).toList()
    ..sort();
  if (absent.isNotEmpty) {
    problems.add(
      '${absent.length} file(s) are in no test, so they never reach the '
      'coverage denominator — the percentage cannot see them. Write a test:\n'
      '    ${absent.join('\n    ')}',
    );
  }

  var found = 0;
  var hit = 0;
  for (final e in tallies.entries) {
    if (!measurable.contains(e.key)) continue;
    found += e.value.found;
    hit += e.value.hit;
  }
  if (found == 0) return problems;

  final pct = hit / found * 100;
  if (pct < minPercent) {
    problems.add(
      'Line coverage ${pct.toStringAsFixed(1)}% is below the required '
      '${minPercent.toStringAsFixed(1)}%.',
    );
  }

  final thin = <String>[];
  for (final e in tallies.entries) {
    if (!measurable.contains(e.key) || e.value.found == 0) continue;
    if (e.value.hit * 100 < perFileFloorPercent * e.value.found) {
      final share = (e.value.hit / e.value.found * 100).floor();
      thin.add('${e.key} ($share% — ${e.value.hit}/${e.value.found} lines)');
    }
  }
  thin.sort();
  if (thin.isNotEmpty) {
    problems.add(
      '${thin.length} file(s) run less than $perFileFloorPercent% of their own '
      'lines — imported by a test but barely called:\n    ${thin.join('\n    ')}',
    );
  }
  return problems;
}

void main(List<String> args) {
  String? package;
  var min = 90.0;
  var perFile = 60;
  for (final arg in args) {
    if (arg.startsWith('--package=')) package = arg.substring(10);
    if (arg.startsWith('--min=')) {
      min = double.tryParse(arg.substring(6)) ?? min;
    }
    if (arg.startsWith('--per-file-floor=')) {
      perFile = int.tryParse(arg.substring(17)) ?? perFile;
    }
  }
  if (package == null) {
    stderr.writeln('usage: package_coverage.dart --package=packages/<name>');
    exit(2);
  }
  final dir = Directory(package);
  final report = File('${dir.path}/coverage/lcov.info');
  if (!report.existsSync()) {
    stderr.writeln('${report.path} not found — run "make test-packages".');
    exit(1);
  }
  final sources = <String, String>{};
  final lib = Directory('${dir.path}/lib');
  if (lib.existsSync()) {
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = f.path.substring(dir.path.length + 1).replaceAll(r'\', '/');
      sources[rel] = f.readAsStringSync();
    }
  }
  final problems = packageCoverageProblems(
    lcov: report.readAsStringSync(),
    sources: sources,
    packageRoot: dir.absolute.path,
    minPercent: min,
    perFileFloorPercent: perFile,
  );
  if (problems.isEmpty) {
    stdout.writeln('$package: coverage OK (floor $min%, per-file $perFile%).');
    return;
  }
  for (final p in problems) {
    stderr.writeln('$package: $p');
  }
  exit(1);
}
