import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const lokaleDoublures = [
    '.forgejo/workflows/static-gate.yml',
    '.forgejo/workflows/scans.yml',
    '.forgejo/workflows/web-gate.yml',
  ];

  for (final pad in lokaleDoublures) {
    test('$pad draait alleen bewust op afroep', () {
      final yaml = loadYaml(File(pad).readAsStringSync()) as YamlMap;
      final trekkers = yaml['on'] as YamlMap;

      expect(trekkers.keys, equals(['workflow_dispatch']));
    });
  }
}
