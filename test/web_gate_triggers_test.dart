@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Bewaakt dát de webbundel per PR écht gebouwd wordt — niet wát erin zit.
///
/// De harding van de webbundel (`make check-web`) draaide alleen lokaal in
/// `check-full` en op een `v*`-tag. Tussen die twee zag niets een echte
/// `flutter build web`, en dat kostte de release van v0.5.0: de
/// dotfile-opruiming uit #1888 verwijderde `.htaccess` en
/// `.well-known/security.txt` uit `build/web`, en de eerste machine die dat
/// merkte was fase 1 van de releaseketen. Alle poorten stonden intussen groen —
/// de per-PR-test van #1888 draaide op een met de hand gebouwde bundel die
/// precies de bestanden miste die de wijziging brak.
///
/// `web-gate.yml` zet die bouw wél op de PR neer, maar alleen wanneer er iets
/// veranderde dat de bundel kan breken. Dat padfilter is precies waar de
/// bescherming stil kan verdwijnen: een poort die niet afgaat bewaakt niets.
/// Vandaar dat elke invoer hieronder met zijn reden staat — die reden is wat
/// een volgende lezer nodig heeft om te beoordelen of hij er een weg mag halen.
void main() {
  const pad = '.forgejo/workflows/web-gate.yml';

  /// De invoeren die de gebouwde webbundel kunnen breken.
  const invoeren = {
    'web/**':
        'de bron die `flutter build web` letterlijk kopieert — hier wonen '
        '.htaccess (#849) en .well-known/security.txt (RFC 9116)',
    'tool/pack_web_release.dart':
        'de inpakstap die de bundel verzegelt — hier ging #1888 mis',
    'tool/check_web_hardening.dart': 'de poort zelf',
    'tool/check_bundled_docs_fresh.dart': 'het derde been van check-web',
    'Makefile':
        'de bouwvlaggen die de harding maken (--no-web-resources-cdn, --csp) '
        'en de permissienormalisatie erna',
    'pubspec.yaml':
        'een asset of een plugin erbij — een plugin zonder web-implementatie '
        'breekt pas bij het bouwen',
    'pubspec.lock': 'de opgeloste afhankelijkheden',
    '.tool-versions':
        'de Flutter-pin: andere compiler, andere web-engine, andere loader',
    '.forgejo/ci-image/**': 'het image waarin deze poort draait',
    '.forgejo/workflows/web-gate.yml':
        'de poort zelf — een wijziging eraan hoort hem te laten draaien',
  };

  final bestand = File(pad);

  test('$pad bestaat', () {
    expect(
      bestand.existsSync(),
      isTrue,
      reason: '$pad niet gevonden — dan bouwt geen enkele poort de web per PR',
    );
  });

  if (!bestand.existsSync()) return;

  final tekst = bestand.readAsStringSync();
  final doc = loadYaml(tekst) as YamlMap;
  final trekkers = doc['on'] as YamlMap;

  group('$pad: de trekkers', () {
    test('gaat af op een pull request', () {
      expect(
        trekkers.containsKey('pull_request'),
        isTrue,
        reason:
            'zonder PR-trekker verschuift er niets naar links en is de '
            'releaseketen weer de eerste die een kapotte bundel ziet',
      );
    });

    test('draait ook na een merge naar main', () {
      // Een PR-run toetst de *voorvertoning* van één samenvoeging. Landen er
      // twee PR's vlak na elkaar, dan zijn beide runs groen en is de uitkomst
      // het toch niet — dezelfde redenering als in static-gate.yml.
      final push = trekkers['push'] as YamlMap?;
      expect(
        (push?['branches'] as YamlList?)?.toList(),
        equals(['main']),
        reason: '$pad ziet de échte samenvoeging niet, alleen de voorvertoning',
      );
    });

    test('blijft met de hand te starten', () {
      expect(
        trekkers.containsKey('workflow_dispatch'),
        isTrue,
        reason: 'een bouw op afroep is de enige route zonder tag of PR',
      );
    });
  });

  /// Het filter staat **per trekker**, en dat is de valkuil: één lijst
  /// aanpassen en de andere laten staan levert een poort op die op een PR zwijgt
  /// en na de merge alsnog rood wordt. Toets daarom elke trekker apart, niet de
  /// tekst van het bestand als geheel.
  for (final trekker in ['pull_request', 'push']) {
    group('$pad: het padfilter van $trekker', () {
      final paden = ((trekkers[trekker] as YamlMap?)?['paths'] as YamlList?)
          ?.cast<String>()
          .toList();

      test('bestaat', () {
        expect(
          paden,
          isNotNull,
          reason:
              'zonder filter draait deze bouw op élke wijziging — de kosten '
              'die #790 juist wegnam',
        );
      });

      test('noemt elke invoer die de webbundel kan breken', () {
        for (final invoer in invoeren.entries) {
          expect(
            paden,
            contains(invoer.key),
            reason:
                '$pad slaat een $trekker over die ${invoer.key} raakt '
                '(${invoer.value})',
          );
        }
      });
    });
  }

  test('$pad: de twee padfilters lopen niet uiteen', () {
    // Wat een PR bouwt en wat een merge bouwt hoort hetzelfde te zijn. Gaan ze
    // uit elkaar lopen, dan is één van beide stil zwakker geworden.
    List<String>? filter(String trekker) =>
        ((trekkers[trekker] as YamlMap?)?['paths'] as YamlList?)
            ?.cast<String>()
            .toList();
    expect(filter('pull_request'), equals(filter('push')));
  });

  group('$pad: wat de job doet', () {
    test('draait `make check-web` en geen nagebouwde deelverzameling', () {
      // De drie stappen van check-web staan in de Makefile. Ze hier overtypen
      // levert een tweede waarheid op die uit elkaar gaat lopen — dezelfde
      // reden waarom static-gate `make check-static` aanroept.
      final commandos = [
        for (final job in (doc['jobs'] as YamlMap).values)
          for (final stap in (job as YamlMap)['steps'] as YamlList? ?? const [])
            ((stap as YamlMap)['run'] as String?) ?? '',
      ];
      expect(
        commandos.any((c) => c.trim() == 'make check-web'),
        isTrue,
        reason:
            '$pad hoort de poort uit de Makefile te draaien, niet zijn eigen',
      );
    });

    test('staat op het voorgebakken CI-image', () {
      // Het image-tag ís de Flutter-pin; loopt het achter op `.tool-versions`,
      // dan valt `check-toolchain` elders om. Een kaal ubuntu zou hier de
      // toolchain per run opnieuw installeren.
      final images = [
        for (final job in (doc['jobs'] as YamlMap).values)
          ((job as YamlMap)['container'] as YamlMap?)?['image'] as String?,
      ];
      expect(
        images,
        everyElement(
          startsWith('pawprint.vigilis.online/librekat/ocideck-ci:flutter-'),
        ),
        reason: '$pad draait niet op het gepinde CI-image',
      );
    });
  });
}
