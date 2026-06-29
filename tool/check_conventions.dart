// Guards two project conventions in lib/ (see CONTRIBUTING / the logger in
// lib/utils/log.dart):
//
//   * No `print(` — diagnostics go through the logger, never stdout.
//   * No NEW bare `catch (_)` — swallowing errors silently hides failures; catch
//     a typed error and route it through `logError`. A handful of legacy sites
//     remain, so this is a RATCHET: the count may not grow. Lower the baseline
//     as you migrate the remaining ones; it must never be raised.
//
// Exits non-zero (with the offending locations) when a rule is violated.

import 'dart:io';

/// Bare `catch (_)` sites still present in lib/. Ratchet only downwards.
const int catchUnderscoreBaseline = 17;

final _print = RegExp(r'(?<![\w.])print\(');
final _catchUnderscore = RegExp(r'catch\s*\(\s*_\s*\)');

void main() {
  final printHits = <String>[];
  var catchCount = 0;

  for (final file in _dartFiles(Directory('lib'))) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_print.hasMatch(line)) printHits.add('${file.path}:${i + 1}');
      if (_catchUnderscore.hasMatch(line)) catchCount++;
    }
  }

  final failures = <String>[];

  if (printHits.isNotEmpty) {
    failures.add(
      'Found ${printHits.length} `print(` call(s) — use the logger '
      '(lib/utils/log.dart):\n    ${printHits.join('\n    ')}',
    );
  }

  if (catchCount > catchUnderscoreBaseline) {
    failures.add(
      'Bare `catch (_)` count rose to $catchCount (baseline '
      '$catchUnderscoreBaseline). Catch a typed error and call logError, '
      'or lower the baseline if you removed one.',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'Conventions OK: no print(); bare catch (_) at $catchCount '
      '(baseline $catchUnderscoreBaseline).',
    );
    if (catchCount < catchUnderscoreBaseline) {
      stdout.writeln(
        'Tip: bare catch (_) dropped to $catchCount — lower '
        'catchUnderscoreBaseline in tool/check_conventions.dart to lock it in.',
      );
    }
    exit(0);
  }

  stderr.writeln('Convention check FAILED:');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  exit(1);
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
