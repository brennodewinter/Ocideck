import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('scripts/release_auto.sh').readAsStringSync();
  final skip = Platform.isWindows
      ? 'release orchestration uses POSIX bash'
      : null;
  final head = 'a' * 40;
  final merge = 'b' * 40;
  final other = 'c' * 40;
  const base = 'codex/maintenance-0.7.7';

  String function(String name) {
    final start = source.indexOf('$name() {');
    final end = source.indexOf('\n}', start) + 2;
    return source.substring(start, end);
  }

  ProcessResult run(String body, [List<String> args = const []]) {
    return Process.runSync('bash', ['-c', body, 'test', ...args]);
  }

  final valid = <String, Object?>{
    'number': 42,
    'title': 'chore(release): versie 0.7.7',
    'base': {'ref': base},
    'head': {'sha': head, 'ref': 'release/v0.7.7'},
    'state': 'open',
    'merged': false,
    'merge_commit_sha': null,
  };

  String selector(Map<String, Object?> pr, {String published = ''}) =>
      '''
set -euo pipefail
RELEASE_BASE='$base'
RELEASE_PR=42
TAG=v0.7.7
NEW_VERSION=0.7.7
BRANCH=release/v0.7.7
die() { printf '%s\\n' "\$1" >&2; exit 42; }
git() { printf '%s' '$published'; }
api() { printf '%s' '${jsonEncode(pr)}'; }
${function('find_release_pr')}
find_release_pr
''';

  test('maintenance status reads the selected PR and rejects a wrong base', () {
    final temp = Directory.systemTemp.createTempSync('release-status-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final output = '${temp.path}/status';
    for (final selectedBase in [base, 'unrelated']) {
      final body =
          '''
set -euo pipefail
RELEASE_PR=42
RELEASE_BASE='$base'
NEW_VERSION=0.7.7
api() { [ "\$2" = /pulls/42 ] || exit 99; printf '%s' '${jsonEncode({
            ...valid,
            'base': {'ref': selectedBase},
          })}'; }
${function('status_probe_pr')}
status_probe_pr '$output'
''';
      expect(run(body).exitCode, 0);
      final result = File(output).readAsStringSync();
      expect(
        result,
        selectedBase == base
            ? '1|42|open|false\n'
            : '?|Forgejo-API onleesbaar\n',
      );
    }
  }, skip: skip);

  test('a channel tag cannot restart the legacy release controller', () {
    for (final annotation in ['Release-Mode: channels', 'Candidate-Run: 123']) {
      final result = run('''
set -euo pipefail
TAG=v0.7.7
die() { exit 42; }
git() { printf '%s\\n' '$annotation'; }
${function('assert_legacy_release_mode')}
assert_legacy_release_mode
''');
      expect(result.exitCode, annotation.contains('channels') ? 42 : 0);
    }
  }, skip: skip);

  test('maintenance selector accepts exact open and merged release PRs', () {
    final open = run(selector(valid));
    expect(open.exitCode, 0, reason: '${open.stderr}');
    expect(open.stdout, '42|open|false|$head|\n');
    final closed = run(
      selector({
        ...valid,
        'state': 'closed',
        'merged': true,
        'merge_commit_sha': merge,
      }),
    );
    expect(closed.exitCode, 0, reason: '${closed.stderr}');
    expect(closed.stdout, '42|closed|true|$head|$merge\n');
  }, skip: skip);

  test(
    'maintenance selector rejects unrelated heads and inconsistent state',
    () {
      for (final change in <Map<String, Object?>>[
        {'number': 43},
        {'title': 'chore(release): versie 0.7.8'},
        {
          'base': {'ref': 'main'},
        },
        {
          'head': {'sha': 'short', 'ref': 'release/v0.7.7'},
        },
        {
          'head': {'sha': head, 'ref': 'unrelated'},
        },
        {'state': 'closed'},
        {'merged': true},
        {'merge_commit_sha': merge},
      ]) {
        final result = run(selector({...valid, ...change}));
        expect(result.exitCode, 42, reason: '$change: ${result.stderr}');
      }
      expect(run(selector(valid, published: 'published')).exitCode, 42);
    },
    skip: skip,
  );

  test('default main explicit selector still rejects an open release PR', () {
    final result = run(
      selector({
        ...valid,
        'base': {'ref': 'main'},
      }).replaceFirst("RELEASE_BASE='$base'", 'RELEASE_BASE=main'),
    );
    expect(result.exitCode, 42);
  }, skip: skip);

  test('implicit selection continues to reject duplicate release PRs', () {
    final result = run('''
set -euo pipefail
RELEASE_BASE=main
RELEASE_PR=''
NEW_VERSION=0.7.7
BRANCH=release/v0.7.7
die() { exit 42; }
api() { printf '%s' '${jsonEncode([
      {
        ...valid,
        'base': {'ref': 'main'},
      },
      {
        ...valid,
        'number': 43,
        'base': {'ref': 'main'},
      },
    ])}'; }
${function('find_release_pr')}
find_release_pr
''');
    expect(result.exitCode, 42);
  }, skip: skip);

  String frozen(String current, {bool fetchFails = false}) =>
      '''
set -euo pipefail
RELEASE_BASE='$base'
BRANCH=release/v0.7.7
TAG=v0.7.7
die() { printf '%s\\n' "\$1" >&2; exit 42; }
log() { :; }
git() {
  case "\$1" in
    fetch) [ "\$3" = '$base' ] || exit 91; ${fetchFails ? 'return 1' : 'return 0'} ;;
    merge-base) [ "\$3" = 'origin/$base' ] || exit 92; echo '$merge' ;;
    rev-parse) [ "\$2" = 'origin/$base' ] || exit 93; echo '$current' ;;
    *) exit 94 ;;
  esac
}
${function('assert_release_base_frozen')}
assert_release_base_frozen
''';

  test('frozen base checks selected branch rather than main', () {
    final result = run(frozen(merge));
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(run(frozen(other)).exitCode, 42);
    expect(run(frozen(merge, fetchFails: true)).exitCode, 42);
  }, skip: skip);

  test('maintenance resume accepts only exact selected base tip', () {
    String target(String current) =>
        '''
set -euo pipefail
RELEASE_BASE='$base'
TAG=v0.7.7
NEW_VERSION=0.7.7
die() { printf '%s\\n' "\$1" >&2; exit 42; }
git() {
  [ "\$1" = ls-remote ] || exit 91
  [ "\$3" = 'refs/heads/$base' ] || exit 92
  printf '%s\\t%s\\n' '$current' 'refs/heads/$base'
}
${function('resume_tag_target')}
resume_tag_target '$merge'
''';
    final result = run(target(merge));
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, '$merge\n');
    expect(run(target(other)).exitCode, 42);
    expect(run(target('')).exitCode, 42);
  }, skip: skip);

  test('fresh freeze creates once, reuses exact refs and rejects drift', () {
    final temp = Directory.systemTemp.createTempSync('release-freeze-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final state = File('${temp.path}/ref');
    final pushes = File('${temp.path}/pushes');

    ProcessResult freeze({
      String? existing,
      String? main,
      bool corruptReadback = false,
    }) {
      state.writeAsStringSync(existing ?? '');
      pushes.writeAsStringSync('');
      return run('''
set -euo pipefail
TAG=v0.7.7
RELEASE_BASE=main
die() { printf '%s\\n' "\$1" >&2; exit 42; }
log() { :; }
api() { exit 95; }
git() {
  case "\$1" in
    ls-remote)
      [ "\$2" = origin ] || exit 91
      case "\$3" in
        refs/heads/main) printf '%s\\t%s\\n' '${main ?? merge}' 'refs/heads/main' ;;
        refs/heads/codex/release-base-v0.7.7)
          if [ -s '${state.path}' ]; then
            printf '%s\\t%s\\n' "\$(cat '${state.path}')" "\$3"
          fi ;;
        *) exit 92 ;;
      esac ;;
    fetch)
      [ "\$2" = origin ] && [ "\$3" = codex/release-base-v0.7.7 ] || exit 97 ;;
    push)
      printf '%s\\n' "\$*" >> '${pushes.path}'
      case " \$* " in
        *" --force-with-lease=refs/heads/codex/release-base-v0.7.7: "*) ;;
        *) exit 93 ;;
      esac
      case " \$* " in
        *" $merge:refs/heads/codex/release-base-v0.7.7 "*) ;;
        *) exit 94 ;;
      esac
      printf '%s' '${corruptReadback ? other : merge}' > '${state.path}' ;;
    *) exit 96 ;;
  esac
}
${function('freeze_release_source')}
freeze_release_source
printf '%s' "\$RELEASE_BASE"
''');
    }

    final created = freeze();
    expect(created.exitCode, 0, reason: '${created.stderr}');
    expect(created.stdout, 'codex/release-base-v0.7.7');
    expect(state.readAsStringSync(), merge);
    expect(pushes.readAsLinesSync(), hasLength(1));
    final reused = freeze(existing: merge);
    expect(reused.exitCode, 0, reason: '${reused.stderr}');
    expect(reused.stdout, 'codex/release-base-v0.7.7');
    expect(pushes.readAsStringSync(), isEmpty);
    expect(freeze(existing: other).exitCode, 42);
    expect(pushes.readAsStringSync(), isEmpty);
    for (final badMain in ['', 'short', '0' * 40]) {
      expect(freeze(main: badMain).exitCode, 42, reason: badMain);
      expect(pushes.readAsStringSync(), isEmpty);
    }
    expect(freeze(corruptReadback: true).exitCode, 42);
  }, skip: skip);

  test('resume discovers only the exact version-bound frozen PR base', () {
    ProcessResult resolve(
      Map<String, Object?> pr, {
      String selected = 'main',
      bool explicit = false,
    }) => run('''
set -euo pipefail
TAG=v0.7.7
NEW_VERSION=0.7.7
RELEASE_BASE='$selected'
RELEASE_BASE_SET=${explicit ? 1 : 0}
die() { exit 42; }
api() { printf '%s' '${jsonEncode(pr)}'; }
${function('resolve_release_base')}
resolve_release_base 42 '$head'
printf '%s' "\$RELEASE_BASE"
''');
    final frozenPr = {
      ...valid,
      'base': {'ref': 'codex/release-base-v0.7.7'},
    };
    final discovered = resolve(frozenPr);
    expect(discovered.exitCode, 0, reason: '${discovered.stderr}');
    expect(discovered.stdout, 'codex/release-base-v0.7.7');
    final mainPr = {
      ...valid,
      'base': {'ref': 'main'},
    };
    expect(resolve(mainPr).stdout, 'main');
    expect(resolve(valid, selected: base).stdout, base);
    for (final change in <Map<String, Object?>>[
      {'number': 43},
      {'title': 'chore(release): versie 0.7.8'},
      {
        'head': {'sha': other},
      },
      {
        'base': {'ref': 'codex/release-base-v0.7.8'},
      },
      {
        'base': {'ref': 'unrelated'},
      },
    ]) {
      expect(resolve({...frozenPr, ...change}).exitCode, 42, reason: '$change');
    }
    expect(resolve(frozenPr, selected: base).exitCode, 42);
    expect(resolve(frozenPr, explicit: true).exitCode, 42);
  }, skip: skip);

  test('CLI defaults to main and validates maintenance-only arguments', () {
    final parser = source.substring(
      source.indexOf('RESUME=0\n'),
      source.indexOf('# --print-version is een hermetische'),
    );
    final body =
        '''
set -euo pipefail
die() { exit 42; }
GATE_TIMEOUT_MIN=720
RELEASE_CI_TIMEOUT_MIN=960
LEVEL=''
RESUME_TAG=''
$parser
printf '%s' "\${RELEASE_BASE:-main}"
''';
    expect(run(body, ['--resume', 'v0.7.7']).stdout, 'main');
    for (final mode in ['--resume', '--status']) {
      final result = run(body, [
        mode,
        'v0.7.7',
        '--release-base',
        base,
        '--release-pr',
        '42',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, base);
    }
    for (final args in [
      ['patch', '--release-base', base, '--release-pr', '42'],
      ['--resume', 'v0.7.7', '--release-base', base],
      ['--resume', 'v0.7.7', '--release-base'],
      [
        '--resume',
        'v0.7.7',
        '--release-base',
        '../unsafe',
        '--release-pr',
        '42',
      ],
      [
        '--resume',
        'v0.7.7',
        '--release-base',
        '--unsafe',
        '--release-pr',
        '42',
      ],
      [
        '--resume',
        'v0.7.7',
        '--release-base',
        base,
        '--release-base',
        base,
        '--release-pr',
        '42',
      ],
      [
        '--resume',
        'v0.7.7',
        '--release-base',
        base,
        '--candidate-sha',
        head,
        '--release-pr',
        '42',
      ],
    ]) {
      expect(run(body, args).exitCode, 42, reason: '$args');
    }
  }, skip: skip);
}
