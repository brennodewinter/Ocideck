@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Bewaakt de dartcv4-cache-key-invariant (#1748) over alle drie de workflows
/// die de OpenCV-build cachen: `static-gate.yml`, `linux-gate.yml` en
/// `release.yml`.
///
/// De key mag alleen afhangen van de dartcv4-versie
/// (`steps.dartcv.outputs.versie`), niet van `hashFiles('pubspec.lock')`.
/// Hing hij aan de hele `pubspec.lock`, dan invalidéerde élke dep-bump de
/// cache en bouwde de hook OpenCV vanaf nul (~1 GB) — de duurste stap van
/// static-gate. Een `restore-keys`-fallback mag er niet staan, want die
/// herstelt een stale CMake-cache van een vorige dartcv4-versie (de fout die
/// `13c8a40ce` verhivelde).
void main() {
  final workflows = [
    '.forgejo/workflows/static-gate.yml',
    '.forgejo/workflows/linux-gate.yml',
    '.forgejo/workflows/release.yml',
  ];

  for (final path in workflows) {
    test(
      '$path: dartcv4-cache-key op versie alleen, geen hashFiles of restore-keys',
      () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path niet gevonden');

        final doc = loadYaml(file.readAsStringSync()) as YamlMap;
        final jobs = doc['jobs'] as YamlMap;

        for (final entry in jobs.entries) {
          final jobName = entry.key as String;
          final steps =
              (entry.value as YamlMap)['steps'] as YamlList? ?? const [];

          for (final step in steps) {
            final s = step as YamlMap;
            if (s['uses'] != 'actions/cache@v4') continue;

            final with_ = s['with'] as YamlMap?;
            final key = with_?['key'] as String?;
            if (key == null || !key.startsWith('dartcv-linux-')) continue;

            // De key moet de dartcv4-versie-stap gebruiken, niet hashFiles.
            expect(
              key,
              contains('steps.dartcv.outputs.versie'),
              reason:
                  '$path/$jobName: dartcv4-cache-key gebruikt niet de '
                  'versie-stap — zie #1748. Key: $key',
            );
            expect(
              key,
              isNot(contains('hashFiles')),
              reason:
                  '$path/$jobName: dartcv4-cache-key hangt aan hashFiles '
                  '(hele pubspec.lock) in plaats van de dartcv4-versie — zie #1748.',
            );

            // Geen restore-keys: die herstelt een stale CMake-cache van een
            // vorige dartcv4-versie.
            expect(
              with_?.containsKey('restore-keys'),
              isFalse,
              reason:
                  '$path/$jobName: dartcv4-cache-stap heeft restore-keys — '
                  'dat herstelt een stale CMake-cache bij een dartcv4-bump. '
                  'Zie 13c8a40ce en #1748.',
            );
          }
        }
      },
    );
  }
}
