import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('scripts/release_auto.sh').readAsStringSync();
  final skip = Platform.isWindows
      ? 'release orchestration uses POSIX bash'
      : null;
  final start = source.indexOf('find_release_pr() {');
  final end = source.indexOf('\n}', start) + 2;
  final function = source.substring(start, end);
  final parser = source.substring(
    source.indexOf('RESUME=0\n'),
    source.indexOf('# --print-version is een hermetische'),
  );

  ProcessResult run(String body, {List<String> args = const []}) {
    return Process.runSync('bash', ['-c', body, 'test', ...args]);
  }

  String harness(
    Map<String, Object?> pr, {
    String tag = '',
    bool fail = false,
  }) {
    final response = jsonEncode(pr);
    return '''
set -euo pipefail
RELEASE_PR=42
TAG=v0.7.6
NEW_VERSION=0.7.6
BRANCH=release/v0.7.6
die() { printf '%s\\n' "\$1" >&2; exit 42; }
git() { printf '%s' '$tag'; }
api() { ${fail ? 'return 1' : "printf '%s' '$response'"}; }
$function
find_release_pr
''';
  }

  final valid = <String, Object?>{
    'number': 42,
    'title': 'chore(release): versie 0.7.6',
    'base': {'ref': 'main'},
    'state': 'closed',
    'merged': true,
    'head': {'sha': 'a' * 40},
    'merge_commit_sha': 'b' * 40,
  };

  test('explicit merged release PR returns the normal selection format', () {
    final result = run(harness(valid));
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, '42|closed|true|${'a' * 40}|${'b' * 40}\n');
  }, skip: skip);

  test('explicit selector rejects unrelated or incomplete PR responses', () {
    for (final change in <Map<String, Object?>>[
      {'number': 43},
      {'title': 'chore(release): versie 0.7.7'},
      {
        'base': {'ref': 'other'},
      },
      {'merged': false},
      {'state': 'open'},
      {'merge_commit_sha': null},
      {
        'head': {'sha': 'short'},
      },
    ]) {
      final result = run(harness({...valid, ...change}));
      expect(result.exitCode, 42, reason: '$change: ${result.stderr}');
    }
    expect(run(harness({})).exitCode, 42);
    expect(run(harness(valid, fail: true)).exitCode, 42);
    expect(run(harness(valid, tag: 'published')).exitCode, 42);
  }, skip: skip);

  test('tag on mirror and remote lookup failure both reject selection', () {
    for (final git in [
      'git() { if [ "\$2" = mirror ]; then echo published; fi; }',
      'git() { return 1; }',
    ]) {
      final body = harness(
        valid,
      ).replaceFirst("git() { printf '%s' ''; }", git);
      expect(run(body).exitCode, 42);
    }
  }, skip: skip);

  test('implicit selection still refuses multiple release PRs', () {
    final result = run('''
set -euo pipefail
RELEASE_PR=''
NEW_VERSION=0.7.6
BRANCH=release/v0.7.6
die() { exit 42; }
api() { printf '%s' '${jsonEncode([
      valid,
      {...valid, 'number': 43},
    ])}'; }
$function
find_release_pr
''');
    expect(result.exitCode, 42);
  }, skip: skip);

  test('CLI accepts only one positive explicit PR in resume mode', () {
    final body =
        '''
set -euo pipefail
die() { exit 42; }
GATE_TIMEOUT_MIN=720
RELEASE_CI_TIMEOUT_MIN=960
LEVEL=''
RESUME_TAG=''
$parser
printf '%s' "\$RELEASE_PR"
''';
    final accepted = run(
      body,
      args: ['--resume', 'v0.7.6', '--release-pr', '42'],
    );
    expect(accepted.exitCode, 0, reason: '${accepted.stderr}');
    expect(accepted.stdout, '42');
    for (final args in [
      ['--release-pr', '42'],
      ['--status', 'v0.7.6', '--release-pr', '42'],
      ['--resume', 'v0.7.6', '--release-pr'],
      ['--resume', 'v0.7.6', '--release-pr', '0'],
      ['--resume', 'v0.7.6', '--release-pr', '-1'],
      ['--resume', 'v0.7.6', '--release-pr', '01'],
      ['--resume', 'v0.7.6', '--release-pr', '42', '--release-pr', '43'],
      ['--resume', 'v0.7.6', '--release-pr', '42', '--candidate-sha', 'a' * 40],
    ]) {
      expect(run(body, args: args).exitCode, 42, reason: '$args');
    }
  }, skip: skip);
}
