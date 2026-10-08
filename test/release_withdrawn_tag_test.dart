@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A withdrawn tag was never distributed. The next changelog range must start
/// after the last distributed tag, otherwise every commit that only existed in
/// the withdrawn build silently disappears from the next release notes.
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh is only supported on macOS/Linux'
      : null;

  String allFunctionDefinitions(String source) {
    final lines = source.split('\n');
    final out = <String>[];
    final open = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*\(\)\s*\{');
    for (var i = 0; i < lines.length; i++) {
      if (!open.hasMatch(lines[i])) continue;
      for (; i < lines.length; i++) {
        out.add(lines[i]);
        if (RegExp(r'^\}\s*$').hasMatch(lines[i])) break;
      }
    }
    return out.join('\n');
  }

  test('0.6.15 is explicitly recorded as withdrawn and never distributed', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    const heading = '## [0.6.15] — 2026-10-08 — Withdrawn (never distributed)';
    expect(
      changelog,
      contains(heading),
      reason:
          'A tag that was retracted before distribution must not read as a '
          'published release in the permanent changelog.',
    );
    final tombstone = changelog.substring(
      changelog.indexOf(heading),
      changelog.indexOf('## [0.6.14]'),
    );
    expect(tombstone, contains('nooit gepubliceerd'));
    expect(
      RegExp(r'^### ', multiLine: true).hasMatch(tombstone),
      isFalse,
      reason:
          'The withdrawn section is a tombstone; its unreleased entries must '
          'move to the next release instead of appearing as distributed here.',
    );
  });

  test('the changelog range skips a withdrawn latest tag', () {
    final source = File(script).readAsStringSync();
    final start = source.indexOf('LAST_TAG=');
    final end = source.indexOf('TODAY=', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final selection = source.substring(start, end);

    final dir = Directory.systemTemp.createTempSync('ocideck-withdrawn-tag-');
    addTearDown(() => dir.deleteSync(recursive: true));

    String git(List<String> args) {
      final result = Process.runSync('git', args, workingDirectory: dir.path);
      expect(
        result.exitCode,
        0,
        reason: 'git ${args.join(' ')} failed: ${result.stderr}',
      );
      return (result.stdout as String).trim();
    }

    git(['-c', 'init.defaultBranch=main', 'init', '-q', '.']);
    git(['config', 'user.email', 'test@example.invalid']);
    git(['config', 'user.name', 'test']);
    File('${dir.path}/CHANGELOG.md').writeAsStringSync('''
# Changelog

## Unreleased

- repair after withdrawal

## [0.6.15] — 2026-10-08 — Withdrawn (never distributed)

- content that still belongs in the next release

## [0.6.14] — 2026-10-06

- last distributed release
''');
    git(['add', 'CHANGELOG.md']);
    git(['commit', '-qm', '0.6.14']);
    git(['tag', 'v0.6.14']);
    File('${dir.path}/marker').writeAsStringSync('withdrawn\n');
    git(['add', 'marker']);
    git(['commit', '-qm', '0.6.15']);
    git(['tag', 'v0.6.15']);
    File('${dir.path}/marker').writeAsStringSync('repair\n');
    git(['commit', '-qam', 'repair']);

    final harness = File('${dir.path}/select.sh')
      ..writeAsStringSync(
        'set -euo pipefail\n'
        '${allFunctionDefinitions(source)}\n'
        '$selection\n'
        'printf "%s\\n" "\$LAST_TAG"\n',
      );
    final result = Process.runSync('bash', [
      harness.path,
    ], workingDirectory: dir.path);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      (result.stdout as String).trim(),
      'v0.6.14',
      reason:
          'v0.6.15 was never distributed; the next generated section must '
          'include its commits by ranging from v0.6.14.',
    );
  }, skip: skipOnWindows);

  test('a release promotes all Unreleased content and resets that section', () {
    final source = File(script).readAsStringSync();
    final dir = Directory.systemTemp.createTempSync('ocideck-changelog-bump-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final changelog = File('${dir.path}/CHANGELOG.md')
      ..writeAsStringSync('''
# Changelog

## Unreleased

### Changed

- first curated entry
- second curated entry

## [0.6.15] — 2026-10-08 — Withdrawn (never distributed)

Never distributed.

## [0.6.14] — 2026-10-06

- previous release
''');

    final generate = File('${dir.path}/generate.sh')
      ..writeAsStringSync('''
set -euo pipefail
${allFunctionDefinitions(source)}
NEW_VERSION=0.6.16
TODAY=2026-10-09
LAST_TAG=v0.6.14
generate_changelog_section
''');
    final generated = Process.runSync('bash', [
      generate.path,
    ], workingDirectory: dir.path);
    expect(
      generated.exitCode,
      0,
      reason: '${generated.stdout}\n${generated.stderr}',
    );
    final section = generated.stdout as String;
    expect(section, startsWith('## [0.6.16] — 2026-10-09'));
    expect(section, contains('- first curated entry'));
    expect(section, contains('- second curated entry'));

    const marker = '  python3 - "\$SECTION" <<\'PY\'';
    final commandStart = source.indexOf(marker);
    expect(commandStart, isNonNegative);
    final codeStart = source.indexOf('\n', commandStart) + 1;
    final codeEnd = source.indexOf('\nPY', codeStart);
    expect(codeEnd, greaterThan(codeStart));
    final updateCode = source.substring(codeStart, codeEnd);
    final updated = Process.runSync('python3', [
      '-c',
      updateCode,
      section,
    ], workingDirectory: dir.path);
    expect(updated.exitCode, 0, reason: '${updated.stdout}\n${updated.stderr}');

    final result = changelog.readAsStringSync();
    final unreleasedStart = result.indexOf('## Unreleased');
    final releaseStart = result.indexOf('## [0.6.16]');
    expect(releaseStart, greaterThan(unreleasedStart));
    expect(
      result.substring(unreleasedStart, releaseStart),
      '## Unreleased\n\n',
      reason: 'The promoted Unreleased section must be empty for new work.',
    );
    expect('- first curated entry'.allMatches(result), hasLength(1));
    expect('- second curated entry'.allMatches(result), hasLength(1));
  }, skip: skipOnWindows);
}
