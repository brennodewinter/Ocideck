@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Bewaakt de faalklasse die beide image-publiceer-workflows in hun hele
/// bestaan rood hield — en die pas opviel toen een release erop strandde.
///
/// De jobs draaien ÍN de docker-in-docker-sidecar, in een netwerk dat de runner
/// per workflow-run aanmaakt. De runnerconfig injecteert daar
/// `DOCKER_HOST=tcp://docker-in-docker:2375`, en die injectie **wint van een
/// `env:` in de workflow**. Die naam is een alias op het buitenste
/// compose-netwerk en bestaat niet in de dind, dus elke docker-aanroep die op de
/// omgeving leunt strandt op `lookup docker-in-docker … no such host`.
///
/// De enige constructie die daar niet gevoelig voor is, is de `-H`-vlag: een
/// CLI-vlag wint altijd van de omgeving. Deze poort dwingt dat structureel af —
/// niet als string-match op één regel, maar als invariant over álle
/// docker-aanroepen in beide workflows. Een kale `docker build` die terugsluipt
/// valt hier om, niet pas op de runner.
void main() {
  const workflows = <String>[
    '.forgejo/workflows/ci-image.yml',
    '.forgejo/workflows/ci-image-scans.yml',
  ];

  /// Een docker-aanroep: `docker` als commandowoord (dus niet `docker.io` of
  /// `dockerd`), plus het eerstvolgende woord — dat `-H` moet zijn.
  final aanroep = RegExp(r'(?:^|[\s|;&(])docker\s+(\S+)', multiLine: true);

  /// Elke sleutel die de workflow in een `env:`-blok zet — op workflow-, job- of
  /// stapniveau. De runner injecteert zijn eigen omgeving over al die niveaus
  /// heen, dus een sleutel hier zegt niets over wat de job werkelijk ziet.
  Set<String> envSleutels(File file) {
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    final uit = <String>{};
    void oogst(dynamic env) {
      if (env is YamlMap) uit.addAll(env.keys.map((k) => '$k'));
    }

    oogst(doc['env']);
    for (final entry in (doc['jobs'] as YamlMap).entries) {
      final job = entry.value as YamlMap;
      oogst(job['env']);
      for (final step in (job['steps'] as YamlList? ?? const [])) {
        oogst((step as YamlMap)['env']);
      }
    }
    return uit;
  }

  /// Alle `run:`-scripts in een workflow, met hun jobnaam erbij voor de melding.
  List<({String job, String script})> runScripts(File file) {
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    final jobs = doc['jobs'] as YamlMap;
    final uit = <({String job, String script})>[];
    for (final entry in jobs.entries) {
      final steps = (entry.value as YamlMap)['steps'] as YamlList? ?? const [];
      for (final step in steps) {
        final script = (step as YamlMap)['run'];
        if (script is String) {
          uit.add((job: entry.key as String, script: script));
        }
      }
    }
    return uit;
  }

  for (final pad in workflows) {
    group(pad, () {
      final file = File(pad);

      test('elke docker-aanroep draagt een expliciete -H', () {
        expect(file.existsSync(), isTrue, reason: '$pad niet gevonden');

        final kaal = <String>[];
        for (final (:job, :script) in runScripts(file)) {
          for (final regel in script.split('\n')) {
            // Commentaar in het script noemt `docker …` als uitleg, niet als
            // aanroep; dat is geen overtreding.
            if (regel.trimLeft().startsWith('#')) continue;
            for (final m in aanroep.allMatches(regel)) {
              if (m.group(1) != '-H') {
                kaal.add('$job: ${regel.trim()}');
              }
            }
          }
        }

        expect(
          kaal,
          isEmpty,
          reason:
              'deze docker-aanroep(en) leunen op DOCKER_HOST uit de omgeving, en '
              'die wijst op deze runner naar een naam die in de dind niet '
              'bestaat. Zet er `-H "\$DH"` op, met DH uit de stap '
              '"Adres van de docker-daemon bepalen":\n  ${kaal.join('\n  ')}',
        );
      });

      test('bepaalt het daemon-adres zelf, en zet geen DOCKER_HOST meer', () {
        final bron = file.readAsStringSync();

        // De stap die de gateway uitleest is de bron van `$DH`; zonder die stap
        // verwijst elke `-H` naar een lege waarde.
        expect(
          bron,
          contains('id: dockerd'),
          reason: '$pad mist de stap die het daemon-adres uitleest',
        );
        expect(
          bron,
          contains(r'echo "host=tcp://$GW:2375" >> "$GITHUB_OUTPUT"'),
          reason: '$pad schrijft het uitgelezen adres niet als stap-output weg',
        );

        // Een `DOCKER_HOST` in een `env:`-blok leest als een werkende
        // instelling, maar de runner overschrijft hem. Dat misverstand kostte
        // deze workflows hun hele bestaan; laat het niet terugkomen. Bewust op
        // de geparste YAML en niet op de brontekst: het commentaar hierboven
        // noemt de variabele juist om uit te leggen waarom ze er niet staat.
        expect(
          envSleutels(file),
          isNot(contains('DOCKER_HOST')),
          reason:
              '$pad zet DOCKER_HOST in een env:-blok — dat wordt door de '
              'runnerconfig overschreven en wekt de indruk dat het adres '
              'geregeld is. Gebruik `-H`.',
        );
      });
    });
  }
}
