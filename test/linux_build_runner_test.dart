@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final workflow =
      loadYaml(File('.forgejo/workflows/linux-build.yml').readAsStringSync())
          as YamlMap;
  final job = (workflow['jobs'] as YamlMap)['build-linux'] as YamlMap;
  final steps = (job['steps'] as YamlList).cast<YamlMap>();
  final shellOnly = Platform.isWindows ? 'Forgejo uses a Linux shell' : null;

  test('the standalone builder uses the release image for the SDK pin', () {
    final release =
        loadYaml(File('.forgejo/workflows/release.yml').readAsStringSync())
            as YamlMap;
    final linux = (release['jobs'] as YamlMap)['linux'] as YamlMap;
    final image = (job['container'] as YamlMap)['image'] as String;
    final pin = RegExp(
      r'^flutter (\S+)-stable$',
      multiLine: true,
    ).firstMatch(File('.tool-versions').readAsStringSync())![1]!;
    expect(image, (linux['container'] as YamlMap)['image']);
    expect(
      image,
      matches('flutter-${RegExp.escape(pin)}@sha256:[a-f0-9]{64}\$'),
    );
    expect(job['timeout-minutes'], 240);
  });

  test('a rejected SDK stops before apt, pub or compilation', () {
    final (result, calls) = runBuildSteps(steps, wrongSdk: true);
    expect(result.exitCode, isNot(0));
    expect(calls, ['make check-toolchain']);
  }, skip: shellOnly);

  test('the real workflow enforces the lock and bounds Flutter Ninja', () {
    final (result, calls) = runBuildSteps(steps, wrongSdk: false);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(calls.first, 'make check-toolchain');
    expect(calls, contains('flutter pub get --enforce-lockfile'));
    expect(calls, contains('make build-linux'));
    expect(calls, contains('ninja -j2 -C build install'));
    expect(calls.where((line) => line.startsWith('ninja ')), hasLength(1));
    expect(calls.join('\n'), isNot(contains('-j99')));
  }, skip: shellOnly);
}

/// Execute the actual pre-package workflow shells with disposable tool stubs.
/// No daemon, SDK download, package manager or compiler is contacted.
(ProcessResult, List<String>) runBuildSteps(
  List<YamlMap> steps, {
  required bool wrongSdk,
}) {
  final dir = Directory.systemTemp.createTempSync('linux-build-runner-');
  try {
    Directory('${dir.path}/bin').createSync();
    Directory('${dir.path}/scripts').createSync();
    File(
      'scripts/run_release_linux_build.sh',
    ).copySync('${dir.path}/scripts/run_release_linux_build.sh');
    File(
      '${dir.path}/pubspec.lock',
    ).writeAsStringSync('  dartcv4:\n    version: "2.0.1"\n');
    final stubs = <String, String>{
      'git': '#!/bin/sh\nexit 0\n',
      'apt-get': '#!/bin/sh\necho "apt-get \$*" >> "\$CALLS"\n',
      'flutter': '#!/bin/sh\necho "flutter \$*" >> "\$CALLS"\n',
      'ninja': '#!/bin/sh\necho "ninja \$*" >> "\$CALLS"\n',
      'make': r'''#!/bin/sh
echo "make $*" >> "$CALLS"
if [ "$1" = check-toolchain ]; then exit "$SDK_RESULT"; fi
[ "$1" = build-linux ] || exit 91
exec ninja -C build install -j99
''',
    };
    for (final entry in stubs.entries) {
      final file = File('${dir.path}/bin/${entry.key}')
        ..writeAsStringSync(entry.value);
      Process.runSync('chmod', ['700', file.path]);
    }
    // Preserve the tracked non-executable mode: the workflow needs Bash.
    expect(
      File('${dir.path}/scripts/run_release_linux_build.sh').statSync().mode &
          0x49,
      0,
    );
    final calls = File('${dir.path}/calls');
    final environment = <String, String>{
      'PATH': '${dir.path}/bin:${Platform.environment['PATH']}',
      'HOME': dir.path,
      'XDG_CACHE_HOME': '${dir.path}/.cache',
      'GITHUB_WORKSPACE': dir.path,
      'GITHUB_OUTPUT': '${dir.path}/outputs',
      'CALLS': calls.path,
      'SDK_RESULT': wrongSdk ? '23' : '0',
    };
    var result = ProcessResult(0, 0, '', '');
    for (final step in steps) {
      final run = step['run'] as String?;
      if (run != null) {
        result = Process.runSync(
          'bash',
          ['-e', '-o', 'pipefail', '-c', run],
          workingDirectory: dir.path,
          environment: environment,
        );
        if (result.exitCode != 0) break;
      }
      if (step['name'] == 'Linux-release bouwen') break;
    }
    return (result, calls.existsSync() ? calls.readAsLinesSync() : []);
  } finally {
    dir.deleteSync(recursive: true);
  }
}
