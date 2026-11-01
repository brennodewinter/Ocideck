import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('scripts/release_auto.sh').readAsStringSync();
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  test('release watchers retain generous build and runner queue margins', () {
    final gate = int.parse(
      RegExp(r'GATE_TIMEOUT_MIN:-([0-9]+)').firstMatch(source)!.group(1)!,
    );
    final candidate = int.parse(
      RegExp(r'RELEASE_CI_TIMEOUT_MIN:-([0-9]+)').firstMatch(source)!.group(1)!,
    );
    expect(gate, greaterThanOrEqualTo(720));
    expect(candidate, greaterThanOrEqualTo(gate + 240));
    expect(source, contains('start + 21600'));
  });

  String function(String name) {
    final lines = source.split('\n');
    final start = lines.indexWhere((line) => line.startsWith('$name() {'));
    expect(start, greaterThanOrEqualTo(0));
    final end = lines.indexWhere((line) => line == '}', start + 1);
    expect(end, greaterThan(start));
    return lines.sublist(start, end + 1).join('\n');
  }

  ProcessResult run(String body, List<String> names) {
    final dir = Directory.systemTemp.createTempSync('release-gates-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/harness.sh');
    file.writeAsStringSync('''
set -euo pipefail
TAG=v9.9.9
NEW_VERSION=9.9.9
${names.map(function).join('\n')}
die() { printf 'STOP: %s\n' "\$1" >&2; exit 42; }
log() { :; }
section() { :; }
sleep() { :; }
$body
''');
    return Process.runSync('bash', [file.path]);
  }

  test('ontbrekend CI-secret stopt vóór de tag zonder waarden te tonen', () {
    final result = run(
      r'''
api() { printf '%s\n' '[{"name":"GH_DISPATCH_TOKEN"}]'; }
assert_release_ci_secrets
''',
      ['assert_release_ci_secrets'],
    );
    expect(result.exitCode, 42);
    expect(result.stderr, contains('RELEASE_TOKEN ontbreekt'));
    expect(result.stdout, isEmpty);
  }, skip: skipOnWindows);

  test('rode Windows-run op exacte mergecommit stopt vóór de tag', () {
    final result = run(
      r'''
git() {
  case "$1 $2" in
    'remote get-url') printf '%s\n' 'git@github.com:owner/repo.git' ;;
    'ls-remote origin'|'ls-remote mirror') printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
  esac
}
gh() {
  case "$1 $2" in
    'run list') printf '%s\n' '[{"databaseId":77,"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"failure"}]' ;;
    'run view') printf '%s\n' '{"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"failure"}' ;;
  esac
}
assert_windows_merge_gate aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
''',
      [
        'candidate_ref',
        'assert_candidate_refs',
        'ensure_candidate_refs',
        'wait_windows_merge_gate',
        'assert_windows_merge_gate',
      ],
    );
    expect(result.exitCode, 42);
    expect(
      result.stderr,
      contains('Windows-suite op merge aaaaaaaaaaaa is failure'),
    );
  }, skip: skipOnWindows);

  test('groene Windows-run op exacte mergecommit laat tagstap door', () {
    final result = run(
      r'''
git() {
  case "$1 $2" in
    'remote get-url') printf '%s\n' 'git@github.com:owner/repo.git' ;;
    'ls-remote origin'|'ls-remote mirror') printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
  esac
}
gh() {
  case "$1 $2" in
    'run list') printf '%s\n' '[{"databaseId":77,"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"success"}]' ;;
    'run view') printf '%s\n' '{"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"success"}' ;;
  esac
}
assert_windows_merge_gate aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf 'READY\n'
''',
      [
        'candidate_ref',
        'assert_candidate_refs',
        'ensure_candidate_refs',
        'wait_windows_merge_gate',
        'assert_windows_merge_gate',
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('READY'));
  }, skip: skipOnWindows);

  test('rode Windows-native bouw stopt vóór de tag na groene suite', () {
    final result = run(
      r'''
git() {
  case "$1 $2" in
    'remote get-url') printf '%s\n' 'git@github.com:owner/repo.git' ;;
    'ls-remote origin'|'ls-remote mirror') printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
  esac
}
gh() {
  case "$1 $2" in
    'run list')
      case "$*" in
        *windows-native-check.yml*) printf '%s\n' '[{"databaseId":78,"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"failure"}]' ;;
        *) printf '%s\n' '[{"databaseId":77,"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"success"}]' ;;
      esac ;;
    'run view')
      case "$3" in
        78) printf '%s\n' '{"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"failure"}' ;;
        *) printf '%s\n' '{"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"completed","conclusion":"success"}' ;;
      esac ;;
  esac
}
assert_windows_merge_gate aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
''',
      [
        'candidate_ref',
        'assert_candidate_refs',
        'ensure_candidate_refs',
        'wait_windows_merge_gate',
        'assert_windows_merge_gate',
      ],
    );
    expect(result.exitCode, 42);
    expect(
      result.stderr,
      contains('Windows-bouw op merge aaaaaaaaaaaa is failure'),
    );
  }, skip: skipOnWindows);

  test('mislukte volledige kandidaatbouw verbruikt geen tag', () {
    final result = run(
      r'''
RELEASE_CI_TIMEOUT_MIN=1
git() { printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; }
api() {
  case "$2" in
    '/actions/runs?limit=100&page=1&workflow_id=release.yml&head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
      printf '%s\n' '{"workflow_runs":[{"id":123,"workflow_id":"release.yml","commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","prettyref":"codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":""}]}' ;;
    '/actions/runs/123')
      printf '%s\n' '{"workflow_id":"release.yml","commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","prettyref":"codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"","status":"failure"}' ;;
  esac
}
release_candidate_run aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 123
''',
      ['candidate_ref', 'assert_candidate_refs', 'release_candidate_run'],
    );
    expect(result.exitCode, 42);
    expect(result.stderr, contains('kandidaatbouw 123 is failure'));
  }, skip: skipOnWindows);

  test('een mislukte kandidaat krijgt bij hervatten een nieuwe poging', () {
    final result = run(
      r'''
RELEASE_CI_TIMEOUT_MIN=1
git() { printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; }
api() {
  case "$1 $2" in
    'GET /actions/runs?limit=100&page=1&workflow_id=release.yml&head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
      printf '%s\n' '{"workflow_runs":[{"id":123,"workflow_id":"release.yml","commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","prettyref":"codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch"}]}' ;;
    'GET /actions/runs/123') printf '%s\n' '{"status":"failure"}' ;;
    'POST /actions/workflows/release.yml/dispatches') printf '%s\n' '{"id":124}' ;;
    'GET /actions/runs/124')
      printf '%s\n' '{"workflow_id":"release.yml","commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","prettyref":"codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","status":"failure"}' ;;
  esac
}
release_candidate_run aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
''',
      ['candidate_ref', 'assert_candidate_refs', 'release_candidate_run'],
    );
    expect(result.exitCode, 42);
    expect(result.stderr, contains('kandidaatbouw 124 is failure'));
  }, skip: skipOnWindows);

  test('groene kandidaatrun zonder downloadbare bundel verbruikt geen tag', () {
    final result = run(
      r'''
RELEASE_CI_TIMEOUT_MIN=1
git() { printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; }
api() {
  case "$2" in
    '/actions/runs?limit=100&page=1&workflow_id=release.yml&head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
      printf '%s\n' '{"workflow_runs":[{"id":123,"workflow_id":"release.yml","commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","prettyref":"codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch"}]}' ;;
    '/actions/runs/123')
      printf '%s\n' '{"workflow_id":"release.yml","commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","prettyref":"codex/release-candidate-v9.9.9-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","status":"success"}' ;;
    '/actions/runs/123/artifacts?per_page=100')
      printf '%s\n' '[]' ;;
  esac
}
release_candidate_run aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
''',
      ['candidate_ref', 'assert_candidate_refs', 'release_candidate_run'],
    );
    expect(result.exitCode, 42);
    expect(result.stderr, contains('geen uniek, geldig kandidaatarchief'));
  }, skip: skipOnWindows);

  test('de tagpush volgt pas na de volledige kandidaatcontrole', () {
    final push = function('tag_and_push');
    expect(push, contains(r'release_candidate_run "$mergesha"'));
    expect(push, contains(r'Candidate-Run: $CANDIDATE_RUN_ID'));
    expect(
      push.indexOf(r'release_candidate_run "$mergesha"'),
      lessThan(push.indexOf(r'git push --quiet origin "$TAG"')),
    );
    expect(push, contains(r'ensure_candidate_publication "$mergesha"'));
    expect(
      function('follow_ci'),
      contains('if ! tag_has_candidate; then wait_tag_gates; fi'),
    );
  });

  test('hervatten tagt de nieuwe main na test- en catalogusreparatie', () {
    final result = run(
      r'''
git() {
  case "$*" in
    'ls-remote origin refs/heads/main') printf '%s\n' 'new refs/heads/main' ;;
    'merge-base --is-ancestor old new') return 0 ;;
    'diff --name-only old new') printf '%s\n' 'test/form_maker_check_dialog_test.dart' 'scripts/release_auto.sh' '.github/workflows/windows-test-check.yml' 'assets/cwe/cwe_full.json' 'lib/services/reference_standards.dart' 'CONTRIBUTORS.md' ;;
    'show new:pubspec.yaml') printf '%s\n' 'version: 9.9.9+45' ;;
    *) return 1 ;;
  esac
}
resume_tag_target old
''',
      ['resume_tag_target'],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout.trim(), 'new');
  }, skip: skipOnWindows);

  for (final scenario in [
    'current-main',
    'frozen-main-advanced',
    'only-origin-frozen',
    'moved-frozen-ref',
    'already-tagged',
    'changed-pubspec',
    'unmerged-pr',
    'wrong-pr-head',
    'changed-merge-tree',
    'product-change',
    'catalog-change',
    'unrelated-history',
  ]) {
    test('explicit repair candidate selection: $scenario', () {
      final result = run(
        'SCENARIO=$scenario\n'
        r'''
CANDIDATE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
RELEASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
HEAD=cccccccccccccccccccccccccccccccccccccccc
git() {
  case "$1 $2" in
    'ls-remote '*)
      case "$3" in
        refs/tags/*) [ "$SCENARIO" != already-tagged ] || printf 'tag-object %s\n' "$3" ;;
        refs/heads/main)
          if [ "$SCENARIO" = current-main ]; then printf '%s %s\n' "$CANDIDATE" "$3"
          else printf '%s %s\n' "$RELEASE" "$3"; fi ;;
        refs/heads/codex/*)
          case "$SCENARIO" in
            frozen-main-advanced) printf '%s %s\n' "$CANDIDATE" "$3" ;;
            only-origin-frozen) [ "$2" != origin ] || printf '%s %s\n' "$CANDIDATE" "$3" ;;
            moved-frozen-ref) printf '%s %s\n' "$RELEASE" "$3" ;;
          esac ;;
      esac
      return 0 ;;
    'merge-base --is-ancestor') [ "$SCENARIO" != unrelated-history ] ;;
    'show -s') printf '%s %s\n' "$RELEASE" "$HEAD" ;;
    'rev-parse '*)
      case "$2" in
        *:pubspec.yaml)
          if [ "$SCENARIO" = changed-pubspec ] && [ "$2" = "$CANDIDATE:pubspec.yaml" ]; then printf 'different-spec\n'
          else printf 'same-spec\n'; fi ;;
        *'^{tree}')
          if [ "$SCENARIO" = changed-merge-tree ] && [ "$2" = "$CANDIDATE^{tree}" ]; then printf 'different-tree\n'
          else printf 'same-tree\n'; fi ;;
      esac ;;
    'diff --name-only')
      if [ "$SCENARIO" = product-change ]; then printf 'lib/main.dart\n'
      elif [ "$SCENARIO" = catalog-change ]; then printf 'lib/services/cwe_catalog.dart\n'
      else printf '.forgejo/workflows/linux-build.yml\n.forgejo/workflows/release.yml\n.github/workflows/release.yml\ntest/linux_packaging_test.dart\ndocs/BUILD.md\n'; fi ;;
    *) printf 'unexpected git %s\n' "$*" >&2; return 9 ;;
  esac
}
api() {
  local merged=true head="$HEAD"
  [ "$SCENARIO" != unmerged-pr ] || merged=false
  [ "$SCENARIO" != wrong-pr-head ] || head="$RELEASE"
  printf '{"number":42,"merged":%s,"merge_commit_sha":"%s","head":{"sha":"%s"}}\n' "$merged" "$CANDIDATE" "$head"
}
select_repair_candidate "$RELEASE" "$CANDIDATE"
''',
        [
          'candidate_ref',
          'assert_release_merge_tree',
          'select_repair_candidate',
        ],
      );
      if (scenario == 'current-main' || scenario == 'frozen-main-advanced') {
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          result.stdout.toString().trim(),
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
      } else {
        expect(
          result.exitCode,
          42,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, isEmpty);
        const rejectedFor = {
          'only-origin-frozen': 'exact origin/main',
          'moved-frozen-ref': 'verschoof',
          'already-tagged': 'publieke tag',
          'changed-pubspec': 'wijzigt pubspec.yaml',
          'unmerged-pr': 'aantoonbaar gemergde',
          'wrong-pr-head': 'aantoonbaar gemergde',
          'changed-merge-tree': 'merge-tree wijkt af',
          'product-change': 'buiten de toegestane',
          'catalog-change': 'buiten de toegestane',
          'unrelated-history': 'geen afstammeling',
        };
        expect(
          result.stderr,
          contains(rejectedFor[scenario]!),
          reason: scenario,
        );
      }
    }, skip: skipOnWindows);
  }

  test('ongetagde release vervangen vereist expliciete patch en lege mirror', () {
    const gitStub = r'''
CUR_VERSION=9.9.9
LEVEL=patch
git() {
  case "$1 $2" in
    'ls-remote origin') return 0 ;;
    'ls-remote mirror') [ "${MIRROR_TAGGED:-0}" -eq 0 ] || printf '%s\n' 'tag refs/tags/v9.9.9' ;;
  esac
}
''';
    final rejected = run(
      '$gitStub\nSUPERSEDE_UNTAGGED=0\nassert_current_version_tag_state',
      ['assert_current_version_tag_state'],
    );
    expect(rejected.exitCode, 42);
    expect(rejected.stderr, contains('tag v9.9.9 ontbreekt'));

    final allowed = run(
      '$gitStub\nSUPERSEDE_UNTAGGED=1\nassert_current_version_tag_state',
      ['assert_current_version_tag_state'],
    );
    expect(allowed.exitCode, 0, reason: allowed.stderr as String);

    final minor = run(
      '$gitStub\nSUPERSEDE_UNTAGGED=1\nLEVEL=minor\nassert_current_version_tag_state',
      ['assert_current_version_tag_state'],
    );
    expect(minor.exitCode, 42);

    final mirrorTagged = run(
      '$gitStub\nSUPERSEDE_UNTAGGED=1\nMIRROR_TAGGED=1\nassert_current_version_tag_state',
      ['assert_current_version_tag_state'],
    );
    expect(mirrorTagged.exitCode, 42);
    expect(mirrorTagged.stderr, contains('staat op de mirror'));
  }, skip: skipOnWindows);

  test('hervatten weigert nieuwe productcode sinds de release-merge', () {
    final result = run(
      r'''
git() {
  case "$*" in
    'ls-remote origin refs/heads/main') printf '%s\n' 'new refs/heads/main' ;;
    'merge-base --is-ancestor old new') return 0 ;;
    'diff --name-only old new') printf '%s\n' 'lib/main.dart' ;;
    *) return 1 ;;
  esac
}
resume_tag_target old
''',
      ['resume_tag_target'],
    );
    expect(result.exitCode, 42);
    expect(result.stderr, contains('automatisch hervatten is niet toegestaan'));
  }, skip: skipOnWindows);

  test('rode losse tagpoort verhindert fase 3', () {
    final result = run(
      r'''
git() {
  case "$1 $2" in
    'remote get-url') printf '%s\n' 'git@github.com:owner/repo.git' ;;
    'rev-list -n') printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
  esac
}
latest_workflow_run() { printf '%s\n' '10|failure'; }
macos_gate_tag_status() { printf '%s\n' 'success|11'; }
api() { printf '%s\n' '{"commit_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'; }
gh() { printf '%s\n' '[{"databaseId":12,"headSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","headBranch":"v9.9.9","status":"completed","conclusion":"success"}]'; }
wait_tag_gates
''',
      ['wait_tag_gates'],
    );
    expect(result.exitCode, 42);
    expect(result.stderr, contains('tagpoort op v9.9.9 is failure'));
  }, skip: skipOnWindows);

  test('oude groene Forgejo-tagpoort op andere commit verhindert fase 3', () {
    final result = run(
      r'''
git() {
  case "$1 $2" in
    'remote get-url') printf '%s\n' 'git@github.com:owner/repo.git' ;;
    'rev-list -n') printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
  esac
}
latest_workflow_run() { printf '%s\n' '10|success'; }
macos_gate_tag_status() { printf '%s\n' 'success|11'; }
api() { printf '%s\n' '{"commit_sha":"oldsha"}'; }
wait_tag_gates
''',
      ['wait_tag_gates'],
    );
    expect(result.exitCode, 42);
    expect(
      result.stderr,
      contains('in plaats van aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
    );
  }, skip: skipOnWindows);

  test('status meldt oude groene tagpoort op andere commit niet als groen', () {
    final result = run(
      r'''
latest_workflow_run() { printf '%s\n' '10|success'; }
git() { printf '%s\n' 'git@github.com:owner/repo.git'; }
remote_tag_commit() { printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; }
api() { printf '%s\n' '{"commit_sha":"oldsha"}'; }
probe="$(mktemp)"
status_probe_tag_gates "$probe"
cat "$probe"
rm "$probe"
''',
      ['status_probe_tag_gates'],
    );
    expect(result.exitCode, 0);
    expect(result.stdout, contains('0|Forgejo ci draait op andere commit'));
  }, skip: skipOnWindows);
}
