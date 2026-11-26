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
  test('one automatic short PR and nightly full journey per platform', () {
    final forge = workflow('.forgejo/workflows/app-journey.yml');
    final triggers = forge['on'] as YamlMap;
    expect(triggers['pull_request']['branches'], contains('main'));
    expect(triggers['schedule'], isNotEmpty);
    expect(triggers.containsKey('workflow_dispatch'), isTrue);
    for (final platform in ['linux', 'macos']) {
      final job = forge['jobs'][platform] as YamlMap;
      expect(job['runs-on'], platform == 'linux' ? 'docker' : 'macos');
      final commands = steps(job);
      expect(commands, contains('tool/app_journey.py'));
      expect(commands, contains('scripts/gate_lock.sh'));
      expect(commands, contains('full_arg=--full'));
      final run = (job['steps'] as YamlList).whereType<YamlMap>().singleWhere(
        (step) => '${step['run']}'.contains('tool/app_journey.py'),
      );
      expect(run['env']['FULL'], contains("github.event_name == 'schedule'"));
      expect(run['continue-on-error'], isNull);
      final artifact = (job['steps'] as YamlList)
          .whereType<YamlMap>()
          .singleWhere((step) => '${step['uses']}'.contains('upload-artifact'));
      expect(artifact['if'], 'always()');
      expect(artifact['with']['path'], 'build/app-journey/');
    }
    final macosSteps = steps(forge['jobs']['macos'] as YamlMap);
    expect(macosSteps, contains('prepare_macos_app_journey_sdk.sh'));
    expect(macosSteps, contains('flutter-app-journey.*'));
    final cleanup = (forge['jobs']['macos']['steps'] as YamlList)
        .whereType<YamlMap>()
        .singleWhere(
          (step) => '${step['run']}'.contains(
            'Unexpected app-journey SDK cleanup path',
          ),
        );
    expect(cleanup['if'], 'always()');
    final mirror = workflow('.github/workflows/windows-app-journey.yml');
    expect(mirror['on']['push']['branches'], contains('**'));
    expect(mirror['on']['schedule'], isNotEmpty);
    final windows = mirror['jobs']['journey'] as YamlMap;
    expect(windows['runs-on'], 'windows-2022');
    expect(steps(windows), contains('python tool/app_journey.py'));
    expect(steps(windows), contains('full_arg=--full'));
    expect(
      steps(forge['jobs']['windows'] as YamlMap),
      contains('wait_windows_app_journey.py'),
    );
  });

  test(
    'manual baseline comparisons stay separate from the automatic journey',
    () {
      final linux = workflow('.forgejo/workflows/linux-gate.yml');
      expect(
        linux['on']['workflow_dispatch']['inputs'].containsKey('baseline_ref'),
        isTrue,
      );
      expect(
        steps(linux['jobs']['pagination-profile'] as YamlMap),
        contains('baseline'),
      );
      final windows = workflow('.github/workflows/windows-test-check.yml');
      expect(
        windows['on']['workflow_dispatch']['inputs'].containsKey(
          'baseline_ref',
        ),
        isTrue,
      );
      expect(
        steps(windows['jobs']['test'] as YamlMap),
        contains('baseline.json'),
      );
      for (final path in [
        '.forgejo/workflows/macos-gate.yml',
        '.forgejo/workflows/linux-gate.yml',
        '.github/workflows/windows-test-check.yml',
      ]) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('run_desktop_smoke.dart')),
        );
        expect(
          File(path).readAsStringSync(),
          isNot(contains('make test-desktop-roundtrip')),
        );
      }
      expect(
        File('Makefile').readAsStringSync(),
        contains(
          r'scripts/gate_lock.sh dart run tool/run_desktop_smoke.dart $(DEVICE)',
        ),
      );
    },
  );

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
