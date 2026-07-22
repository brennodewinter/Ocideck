// `security-insights.yml` is de machineleesbare helft van wat `SECURITY.md`,
// `CONTRIBUTING.md` en `COMPLIANCE.md` in proza zeggen.
//
// Dat maakt hem gevaarlijker dan de proza-kant, en dat is de reden dat deze
// poort bestaat: dit is de kopie die een machine leest en die niemand
// proefleest. Loopt hij weg van `SECURITY.md`, dan is een verkeerd meldadres
// niet een slordigheid maar een melding die nooit aankomt.
//
// Wat hier bewaakt wordt is de mechanische helft — bestaan de dingen, en
// spreken de documenten elkaar niet tegen. Of de inhoud *klopt* blijft
// mensenwerk. De schemavalidatie zelf (`cue vet` tegen de OpenSSF-spec) staat er
// bewust niet in: dat vraagt een externe binary die `make check` niet mag
// aannemen, net als semgrep. Zie de kop van het bestand voor de spec-versie.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final raw = File('security-insights.yml').readAsStringSync();
  final doc = loadYaml(raw) as YamlMap;

  YamlMap section(String key) => doc[key] as YamlMap;

  test('de schemaversie staat erin en is die waarop dit is geschreven', () {
    // Verspringt de spec, dan hoort iemand de velden na te lopen in plaats van
    // het versienummer bij te werken en verder te gaan.
    expect(section('header')['schema-version'], '2.2.0');
  });

  test('het meldadres is hetzelfde als in SECURITY.md', () {
    final security = File('SECURITY.md').readAsStringSync();
    final reporting = section('project')['vulnerability-reporting'] as YamlMap;
    final email = reporting['contact']['email'] as String;

    expect(
      security,
      contains(email),
      reason:
          'security-insights.yml noemt $email en SECURITY.md niet. Dit is het '
          'adres waarop een melder een kwetsbaarheid stuurt; één van de twee is '
          'verouderd en de melder ontdekt welke.',
    );
  });

  test('de licentie is dezelfde als die van het project', () {
    final expression =
        (section('repository')['license'] as YamlMap)['expression'] as String;
    expect(
      File('LICENSE.md').readAsStringSync(),
      contains(expression),
      reason: 'de SPDX-expressie hoort in LICENSE.md terug te komen',
    );
  });

  test('elk bestand waar het naar wijst, bestaat ook in deze repo', () {
    // De URL's wijzen naar de forge, dus we vertalen ze terug naar een pad.
    // Zo vangt dit een hernoemd of verwijderd document, wat de vorm van
    // veroudering is die hier het meest voor de hand ligt.
    final links = RegExp(
      r'https://pawprint\.vigilis\.online/LibreKAT/Ocideck/(?:raw|src)/branch/main/(\S+)',
    ).allMatches(raw).map((m) => m.group(1)!).toSet();
    expect(links, isNotEmpty, reason: 'geen enkele verwijzing gevonden?');

    final missing = links.where((p) => !File(p).existsSync()).toList();
    expect(
      missing,
      isEmpty,
      reason: 'security-insights.yml verwijst naar iets wat er niet is',
    );
  });

  test('er wordt geen rentmeester geclaimd zolang die vraag open staat', () {
    // Het schema definieert `steward` onder verwijzing naar CRA artikel 3, en
    // of Stichting LibreKAT dat is, staat niet vast — zie
    // assurance/CRA-2024-2847-positie.md. Dit veld invullen zou het label
    // claimen; weglaten claimt niets, en dat is de accurate positie.
    expect(
      section('project').containsKey('steward'),
      isFalse,
      reason:
          'vul `steward` pas in als de rentmeestervraag beslist is, en werk dan '
          'ook assurance/CRA-2024-2847-positie.md en COMPLIANCE.md bij',
    );
  });

  test('er worden geen releases beweerd die er niet zijn', () {
    // De release-secties liegen het makkelijkst: ze staan vol in het voorbeeld
    // van de spec, en overnemen is verleidelijk. Zolang BR.02-04 in
    // COMPLIANCE.md niet aangevinkt zijn, hoort hier geen pijplijn te staan.
    final release = section('repository')['release'] as YamlMap;
    expect(release['automated-pipeline'], isFalse);
    expect(release.containsKey('distribution-points'), isFalse);
    expect(release.containsKey('attestations'), isFalse);
  });
}
