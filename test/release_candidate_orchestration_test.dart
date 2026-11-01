@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('scripts/release_auto.sh').readAsStringSync();
  final definitions = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (!RegExp(r'^\w+\(\)\s*\{').hasMatch(lines[i])) continue;
    for (; i < lines.length; i++) {
      definitions.add(lines[i]);
      if (lines[i] == '}') break;
    }
  }
  const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const changed = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  for (final scenario in [
    'main-advances',
    'moved-ref',
    'ref-moves-after-build',
    'wrong-windows-sha',
    'suite-failure',
    'candidate-failure',
    'consumer-failure',
    'wrong-candidate-sha',
    'wrong-candidate-ref',
    'archive-mismatch',
  ]) {
    test(
      'pretag orchestration: $scenario',
      () {
        final dir = Directory.systemTemp.createTempSync(
          'candidate-orchestration-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final dist = Directory('${dir.path}/dist')..createSync();
        final payload = File('${dist.path}/payload.bin')
          ..writeAsStringSync('tested');
        final digest =
            (Process.runSync('shasum', ['-a', '256', payload.path]).stdout
                    as String)
                .split(' ')
                .first;
        File(
          '${dist.path}/SHA256SUMS',
        ).writeAsStringSync('$digest  payload.bin\n');
        if (scenario == 'archive-mismatch')
          payload.writeAsStringSync('changed after test');
        File('${dir.path}/candidate-manifest.json').writeAsStringSync(
          jsonEncode({
            'commit': sha,
            'version': 'v9.9.9',
            'windows_run_id': 77,
          }),
        );
        const bundle = 'ocideck-release-candidate-v9.9.9.tar.gz';
        expect(
          Process.runSync('tar', [
            '-czf',
            bundle,
            'candidate-manifest.json',
            'dist/SHA256SUMS',
            'dist/payload.bin',
          ], workingDirectory: dir.path).exitCode,
          0,
        );
        expect(
          Process.runSync('zip', [
            '-q',
            'artifact.zip',
            bundle,
          ], workingDirectory: dir.path).exitCode,
          0,
        );
        final harness = File('${dir.path}/harness.sh')
          ..writeAsStringSync('''
set -euo pipefail
${definitions.join('\n')}
TAG=v9.9.9
NEW_VERSION=9.9.9
TAG_PUSHED=0
TAG_UNCERTAIN=0
STEP=test
RELEASE_CI_TIMEOUT_MIN=1
TOKEN=fake
SCENARIO=$scenario
FIXTURE='${dir.path}'
SHA=$sha
CHANGED=$changed
REF=codex/release-candidate-v9.9.9-$sha
die() { printf '%s\\n' "\$*" >&2; exit 42; }
log() { :; }
section() { :; }
sleep() { :; }
assert_release_ci_secrets() { :; }
assert_tag_commit() { [ "\$2" = "\$3" ] || die wrong-tag; }
remote_tag_commit() {
  if [ -f "\$FIXTURE/tag-pushed" ]; then printf '%s\\n' "\$SHA"; else return 1; fi
}
ensure_mirror_tag() { :; }
ensure_candidate_publication() { :; }
expected_release_assets() { printf 'payload.bin\\n'; }
verify_release_manifest() { [ "\$(wc -l < "\$1" | tr -d ' ')" = 1 ]; }
git() {
  printf '%s\\n' "\$*" >> "\$FIXTURE/git.log"
  case "\$1 \$2" in
    'remote get-url') printf 'git@github.com:owner/repo.git\\n' ;;
    'fetch --quiet'|'cat-file -e'|'tag -d') return 0 ;;
    'show '*) printf 'version: 9.9.9\\n' ;;
    'ls-remote '*)
      if [ "\$3" = refs/heads/main ]; then
        if [ -f "\$FIXTURE/main-advanced" ]; then printf '%s refs/heads/main\\n' "\$CHANGED"; else printf '%s refs/heads/main\\n' "\$SHA"; fi
      elif [ "\$SCENARIO" = moved-ref ] || { [ "\$SCENARIO" = ref-moves-after-build ] && [ -f "\$FIXTURE/candidate-checked" ]; }; then printf '%s refs/heads/%s\\n' "\$CHANGED" "\$REF"
      else printf '%s refs/heads/%s\\n' "\$SHA" "\$REF"; fi ;;
    'tag -a') printf '%s\\n' "\$*" > "\$FIXTURE/tag-created" ;;
    'rev-list -n') printf '%s\\n' "\$SHA" ;;
    'push --quiet') touch "\$FIXTURE/tag-pushed" ;;
    *) die "unexpected git: \$*" ;;
  esac
}
gh() {
  touch "\$FIXTURE/main-advanced"
  case "\$1 \$2" in
    'run list') printf '[{"databaseId":77,"headSha":"%s","status":"completed","conclusion":"success"}]\\n' "\$SHA" ;;
    'run view')
      [ -f \"\$FIXTURE/candidate-checked\" ] || die windows-wait-before-candidate
      local actual="\$SHA" status=success
      [ "\$SCENARIO" != wrong-windows-sha ] || actual="\$CHANGED"
      [ "\$SCENARIO" != suite-failure ] || status=failure
      printf '{"headSha":"%s","status":"completed","conclusion":"%s"}\\n' "\$actual" "\$status" ;;
    *) die "unexpected gh: \$*" ;;
  esac
}
api() {
  case "\$2" in
    /actions/runs\\?*) printf '{"workflow_runs":[{"id":123,"workflow_id":"release.yml","commit_sha":"%s","prettyref":"%s","event":"workflow_dispatch"}]}\\n' "\$SHA" "\$REF" ;;
    /actions/runs/123)
      touch \"\$FIXTURE/candidate-checked\"
      local actual="\$SHA" status=success runref="\$REF"
      [ "\$SCENARIO" != wrong-candidate-ref ] || runref=main
      case "\$SCENARIO" in candidate-failure|consumer-failure) status=failure ;; wrong-candidate-sha) actual="\$CHANGED" ;; esac
      printf '{"workflow_id":"release.yml","commit_sha":"%s","prettyref":"%s","event":"workflow_dispatch","status":"%s"}\\n' "\$actual" "\$runref" "\$status" ;;
    /actions/runs/123/artifacts\\?*) printf '[{"name":"ocideck-release-candidate","expired":false,"archive_download_url":"fixture"}]\\n' ;;
    /actions/workflows/release.yml/dispatches) printf '{"id":123}\\n' ;;
    *) die "unexpected api: \$*" ;;
  esac
}
curl() {
  while [ "\$#" -gt 0 ]; do
    if [ "\$1" = -o ]; then cp "\$FIXTURE/artifact.zip" "\$2"; return; fi
    shift
  done
  die missing-download-path
}
tag_and_push "\$SHA"
[ "\$(git ls-remote origin refs/heads/main | cut -d ' ' -f1)" = "\$CHANGED" ]
''');
        final result = Process.runSync('bash', [harness.path]);
        final output = '${result.stdout}\n${result.stderr}';
        final tagged = File('${dir.path}/tag-pushed').existsSync();
        if (scenario == 'main-advances') {
          expect(result.exitCode, 0, reason: output);
          expect(tagged, isTrue);
          expect(
            File('${dir.path}/tag-created').readAsStringSync(),
            endsWith('$sha\n'),
          );
        } else {
          expect(result.exitCode, 42, reason: output);
          expect(tagged, isFalse, reason: output);
          expect(
            File('${dir.path}/tag-created').existsSync(),
            isFalse,
            reason: output,
          );
        }
      },
      skip: Platform.isWindows
          ? 'release orchestrator runs on macOS/Linux'
          : null,
    );
  }
}
