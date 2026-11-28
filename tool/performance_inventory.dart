import 'dart:convert';
import 'dart:io';

const _guide = 'docs/PERFORMANCE_GUIDE.md';
const _section = '### Codebase and bundled assets\n';
const _nextSection = '\n### Measured timing\n';
const _labels = [
  '`lib/` Dart files',
  '`lib/` Dart lines',
  '`test/` Dart test files',
  '`assets/` source bytes',
  '`assets/fonts/` source bytes',
];

void main(List<String> args) {
  if (args.length != 1 || !['--check', '--update'].contains(args.single)) {
    stderr.writeln(
      'Usage: dart tool/performance_inventory.dart --check|--update',
    );
    exitCode = 64;
    return;
  }
  final git = Process.runSync('git', [
    'ls-files',
    '-z',
    '--',
    'lib',
    'test',
    'assets',
  ], stdoutEncoding: utf8);
  if (git.exitCode != 0) {
    stderr.write(git.stderr);
    exitCode = git.exitCode;
    return;
  }

  var dartFiles = 0;
  var dartLines = 0;
  var tests = 0;
  var assets = 0;
  var fonts = 0;
  for (final path in (git.stdout as String).split('\x00').toSet()) {
    if (path.startsWith('lib/') && path.endsWith('.dart')) {
      dartFiles++;
      dartLines += const LineSplitter()
          .convert(File(path).readAsStringSync())
          .length;
    } else if (path.startsWith('test/') && path.endsWith('_test.dart')) {
      tests++;
    } else if (path.startsWith('assets/')) {
      final bytes = File(path).lengthSync();
      assets += bytes;
      if (path.startsWith('assets/fonts/')) fonts += bytes;
    }
  }

  final values = [dartFiles, dartLines, tests, assets, fonts];
  final guide = File(_guide);
  final contents = guide.readAsStringSync();
  final start = contents.indexOf(_section) + _section.length;
  final end = contents.indexOf(_nextSection, start);
  if (start < _section.length || end < 0) {
    stderr.writeln('Performance inventory section missing from $_guide.');
    exitCode = 1;
    return;
  }

  final rows = [
    '| Item | Measured value |',
    '|---|---:|',
    for (var i = 0; i < _labels.length; i++) '| ${_labels[i]} | ${values[i]} |',
  ].join('\n');
  final section = contents.substring(start, end);
  final tableStart = section.indexOf('| Item | Measured value |');
  if (tableStart < 0) {
    stderr.writeln('Performance inventory table missing from $_guide.');
    exitCode = 1;
    return;
  }
  if (args.single == '--update') {
    guide.writeAsStringSync(
      contents.replaceRange(start + tableStart, end, '$rows\n'),
    );
    return;
  }

  for (var i = 0; i < _labels.length; i++) {
    final matches = RegExp(
      '^\\| ${RegExp.escape(_labels[i])} \\| ([0-9]+) \\|\$',
      multiLine: true,
    ).allMatches(section);
    final baseline = matches.length == 1
        ? int.parse(matches.single.group(1)!)
        : 0;
    if (baseline <= 0 || (values[i] - baseline).abs() * 10 > baseline) {
      stderr.writeln(
        '${_labels[i]}: documented $baseline, measured ${values[i]}. '
        'Run dart tool/performance_inventory.dart --update.',
      );
      exitCode = 1;
    }
  }
}
