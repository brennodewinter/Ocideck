// Lightweight mutation check for the "dead boolean-operand" bug class — the one
// `dart analyze` and line coverage both miss (e.g. C6: an `||` operand that can
// never be true because an earlier transform stripped the input; the line is
// still hit via another operand, so coverage looks green).
//
// Operator: each `String.startsWith(...)` / `.endsWith(...)` predicate is given
// an impossible argument (type-safe, always compiles) so it is forced to false.
// The given tests are then run. If they STILL pass, that predicate is dead or
// untested → printed as a survivor to review. A genuine, tested predicate makes
// at least one test fail (the mutant is "killed").
//
// Usage:
//   dart run tool/mutation_check.dart <lib-file> <test-path>...
// Example:
//   dart run tool/mutation_check.dart lib/services/markdown_validator.dart \
//     test/markdown_validator_test.dart
//
// The target file is always restored (finally + git checkout safety net).

import 'dart:io';

const _sentinel = "'__MUTATION_IMPOSSIBLE__'";

class _Mutant {
  _Mutant(this.source, this.line, this.snippet);
  final String source;
  final int line;
  final String snippet;
}

int _matchingParen(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

List<_Mutant> _mutants(String src) {
  final out = <_Mutant>[];
  final re = RegExp(r'\.(startsWith|endsWith)\(');
  for (final m in re.allMatches(src)) {
    final open = m.end - 1;
    final close = _matchingParen(src, open);
    if (close < 0) continue;
    final mutated =
        src.substring(0, open + 1) + _sentinel + src.substring(close);
    final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
    final lineStart = src.lastIndexOf('\n', m.start) + 1;
    var lineEnd = src.indexOf('\n', m.start);
    if (lineEnd < 0) lineEnd = src.length;
    out.add(_Mutant(mutated, line, src.substring(lineStart, lineEnd).trim()));
  }
  return out;
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/mutation_check.dart <lib-file> <test-path>...',
    );
    exit(64);
  }
  final target = args.first;
  final tests = args.sublist(1);
  final file = File(target);
  final original = file.readAsStringSync();
  final mutants = _mutants(original);

  stdout.writeln('Mutating $target — ${mutants.length} predicate(s)\n');
  final survivors = <String>[];
  try {
    for (var i = 0; i < mutants.length; i++) {
      final mut = mutants[i];
      file.writeAsStringSync(mut.source);
      final result = await Process.run('flutter', ['test', ...tests]);
      final killed = result.exitCode != 0;
      stdout.writeln(
        '[${i + 1}/${mutants.length}] '
        '${killed ? 'killed  ' : 'SURVIVED'} '
        'L${mut.line}: ${mut.snippet}',
      );
      if (!killed) survivors.add('$target:${mut.line}  ${mut.snippet}');
    }
  } finally {
    file.writeAsStringSync(original);
    // Safety net in case the in-memory restore was bypassed by a crash.
    await Process.run('git', ['checkout', '--', target]);
  }

  stdout.writeln(
    '\n${survivors.length} survivor(s) to review '
    '(dead or untested predicate):',
  );
  for (final s in survivors) {
    stdout.writeln('  $s');
  }
  exit(survivors.isEmpty ? 0 : 1);
}
