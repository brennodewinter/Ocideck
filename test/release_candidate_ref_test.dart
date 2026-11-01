import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const otherSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const ref = 'codex/release-candidate-v0.7.6-$sha';
  final skip = Platform.isWindows ? 'Executes the Unix release shell' : null;

  String validationBlock(String path, String step, String nextStep) {
    final source = File(path).readAsStringSync();
    final section = source.split('- name: $step\n')[1].split(nextStep)[0];
    return section
        .split('run: |\n')[1]
        .split('\n')
        .map(
          (line) => line.startsWith('          ') ? line.substring(10) : line,
        )
        .join('\n')
        .replaceAll(r'${{ inputs.mode }}', 'candidate');
  }

  test('tagged publication accepts only the attested successful candidate', () {
    final source = File('.forgejo/workflows/release.yml').readAsStringSync();
    final publication = source.split(
      r'"$API/actions/runs/$RID" > /tmp/candidate-run.json',
    )[1];
    final filter = publication.split("'")[1];
    // The API URL above uses RID extracted from the already validated tag.
    for (final candidateRef in [ref, 'main']) {
      final result = Process.runSync('jq', [
        '-ne',
        '--arg',
        'sha',
        sha,
        '--arg',
        'tag',
        'v0.7.6',
        '{workflow_id:"release.yml",commit_sha:\$sha,status:"success",prettyref:"$candidateRef"} | $filter',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }
    for (final invalid in [
      '{workflow_id:"release.yml",commit_sha:"$otherSha",status:"success",prettyref:"main"}',
      '{workflow_id:"release.yml",commit_sha:\$sha,status:"failure",prettyref:"main"}',
      '{workflow_id:"release.yml",commit_sha:\$sha,status:"success",prettyref:"other"}',
    ]) {
      final result = Process.runSync('jq', [
        '-ne',
        '--arg',
        'sha',
        sha,
        '--arg',
        'tag',
        'v0.7.6',
        '$invalid | $filter',
      ]);
      expect(result.exitCode, isNot(0));
    }
  }, skip: skip);

  for (final workflow in [
    (
      path: '.forgejo/workflows/release.yml',
      step: 'Release-invoer valideren',
      next: '      - name: Afhankelijkheden ophalen',
    ),
    (
      path: '.github/workflows/release.yml',
      step: 'Kandidateninvoer valideren',
      next: '      - name: Set up Flutter',
    ),
  ]) {
    group(workflow.path, () {
      ProcessResult validate(Map<String, String> overrides) {
        final dir = Directory.systemTemp.createTempSync('candidate-ref-');
        addTearDown(() => dir.deleteSync(recursive: true));
        File(
          '${dir.path}/pubspec.yaml',
        ).writeAsStringSync('version: 0.7.6+1\n');
        final script = File('${dir.path}/validate.sh')
          ..writeAsStringSync('''
set -eu
git() {
  test "\$1 \$2" = 'rev-parse HEAD'
  printf '%s\\n' "\$CHECKOUT_SHA"
}
${validationBlock(workflow.path, workflow.step, workflow.next)}
''');
        return Process.runSync(
          'bash',
          [script.path],
          workingDirectory: dir.path,
          environment: {
            'RELEASE_TAG': 'v0.7.6',
            'RELEASE_SHA': sha,
            'GITHUB_REF_TYPE': 'branch',
            'GITHUB_REF_NAME': ref,
            'GITHUB_SHA': sha,
            'CHECKOUT_SHA': sha,
            ...overrides,
          },
        );
      }

      test('accepts the exact candidate branch and commit', () {
        final result = validate({});
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }, skip: skip);

      for (final wrong in {
        'moving main': {'GITHUB_REF_NAME': 'main'},
        'another candidate branch': {'GITHUB_REF_NAME': '$ref-other'},
        'tag ref': {'GITHUB_REF_TYPE': 'tag'},
        'moved event commit': {'GITHUB_SHA': otherSha},
        'wrong checkout': {'CHECKOUT_SHA': otherSha},
        'abbreviated commit': {
          'RELEASE_SHA': 'aaaaaaaa',
          'GITHUB_REF_NAME': 'codex/release-candidate-v0.7.6-aaaaaaaa',
          'GITHUB_SHA': 'aaaaaaaa',
          'CHECKOUT_SHA': 'aaaaaaaa',
        },
      }.entries) {
        test('rejects ${wrong.key}', () {
          expect(validate(wrong.value).exitCode, isNot(0));
        }, skip: skip);
      }
    });
  }
}
