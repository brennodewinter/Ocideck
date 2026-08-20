// Slaat Windows over om dezelfde reden als homebrew_cask_test.dart: de test
// roept `bash scripts/verify_homebrew_cask.sh` aan (curl/sed/mktemp), en de
// cask is macOS-only — op Windows draait dat script niet in productie.
@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// De terugleescontrole op de Homebrew-tap
/// (`scripts/verify_homebrew_cask.sh`).
///
/// De cask-stap in `.forgejo/workflows/release.yml` slikt een mislukte clone
/// bewust in (`exit 0`), zodat een onbereikbare tap een afgeronde release niet
/// rood maakt. Daardoor las een groene job óók als "tap bijgewerkt" terwijl er
/// niets gepusht was: een ingetrokken `HOMEBREW_TAP_TOKEN` bleef onzichtbaar
/// tot iemand via `brew` een oude versie installeerde.
///
/// Deze controle meet daarom wat er in de tap stáát in plaats van het aan te
/// nemen. De tests pinnen de twee helften die stil kunnen wegrotten:
///   1. het oordeel zelf — een achtergebleven cask moet rood geven, want dat
///      is precies het geval dat eerst groen was;
///   2. de bedrading — de releaseketen moet de controle ook echt draaien; een
///      script dat niemand aanroept bewaakt niets.
void main() {
  late Directory temp;
  late String repoRoot;

  setUp(() {
    repoRoot = Directory.current.path;
    temp = Directory.systemTemp.createTempSync('brew_verify');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File writeCask(String version) => File('${temp.path}/ocideck.rb')
    ..writeAsStringSync(
      'cask "ocideck" do\n'
      '  version "$version"\n'
      '  sha256 "abc"\n'
      'end\n',
    );

  // CASK_FILE houdt de test offline: zonder die haak zou het script de tap
  // over het netwerk bevragen en zou de uitkomst van de dag afhangen.
  ProcessResult run(String tag, {File? cask}) => Process.runSync(
    'bash',
    ['scripts/verify_homebrew_cask.sh', tag],
    workingDirectory: repoRoot,
    environment: {if (cask != null) 'CASK_FILE': cask.path},
  );

  test('een cask op de releaseversie is groen', () {
    final r = run('v0.4.6', cask: writeCask('0.4.6'));
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('0.4.6'));
  });

  test('een achtergebleven cask is rood', () {
    final r = run('v0.4.7', cask: writeCask('0.4.6'));
    expect(r.exitCode, isNot(0));
    // De melding moet de dader noemen, niet alleen dat er iets niet klopt:
    // wie dit in een release-log tegenkomt moet weten waar hij moet kijken.
    expect(r.stderr, contains('HOMEBREW_TAP_TOKEN'));
  });

  test('een cask zonder versieregel is rood', () {
    final leeg = File('${temp.path}/leeg.rb')
      ..writeAsStringSync('cask do\nend\n');
    expect(run('v0.4.6', cask: leeg).exitCode, isNot(0));
  });

  test('een ontbrekend cask-bestand is rood', () {
    final weg = File('${temp.path}/bestaat-niet.rb');
    expect(run('v0.4.6', cask: weg).exitCode, isNot(0));
  });

  test('een prerelease-tag wordt niet getoetst', () {
    // De generator publiceert prereleases niet naar de tap, dus daar blijven
    // staan op de vorige stabiele versie is juist goed gedrag.
    final r = run('v0.5.0-rc1', cask: writeCask('0.4.6'));
    expect(r.exitCode, 0, reason: '${r.stderr}');
  });

  test('de releaseketen draait de controle na het pushen', () {
    final file = File('.forgejo/workflows/release.yml');
    expect(file.existsSync(), isTrue, reason: 'release.yml niet gevonden');

    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    final job = (doc['jobs'] as YamlMap)['homebrew-cask'] as YamlMap;
    final steps = (job['steps'] as YamlList).toList();

    final duwt = steps.indexWhere(
      (s) => ((s as YamlMap)['run'] as String?)?.contains('git push') ?? false,
    );
    final toetst = steps.indexWhere(
      (s) =>
          ((s as YamlMap)['run'] as String?)?.contains(
            'verify_homebrew_cask.sh',
          ) ??
          false,
    );

    expect(duwt, isNot(-1), reason: 'geen push-stap in de cask-job');
    expect(
      toetst,
      isNot(-1),
      reason:
          'de cask-job draait verify_homebrew_cask.sh niet; een groene job zegt '
          'dan opnieuw niets over wat er in de tap staat',
    );
    expect(
      toetst,
      greaterThan(duwt),
      reason:
          'de controle moet ná het pushen lezen, anders toetst hij de '
          'vorige release',
    );
  });
}
