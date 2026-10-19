import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('scripts/release_auto.sh').readAsStringSync();
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

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
    'ls-remote origin'|'ls-remote mirror') printf '%s\n' 'abcdef refs/heads/main' ;;
  esac
}
gh() {
  case "$1 $2" in
    'run list') printf '%s\n' '[{"databaseId":77,"headSha":"abcdef","status":"completed","conclusion":"failure"}]' ;;
    'run view') printf '%s\n' '{"headSha":"abcdef","status":"completed","conclusion":"failure"}' ;;
  esac
}
assert_windows_merge_gate abcdef
''',
      ['assert_windows_merge_gate'],
    );
    expect(result.exitCode, 42);
    expect(result.stderr, contains('Windows-suite op merge abcdef is failure'));
  }, skip: skipOnWindows);

  test('groene Windows-run op exacte mergecommit laat tagstap door', () {
    final result = run(
      r'''
git() {
  case "$1 $2" in
    'remote get-url') printf '%s\n' 'git@github.com:owner/repo.git' ;;
    'ls-remote origin'|'ls-remote mirror') printf '%s\n' 'abcdef refs/heads/main' ;;
  esac
}
gh() {
  case "$1 $2" in
    'run list') printf '%s\n' '[{"databaseId":77,"headSha":"abcdef","status":"completed","conclusion":"success"}]' ;;
    'run view') printf '%s\n' '{"headSha":"abcdef","status":"completed","conclusion":"success"}' ;;
  esac
}
assert_windows_merge_gate abcdef
printf 'READY\n'
''',
      ['assert_windows_merge_gate'],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('READY'));
  }, skip: skipOnWindows);

  test('rode losse tagpoort verhindert fase 3', () {
    final result = run(
      r'''
git() {
  case "$1 $2" in
    'remote get-url') printf '%s\n' 'git@github.com:owner/repo.git' ;;
    'rev-list -n') printf '%s\n' 'abcdef' ;;
  esac
}
latest_workflow_run() { printf '%s\n' '10|failure'; }
macos_gate_tag_status() { printf '%s\n' 'success|11'; }
api() { printf '%s\n' '{"commit_sha":"abcdef"}'; }
gh() { printf '%s\n' '[{"databaseId":12,"headSha":"abcdef","headBranch":"v9.9.9","status":"completed","conclusion":"success"}]'; }
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
    'rev-list -n') printf '%s\n' 'abcdef' ;;
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
    expect(result.stderr, contains('in plaats van abcdef'));
  }, skip: skipOnWindows);

  test('status meldt oude groene tagpoort op andere commit niet als groen', () {
    final result = run(
      r'''
latest_workflow_run() { printf '%s\n' '10|success'; }
git() { printf '%s\n' 'git@github.com:owner/repo.git'; }
remote_tag_commit() { printf '%s\n' 'abcdef'; }
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
