@Tags(['registration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('both Linux sessions always exercise the same built release', () {
    final workflow =
        loadYaml(
              File(
                '.forgejo/workflows/linux-start-smoke.yml',
              ).readAsStringSync(),
            )
            as YamlMap;
    final on = workflow['on'] as YamlMap;
    expect(on['push']['branches'], contains('main'));
    expect(on['pull_request']['branches'], contains('main'));
    final jobs = workflow['jobs'] as YamlMap;
    final build = jobs['linux-start'] as YamlMap;
    final session = jobs['desktop-session'] as YamlMap;
    expect(session.containsKey('if'), isFalse);
    expect(session['needs'], 'linux-start');
    expect(session['strategy']['matrix']['backend'], ['x11', 'wayland']);
    expect(session['strategy']['fail-fast'], isFalse);
    final buildSteps = (build['steps'] as YamlList).cast<YamlMap>();
    final steps = (session['steps'] as YamlList).cast<YamlMap>();
    final uploaded = buildSteps.singleWhere(
      (s) =>
          '${s['uses']}'.contains('upload-artifact') &&
          s['with']['name'] == 'linux-desktop-bundle',
    );
    final downloaded = steps.singleWhere(
      (s) => '${s['uses']}'.contains('download-artifact'),
    );
    expect(downloaded['with']['name'], uploaded['with']['name']);
    final probe = steps.singleWhere(
      (s) => '${s['run']}'.contains('run_linux_window_probe.sh'),
    );
    expect(probe.containsKey('if'), isFalse);
    expect(probe['run'], contains(r"'${{ matrix.backend }}'"));
    expect(probe['run'], contains('desktop-bundle/bundle/ocideck'));
    final evidence = steps.singleWhere(
      (s) => '${s['uses']}'.contains('upload-artifact'),
    );
    expect(evidence['if'], 'always()');
    expect(evidence['with']['name'], contains(r'${{ matrix.backend }}'));
    expect(evidence['with']['path'], contains(r'${{ matrix.backend }}'));
  });
}
