@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const pad = '.forgejo/workflows/web-gate.yml';
  final yaml = loadYaml(File(pad).readAsStringSync()) as YamlMap;

  test('$pad blijft bewust handmatig startbaar', () {
    final trekkers = yaml['on'] as YamlMap;
    expect(trekkers.keys, equals(['workflow_dispatch']));
  });

  test('$pad draait de canonieke webpoort', () {
    final commandos = [
      for (final job in (yaml['jobs'] as YamlMap).values)
        for (final stap in (job as YamlMap)['steps'] as YamlList? ?? const [])
          ((stap as YamlMap)['run'] as String?) ?? '',
    ];
    expect(commandos.any((c) => c.trim() == 'make check-web'), isTrue);
  });

  test('$pad gebruikt het gepinde CI-image', () {
    final images = [
      for (final job in (yaml['jobs'] as YamlMap).values)
        ((job as YamlMap)['container'] as YamlMap?)?['image'] as String?,
    ];
    expect(
      images,
      everyElement(
        startsWith('pawprint.vigilis.online/librekat/ocideck-ci:flutter-'),
      ),
    );
  });
}
