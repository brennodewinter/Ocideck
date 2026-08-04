@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Bewaakt een stille faalklasse in `.forgejo/workflows/release.yml`:
///
/// `actions/checkout@v4` (en elke andere `actions/*`-JS-actie) draait op Node.
/// De kale `ubuntu:24.04`-container heeft géén Node aan boord — alleen de
/// voorgebakken `ocideck-ci`-image wel. Een job die op zo'n kale ubuntu een
/// Node-actie gebruikt, moet daarom éérst `nodejs` installeren. Vergeet je dat,
/// dan faalt de checkout pas op de runner, niet in review — precies wat de
/// eerste echte Homebrew-cask-run (v0.3.1) brak.
///
/// Deze poort dwingt de regel structureel af: geen losse string-match op één
/// job, maar de invariant over álle jobs.
void main() {
  test('kale-ubuntu jobs met een actions/*-actie installeren nodejs', () {
    final file = File('.forgejo/workflows/release.yml');
    expect(file.existsSync(), isTrue, reason: 'release.yml niet gevonden');

    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    final jobs = doc['jobs'] as YamlMap;

    final overtreders = <String>[];

    for (final entry in jobs.entries) {
      final jobName = entry.key as String;
      final job = entry.value as YamlMap;

      // Alleen kale ubuntu-containers: de voorgebakken ocideck-ci-image en de
      // macOS-runner brengen hun eigen Node mee.
      final image = (job['container'] as YamlMap?)?['image'] as String?;
      if (image == null || !image.startsWith('ubuntu')) continue;

      final steps = job['steps'] as YamlList? ?? const [];
      final gebruiktNodeActie = steps.any((s) {
        final uses = (s as YamlMap)['uses'] as String?;
        return uses != null && uses.startsWith('actions/');
      });
      if (!gebruiktNodeActie) continue;

      final installeertNode = steps.any((s) {
        final run = (s as YamlMap)['run'] as String?;
        return run != null && RegExp(r'\bnodejs\b').hasMatch(run);
      });
      if (!installeertNode) overtreders.add(jobName);
    }

    expect(
      overtreders,
      isEmpty,
      reason:
          'Deze jobs draaien een actions/*-actie op kale ubuntu zonder nodejs '
          'te installeren; de checkout faalt op de runner: $overtreders',
    );
  });
}
