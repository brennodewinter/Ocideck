import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // The browser gate is automatic under #3212; web_gate_triggers_test guards it.
  const lokaleDoublures = ['.forgejo/workflows/static-gate.yml'];

  for (final pad in lokaleDoublures) {
    test('$pad draait alleen bewust op afroep', () {
      final yaml = loadYaml(File(pad).readAsStringSync()) as YamlMap;
      final trekkers = yaml['on'] as YamlMap;

      expect(trekkers.keys, equals(['workflow_dispatch']));
    });
  }

  test(
    'PR-geheimenscan draait vertrouwde code uit main en leest git-objecten',
    () {
      final yaml =
          loadYaml(File('.forgejo/workflows/scans.yml').readAsStringSync())
              as YamlMap;
      final triggers = yaml['on'] as YamlMap;
      expect(
        triggers.keys,
        unorderedEquals(['workflow_dispatch', 'pull_request_target']),
      );
      expect((triggers['pull_request_target'] as YamlMap)['branches'], [
        'main',
      ]);

      final steps =
          ((yaml['jobs'] as YamlMap)['scans'] as YamlMap)['steps'] as YamlList;
      final checkout = steps.cast<YamlMap>().singleWhere(
        (step) => step.containsKey('uses'),
      );
      expect(checkout['with'], {
        'fetch-depth': 0,
        'persist-credentials': false,
      });

      final scan = steps.cast<YamlMap>().singleWhere(
        (step) =>
            (step['run'] as String?)?.contains('scripts/scan_pr_secrets.sh') ??
            false,
      );
      expect(
        scan['if'],
        contains("github.event_name == 'pull_request_target'"),
      );
      expect(scan['run'], contains('unset FORGEJO_TOKEN GITHUB_TOKEN'));
      expect(scan['run'], contains(r'refs/pull/$PR_NUMBER/head'));
      expect(
        scan['run'],
        contains(r'test "$(git rev-parse FETCH_HEAD)" = "$PR_HEAD"'),
      );
      for (final step in steps.cast<YamlMap>()) {
        if ((step['run'] as String?)?.startsWith('make ') ?? false) {
          expect(
            step['if'],
            contains("github.event_name == 'workflow_dispatch'"),
          );
        }
      }
    },
  );

  test('de Linux-poort draait de tests niet als root', () {
    final workflow = File(
      '.forgejo/workflows/linux-gate.yml',
    ).readAsStringSync();

    expect(workflow, contains('PUB_CACHE: /home/ubuntu/.pub-cache'));
    expect(workflow, contains('chown -R ubuntu:ubuntu'));
    expect(
      workflow,
      contains('/opt/flutter/packages/flutter_tools/.dart_tool'),
    );
    expect(workflow, contains('runuser --user ubuntu'));
    expect(
      workflow,
      contains(r'key: dartcv-linux-${{ steps.dartcv.outputs.versie }}-uid1000'),
    );
  });
}
