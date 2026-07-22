import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/pack_web_release.dart';

/// De inpakstap voor de webrelease (`tool/pack_web_release.dart`).
///
/// Getoetst op een nagebouwde bundel in een tijdelijke map, niet op
/// `build/web`: die bestaat alleen na een volledige webbuild, en een test die
/// daarop wacht draait in de praktijk nooit. De echte boom komt aan het eind
/// wél aan bod — daar wordt gekeken of de bronbestanden die deze stap belooft
/// te kopiëren er ook echt zijn, want een lijst die naar niets wijst pakt een
/// lege bundel in en meldt vrolijk succes.
void main() {
  late Directory tijdelijk;
  late Directory wortel;
  late Directory bundel;

  /// Zet een repowortel met alle bronbestanden en een bundel met wat inhoud.
  setUp(() {
    tijdelijk = Directory.systemTemp.createTempSync('pack_web_release');
    wortel = Directory('${tijdelijk.path}/wortel')..createSync();
    bundel = Directory('${tijdelijk.path}/bundel')..createSync();
    for (final bron in releaseArtefacten.keys) {
      final bestand = File('${wortel.path}/$bron');
      bestand.parent.createSync(recursive: true);
      bestand.writeAsStringSync('inhoud van $bron');
    }
    File('${bundel.path}/index.html').writeAsStringSync('<html></html>');
    Directory('${bundel.path}/canvaskit').createSync();
    File('${bundel.path}/canvaskit/canvaskit.wasm').writeAsBytesSync([0, 1, 2]);
  });

  tearDown(() => tijdelijk.deleteSync(recursive: true));

  group('inpakken', () {
    test('elk artefact belandt in de bundel en de lijst dekt alles', () {
      expect(pak(bundel, wortel), isEmpty);

      for (final doel in releaseArtefacten.values) {
        expect(
          File('${bundel.path}/$doel').existsSync(),
          isTrue,
          reason: '$doel hoort naast de bundel te liggen',
        );
      }
      expect(controleer(bundel), isEmpty);
    });

    test('een ontbrekend bronbestand is een fout, geen stille overslag', () {
      File('${wortel.path}/LICENSE.md').deleteSync();

      expect(pak(bundel, wortel), ['LICENSE.md']);
      // En er is dan geen lijst geschreven: een halve bundel verzegelen zou de
      // controle groen maken over precies de bundel die niet uit mag.
      expect(File('${bundel.path}/$checksumBestand').existsSync(), isFalse);
    });

    test('de lijst is gesorteerd en noemt zichzelf niet', () {
      pak(bundel, wortel);

      final regels = File(
        '${bundel.path}/$checksumBestand',
      ).readAsLinesSync().where((r) => r.isNotEmpty).toList();
      final paden = [for (final r in regels) r.substring(r.indexOf('  ') + 2)];

      expect(paden, orderedEquals([...paden]..sort()));
      expect(paden, isNot(contains(checksumBestand)));
      expect(paden, contains('index.html'));
      expect(paden, contains('canvaskit/canvaskit.wasm'));
    });

    test('twee keer inpakken geeft dezelfde lijst', () {
      // Reproduceerbaar, want anders zegt een verschil in de digest niets over
      // de inhoud en wordt de vergelijking met de aankondiging ruis.
      pak(bundel, wortel);
      final eerste = File('${bundel.path}/$checksumBestand').readAsStringSync();
      pak(bundel, wortel);

      expect(
        File('${bundel.path}/$checksumBestand').readAsStringSync(),
        eerste,
      );
    });

    test('het formaat is dat van sha256sum: hash, twee spaties, pad', () {
      pak(bundel, wortel);

      final regel = File(
        '${bundel.path}/$checksumBestand',
      ).readAsLinesSync().first;
      expect(regel, matches(RegExp(r'^[0-9a-f]{64} {2}\S')));
    });
  });

  group('controleren', () {
    setUp(() => pak(bundel, wortel));

    test('een gewijzigd bestand valt door de mand', () {
      File(
        '${bundel.path}/index.html',
      ).writeAsStringSync('<html>anders</html>');

      expect(controleer(bundel), ['index.html wijkt af van $checksumBestand.']);
    });

    test('een bestand dat erbij komt valt door de mand', () {
      // Dit is het geval waarvoor de controle bestaat: een latere buildstap die
      // iets toevoegt zou anders buiten de lijst vallen en onopgemerkt blijven.
      File('${bundel.path}/binnengeslopen.js').writeAsStringSync('alert(1)');

      expect(controleer(bundel), [
        'binnengeslopen.js staat niet in $checksumBestand.',
      ]);
    });

    test('een bestand dat verdwijnt valt door de mand', () {
      File('${bundel.path}/index.html').deleteSync();

      expect(controleer(bundel), [
        'index.html staat in $checksumBestand maar ligt niet in de bundel.',
      ]);
    });

    test('een verwijderd artefact wordt bij naam genoemd', () {
      File('${bundel.path}/LICENSE.md').deleteSync();

      expect(
        controleer(bundel),
        contains('LICENSE.md ontbreekt in de bundel.'),
      );
    });

    test('zonder lijst is er niets te controleren, en dat wordt gezegd', () {
      File('${bundel.path}/$checksumBestand').deleteSync();

      expect(
        controleer(bundel),
        contains(
          '$checksumBestand ontbreekt — draai tool/pack_web_release.dart.',
        ),
      );
    });
  });

  group('de digest voor de aankondiging', () {
    test('verandert zodra er iets aan de bundel verandert', () {
      pak(bundel, wortel);
      final voor = bundelDigest(bundel);

      File(
        '${bundel.path}/index.html',
      ).writeAsStringSync('<html>anders</html>');
      pak(bundel, wortel);

      expect(bundelDigest(bundel), isNot(voor));
      expect(bundelDigest(bundel), matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('tegen de echte boom', () {
    test('elk beloofd bronbestand bestaat', () {
      // Zonder deze groep zou een hernoemde THIRD_PARTY_NOTICES.md pas opvallen
      // bij de release zelf — de rest van deze test draait immers op verzonnen
      // bestanden die per definitie bestaan.
      for (final bron in releaseArtefacten.keys) {
        expect(
          File(bron).existsSync(),
          isTrue,
          reason: '$bron staat in releaseArtefacten maar bestaat niet',
        );
      }
    });

    test('de Makefile roept de inpakstap aan in build-web', () {
      final makefile = File('Makefile').readAsStringSync();
      final buildWeb = makefile.substring(makefile.indexOf('\nbuild-web:'));
      final doel = buildWeb.substring(0, buildWeb.indexOf('\n\n'));

      expect(doel, contains('tool/pack_web_release.dart'));
    });

    test('de uitleg belooft geen handtekening', () {
      // De zin uit checksumUitleg belandt in de documentatie. Overschrijft
      // iemand hem met iets stelligers, dan is dat hier een rood kruis en geen
      // ontdekking achteraf.
      expect(checksumUitleg, contains('geen handtekening'));
    });
  });
}
