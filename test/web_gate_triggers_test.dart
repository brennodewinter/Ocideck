@TestOn('vm')
@Tags(['registration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const pad = '.forgejo/workflows/web-gate.yml';
  final yaml = loadYaml(File(pad).readAsStringSync()) as YamlMap;

  test('$pad tests browser inputs automatically on PRs and main', () {
    final triggers = yaml['on'] as YamlMap;
    expect(triggers.containsKey('workflow_dispatch'), isTrue);
    for (final event in ['push', 'pull_request']) {
      expect(triggers[event]['branches'], contains('main'));
      expect(
        triggers[event]['paths'],
        containsAll([
          'lib/**',
          'web/**',
          'assets/**',
          'packages/**',
          'pubspec.yaml',
          'pubspec.lock',
          '.tool-versions',
          'Makefile',
          'tool/web-wasm-check/**',
        ]),
      );
    }
  });

  test('the full local gate runs the browser after building the bundle', () {
    final makefile = File('Makefile').readAsStringSync();
    final rule = RegExp(
      r'^check-full-locked: (.+)$',
      multiLine: true,
    ).firstMatch(makefile)!.group(1)!;
    expect(rule.split(' '), containsAll(['check-web', 'check-web-browser']));
    expect(
      makefile,
      contains('node --test tool/web-wasm-check/probe.test.cjs'),
    );
    for (final mode in ['auto', 'fallback', 'single-thread']) {
      expect(makefile, contains('probe.cjs build/web chromium $mode 1'));
    }
    expect(
      rule.indexOf('check-web-browser'),
      greaterThan(rule.indexOf('check-web ')),
    );
  });

  test('$pad draait de canonieke webpoort', () {
    final commandos = [
      for (final job in (yaml['jobs'] as YamlMap).values)
        for (final stap in (job as YamlMap)['steps'] as YamlList? ?? const [])
          ((stap as YamlMap)['run'] as String?) ?? '',
    ];
    expect(commandos.any((c) => c.trim() == 'make check-web'), isTrue);
    expect(commandos.any((c) => c.contains('make check-web-browser')), isTrue);
    final steps = yaml['jobs']['web-gate']['steps'] as YamlList;
    final evidence = steps.cast<YamlMap>().singleWhere(
      (s) => '${s['uses']}'.contains('upload-artifact'),
    );
    expect(evidence['if'], 'always()');
    expect(evidence['with']['path'], 'build/web-browser/');
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
