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
    // Wat Flutter achterlaat en er niet hoort; zie [nietUitleveren].
    File('${bundel.path}/.last_build_id').writeAsStringSync('fb2348c4');
    // Het bootstrap-bestand met een wíllekeurig serviceWorkerVersion-getal en de
    // service-worker waarnaar dat als cache-buster verwijst. [pak] hoort dat
    // getal deterministisch te maken; zie [normaliseerServiceWorkerVersie] (#1027).
    File(
      '${bundel.path}/$serviceWorkerBestand',
    ).writeAsStringSync('// service-workerinhoud');
    File('${bundel.path}/$bootstrapBestand').writeAsStringSync(
      '_flutter.loader.load({\n'
      '  serviceWorkerSettings: {\n'
      '    serviceWorkerVersion: "1177672334" /* deprecated */\n'
      '  }\n});\n',
    );
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

    test('build-info.json staat in de bundel met een git-describe (#1893)', () {
      pak(bundel, wortel);

      final info = File('${bundel.path}/build-info.json');
      expect(info.existsSync(), isTrue, reason: 'build-info.json hoort erin');
      // In een temp-map zonder git is de terugval 'onbekend'; in de echte
      // repo geeft git describe een tag of commit-hash. Beide zijn geldig.
      final inhoud = info.readAsStringSync();
      expect(inhoud, contains('git_describe'));
      // Staat in SHA256SUMS, anders is het niet verzegeld.
      final lijst = File('${bundel.path}/$checksumBestand').readAsLinesSync();
      expect(lijst, anyElement(contains('build-info.json')));
    });

    test('.DS_Store en andere dotfiles worden verwijderd (#1888)', () {
      // Finder dropt .DS_Store in build/web zodra iemand de map opent.
      File('${bundel.path}/.DS_Store').writeAsStringSync('metadata');
      File('${bundel.path}/.localized').writeAsStringSync('nl');
      // Een bewust meegenomen artefact dat met een punt begint mag blijven.
      // (Er is er nu geen in releaseArtefacten, maar de guard hoort er te zijn.)

      pak(bundel, wortel);

      expect(
        File('${bundel.path}/.DS_Store').existsSync(),
        isFalse,
        reason: '.DS_Store hoort niet in de uit te leveren bundel',
      );
      expect(
        File('${bundel.path}/.localized').existsSync(),
        isFalse,
        reason: '.localized hoort niet in de uit te leveren bundel',
      );
      // De bundel is nog steeds compleet en verzegeld.
      expect(controleer(bundel), isEmpty);
    });

    test('de dotfiles die web/ bewust meeneemt blijven staan (#1888)', () {
      // Flutter kopieert `web/` in de bundel. Twee van die ingangen beginnen
      // met een punt en horen er wél in: `.htaccess` draagt de
      // beveiligingsheaders (#849) waar check_web_hardening.dart op staat, en
      // `.well-known/security.txt` is het meldadres uit RFC 9116. De
      // dotfile-sweep van #1888 keek alleen naar releaseArtefacten en veegde
      // ze allebei weg, waarna de release-poort viel op een bundel die de
      // vorige release nog wél had.
      Directory('${wortel.path}/web/.well-known').createSync(recursive: true);
      File('${wortel.path}/web/.htaccess').writeAsStringSync('Header set X 1');
      File(
        '${wortel.path}/web/.well-known/security.txt',
      ).writeAsStringSync('Contact: mailto:security@librekat.nl');
      // Op een Mac ligt hier ook Finder-metadata; die hoort er juist niet in.
      File('${wortel.path}/web/.DS_Store').writeAsStringSync('metadata');
      // Zoals Flutter het neerzet: alles uit web/ staat al in de bundel.
      Directory('${bundel.path}/.well-known').createSync(recursive: true);
      File('${bundel.path}/.htaccess').writeAsStringSync('Header set X 1');
      File(
        '${bundel.path}/.well-known/security.txt',
      ).writeAsStringSync('Contact: mailto:security@librekat.nl');
      File('${bundel.path}/.DS_Store').writeAsStringSync('metadata');

      pak(bundel, wortel);

      expect(
        File('${bundel.path}/.htaccess').existsSync(),
        isTrue,
        reason: 'de beveiligingsheaders horen met de bundel mee (#849)',
      );
      expect(
        File('${bundel.path}/.well-known/security.txt').existsSync(),
        isTrue,
        reason: 'het meldadres hoort met de bundel mee (RFC 9116)',
      );
      expect(
        File('${bundel.path}/.DS_Store').existsSync(),
        isFalse,
        reason: 'wat op nietUitleveren staat wint van de web/-herkomst',
      );
      // En ze zijn verzegeld: erin zonder in de lijst is niet verzegeld.
      final lijst = File('${bundel.path}/$checksumBestand').readAsStringSync();
      expect(lijst, contains('.htaccess'));
      expect(lijst, contains('.well-known/security.txt'));
      expect(controleer(bundel), isEmpty);
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

    test('.last_build_id gaat de bundel uit en komt niet in de lijst', () {
      // De inhoud is een md5 over onder meer het absolute pad van de uitvoermap
      // op de bouwmachine. Verzegeld meegeven zou betekenen dat wie zelf bouwt
      // — precies wat KNOWN_LIMITATIONS aanraadt — de gepubliceerde digest
      // gegarandeerd niet kan reproduceren, bij byte-identieke bron.
      pak(bundel, wortel);

      expect(File('${bundel.path}/.last_build_id').existsSync(), isFalse);
      expect(
        File('${bundel.path}/$checksumBestand').readAsStringSync(),
        isNot(contains('.last_build_id')),
      );
    });

    test('de bundel is daarna schoon volgens de eigen controle', () {
      // De uitsluiting mag geen gat in de controle slaan: een verwijderd
      // bestand dat nog in de lijst stond zou hier als klacht opduiken.
      pak(bundel, wortel);

      expect(controleer(bundel), isEmpty);
    });
  });

  group('service-workerversie deterministisch maken', () {
    // Een minimale bundel met alleen de twee bestanden die de normalisatie raakt,
    // zodat de afleiding los van het pak-geheel te toetsen is.
    Directory mini(String naam, String startgetal, String swInhoud) {
      final d = Directory('${tijdelijk.path}/$naam')..createSync();
      File('${d.path}/$serviceWorkerBestand').writeAsStringSync(swInhoud);
      File('${d.path}/$bootstrapBestand').writeAsStringSync(
        'x();serviceWorkerVersion: "$startgetal" /* deprecated */\n',
      );
      return d;
    }

    String versieVan(Directory d) {
      final m = RegExp(
        r'serviceWorkerVersion: "(\d+)"',
      ).firstMatch(File('${d.path}/$bootstrapBestand').readAsStringSync());
      return m!.group(1)!;
    }

    test(
      'de willekeurige versie wordt afgeleid van de service-workerinhoud',
      () {
        pak(bundel, wortel);
        final verwacht = serviceWorkerVersieUit(
          File('${bundel.path}/$serviceWorkerBestand').readAsBytesSync(),
        );
        final bootstrap = File(
          '${bundel.path}/$bootstrapBestand',
        ).readAsStringSync();
        expect(bootstrap, contains('serviceWorkerVersion: "$verwacht"'));
        // Het oude willekeurige getal is echt weg, niet er alleen naast gezet.
        expect(bootstrap, isNot(contains('1177672334')));
      },
    );

    test(
      'dezelfde service-worker geeft dezelfde versie, ongeacht het startgetal',
      () {
        // De kern van de reproduceerbaarheid: twee schone builds beginnen met een
        // ander willekeurig getal, maar de genormaliseerde waarde hangt alleen aan
        // de inhoud, dus ze komen op precies hetzelfde uit.
        final a = mini('mini_a', '111', 'zelfde inhoud');
        final b = mini('mini_b', '999999999', 'zelfde inhoud');
        normaliseerServiceWorkerVersie(a);
        normaliseerServiceWorkerVersie(b);
        expect(versieVan(a), versieVan(b));
      },
    );

    test('een andere service-worker geeft een andere versie', () {
      // Cache-busting blijft kloppen: verandert de service-worker, dan verandert
      // de versie mee — anders zou een deterministische waarde een verouderde
      // service-worker kunnen laten hangen.
      final a = mini('mini_c', '111', 'inhoud een');
      final b = mini('mini_d', '111', 'inhoud twee');
      normaliseerServiceWorkerVersie(a);
      normaliseerServiceWorkerVersie(b);
      expect(versieVan(a), isNot(versieVan(b)));
    });

    test('zonder service-worker of versieregel gebeurt er niets', () {
      // Het mechanisme is afgeschreven en mag verdwijnen; de reparatie mag nooit
      // een build breken. Ontbreekt de service-worker, dan blijft de bootstrap
      // ongemoeid in plaats van te crashen.
      final d = Directory('${tijdelijk.path}/mini_geen_sw')..createSync();
      const bootstrap = 'x();serviceWorkerVersion: "111" /* deprecated */\n';
      File('${d.path}/$bootstrapBestand').writeAsStringSync(bootstrap);
      normaliseerServiceWorkerVersie(d); // geen service-worker → no-op
      expect(File('${d.path}/$bootstrapBestand').readAsStringSync(), bootstrap);
    });

    test('serviceWorkerVersieUit is een stabiel decimaal getal', () {
      final een = serviceWorkerVersieUit('abc'.codeUnits);
      final twee = serviceWorkerVersieUit('abc'.codeUnits);
      expect(een, twee);
      expect(een, matches(RegExp(r'^\d+$')));
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

    test('geen enkele ingang uit web/ sneuvelt bij het inpakken', () {
      // De verzonnen bundel hierboven bewijst dat de sweep opruimt; hij bewijst
      // niet dat hij de échte bundel heelhoudt, want de bestanden erin zijn
      // bedacht door dezelfde persoon als de sweep. Precies daar ging #1888
      // doorheen: die PR had een test die groen bleef terwijl `.htaccess` en
      // `.well-known/security.txt` uit de bundel verdwenen, en dat kwam pas bij
      // de release aan het licht — een webbouw draait niet per PR.
      //
      // Deze test leest daarom de echte `web/` en zet de namen daaruit in een
      // nagebouwde bundel. Komt er morgen een dotfile bij, dan telt hij mee
      // zonder dat iemand hier iets aanpast; de fout van #1888 was juist dat de
      // lijst met "bewuste" bestanden achterliep op de werkelijkheid.
      final echteWeb = Directory('web');
      final verwacht = <String>[];
      for (final entiteit in echteWeb.listSync(recursive: true)) {
        if (entiteit is! File) continue;
        final pad = entiteit.path.substring('web/'.length);
        // Zoals `flutter build web` het neerzet: web/ staat in de bundel.
        final uit = File('${bundel.path}/$pad');
        uit.parent.createSync(recursive: true);
        uit.writeAsStringSync('inhoud van $pad');
        // Ook in de nagebouwde wortel, want daar leest [bewusteDotfiles].
        final bron = File('${wortel.path}/web/$pad');
        bron.parent.createSync(recursive: true);
        bron.writeAsStringSync('inhoud van $pad');
        if (!nietUitleveren.contains(pad.split('/').last)) verwacht.add(pad);
      }
      // Anders toetst deze test niets: een lege web/ maakt hem groen.
      expect(verwacht, isNotEmpty);

      pak(bundel, wortel);

      for (final pad in verwacht) {
        expect(
          File('${bundel.path}/$pad').existsSync(),
          isTrue,
          reason: 'web/$pad hoort de bundel te halen',
        );
      }
      for (final weg in nietUitleveren) {
        expect(
          File('${bundel.path}/$weg').existsSync(),
          isFalse,
          reason: '$weg staat op nietUitleveren en hoort de bundel niet uit',
        );
      }
    });

    test('de Makefile roept de inpakstap aan in build-web', () {
      final makefile = File('Makefile').readAsStringSync();
      final buildWeb = makefile.substring(makefile.indexOf('\nbuild-web:'));
      final doel = buildWeb.substring(0, buildWeb.indexOf('\n\n'));

      expect(doel, contains('tool/pack_web_release.dart'));
    });

    test('de uitleg belooft geen handtekening, en niets uit zichzelf', () {
      // De zin uit checksumUitleg belandt in documentatie en in
      // release-aankondigingen. Overschrijft iemand hem met iets stelligers,
      // dan is dat hier een rood kruis en geen ontdekking achteraf.
      expect(checksumUitleg, contains('geen handtekening'));
      // Óók de bescheidenheid staat onder bewaking, niet alleen het woord
      // "handtekening": een lijst die naast de bundel ligt toont uit zichzelf
      // niets — dat wordt het pas als een mens hem tegen een ander kanaal legt.
      expect(checksumUitleg, contains('Op zichzelf'));
      expect(checksumUitleg, contains('ander kanaal'));
    });

    test('SOURCE.md wijst naar de repo waar de bron werkelijk staat', () {
      // EUPL-1.2 artikel 5 vraagt bij het communiceren van het Werk om de bron
      // of een aanwijzing ernaartoe, en de bundel is gecompileerd. Een
      // SOURCE.md die de repo niet noemt haalt dat niet.
      final bron = File('SOURCE.md').readAsStringSync();
      final readme = File('README.md').readAsStringSync();

      expect(releaseArtefacten.keys, contains('SOURCE.md'));
      expect(bron, contains('pawprint.vigilis.online/LibreKAT/Ocideck'));
      // Dezelfde URL als de README noemt; twee adressen die uiteenlopen is
      // precies hoe een verwijzing stilletjes dood raakt.
      expect(readme, contains('pawprint.vigilis.online/LibreKAT/Ocideck'));
    });
  });
}
