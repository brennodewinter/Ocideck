@Tags(['registration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

YamlMap workflow(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;
String steps(YamlMap job) => (job['steps'] as YamlList)
    .whereType<YamlMap>()
    .map((step) => step['run'] ?? '')
    .join('\n');

void main() {
  test(
    'macOS drives the real app on main and manual dispatch, with failure evidence',
    () {
      final yaml = workflow('.forgejo/workflows/macos-gate.yml');
      final on = yaml['on'] as YamlMap;
      expect(on.containsKey('workflow_dispatch'), isTrue);
      expect(on['push']['branches'], contains('main'));
      final native = yaml['jobs']['desktop-lifecycle'] as YamlMap;
      expect(native['runs-on'], 'macos');
      expect(native['timeout-minutes'], lessThanOrEqualTo(30));
      expect(
        steps(native),
        contains('make test-desktop-roundtrip DEVICE=macos'),
      );
      final artifact = (native['steps'] as YamlList)
          .whereType<YamlMap>()
          .singleWhere((step) => '${step['uses']}'.contains('upload-artifact'));
      expect(artifact['if'], contains('always()'));
      expect(artifact['with']['path'], 'build/desktop-roundtrip/');
    },
  );

  test('Linux and Windows execute the same lifecycle harness', () {
    final linux = workflow('.forgejo/workflows/linux-gate.yml');
    final linuxSteps = steps(linux['jobs']['gate-linux'] as YamlMap);
    expect(
      linuxSteps,
      contains('xvfb-run -a make test-desktop-roundtrip DEVICE=linux'),
    );
    final windows = workflow('.github/workflows/windows-test-check.yml');
    final winSteps = (windows['jobs']['test']['steps'] as YamlList)
        .whereType<YamlMap>();
    final native = winSteps.singleWhere(
      (step) => '${step['run']}'.contains(
        'tool/run_desktop_smoke.dart windows --roundtrip',
      ),
    );
    expect(native['if'], contains('matrix.shard == 0'));
    expect(native['if'], contains('!inputs.navigation_only'));
    expect(native['if'], contains('!inputs.video_only'));
    final makefile = File('Makefile').readAsStringSync();
    expect(
      makefile,
      contains(
        r'scripts/gate_lock.sh dart run tool/run_desktop_smoke.dart $(DEVICE)',
      ),
    );
  });

  test(
    'the native probe keeps real exit dispatch and separates fixture state',
    () {
      final probe = File(
        'integration_test/desktop_lifecycle_test.dart',
      ).readAsStringSync();
      expect(probe, contains('configureNativeWindow()'));
      expect(probe, contains('desktop_smoke_paths.dart'));
      for (final bypass in [
        'debugQuitAppSkipsNative',
        'debugDefaultTargetPlatformOverride',
        'handleRequestAppExit(',
        'setMockMethodCallHandler',
      ]) {
        expect(
          probe,
          isNot(contains(bypass)),
          reason: 'Native lifecycle must not be mocked: $bypass',
        );
      }
      final objc = File('test_driver/macos_quit_probe.m').readAsStringSync();
      expect(objc, contains('performKeyEquivalent:event'));
      expect(objc, contains('NSEventModifierFlagCommand'));
      expect(objc, contains('characters:@"q"'));
      expect(objc, contains('dispatch_get_main_queue()'));
    },
  );
}
