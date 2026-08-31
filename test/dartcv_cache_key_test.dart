@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Bewaakt de dartcv4-cache-key-invariant (#1748) over élke workflow die de
/// OpenCV-build cacht.
///
/// De lijst wordt **afgeleid**, niet opgeschreven. Hij stond hier eerst met de
/// hand — `static-gate.yml`, `linux-gate.yml`, `release.yml` — en dat is
/// dezelfde faalvorm als die van #1888: een nieuwe workflow met dezelfde cache
/// valt er stil buiten en niets wordt rood. `web-gate.yml` (#1888-staart) was de
/// vierde. Wat de invariant moet dekken is "alles wat deze cache gebruikt", en
/// dat is af te lezen in plaats van te onthouden.
///
/// De key mag alleen afhangen van de dartcv4-versie
/// (`steps.dartcv.outputs.versie`), niet van `hashFiles('pubspec.lock')`.
/// Hing hij aan de hele `pubspec.lock`, dan invalidéerde élke dep-bump de
/// cache en bouwde de hook OpenCV vanaf nul (~1 GB) — de duurste stap van
/// static-gate. Een `restore-keys`-fallback mag er niet staan, want die
/// herstelt een stale CMake-cache van een vorige dartcv4-versie (de fout die
/// `13c8a40ce` verhivelde).
void main() {
  /// Het goedkope tekstaftasten bepaalt het domein; het ontleden doet de
  /// controle. Lopen die twee uiteen, dan heeft de ontleder stil een bestand
  /// laten vallen (een andere vorm, een parseerfout) en zou de invariant
  /// vacuüm slagen — vandaar dat dat hieronder zelf een test is.
  final noemenDeCache = [
    for (final map in ['.forgejo/workflows', '.github/workflows'])
      if (Directory(map).existsSync())
        for (final bestand in Directory(map).listSync().whereType<File>())
          if (bestand.path.endsWith('.yml') || bestand.path.endsWith('.yaml'))
            if (bestand.readAsStringSync().contains('dartcv-linux-'))
              bestand.path.replaceAll(r'\', '/'),
  ]..sort();

  test('er is überhaupt een workflow die de OpenCV-build cacht', () {
    // Zonder deze regel slaagt de hele suite hieronder zodra de afleiding
    // niets meer vindt — de stilste manier waarop een poort verdwijnt.
    expect(
      noemenDeCache,
      isNotEmpty,
      reason:
          'geen enkele workflow cachet de dartcv4-build meer; klopt dat, of '
          'is de afleiding stuk?',
    );
  });

  test('elke workflow met de cachesleutel wordt ook echt ontleed', () {
    for (final path in noemenDeCache) {
      final doc = loadYaml(File(path).readAsStringSync());
      final jobs = doc is YamlMap ? doc['jobs'] : null;
      expect(
        jobs,
        isA<YamlMap>(),
        reason:
            '$path noemt dartcv-linux- maar heeft geen leesbare jobs — de '
            'controle hieronder zou hem stil overslaan',
      );
    }
  });

  for (final path in noemenDeCache) {
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
