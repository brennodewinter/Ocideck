// De nabrander bij een omgevallen suite (#798), en het opruimdoel waar hij naar
// wijst.
//
// **Waarom dit een poort is en geen regressietest.** De storing zelf laat zich
// hier niet naspelen: hij zit in het laden van een testbestand door `flutter
// test` — een laag onder de suite, die deze suite dus niet kan uitlokken. Drie
// manieren om de kernelcache te beschadigen zijn geprobeerd (afkappen, bytes
// omklappen, vervangen door een dill uit een andere broomboom) en alle drie
// werden opgevangen; zie docs/CHECKS.md. Wat wél toetsbaar is, is de
// tegenmaatregel, en die bestaat uit vier eigenschappen die stil kapot kunnen
// gaan zonder dat iets anders rood wordt:
//
//  1. géén `flutter test` in de Makefile ontsnapt aan de aanwijzing;
//  2. de aanwijzing houdt de afloop van de suite intact (`exit 1`);
//  3. `CARRIED_TEST_CACHE` wordt uitgerekend vóór de suite draait — met een
//     luie `=` staat de tekst onder élke rode test en leest niemand hem meer;
//  4. `clean-test-cache` raakt `build/test_cache` en niets erbuiten.
//
// De vierde is de enige met echte schade als hij fout gaat: een `rm -rf build`
// neemt de platformbuilds mee, en daarmee de native OpenCV-bibliotheek waar
// DARTCV_LIB aan hangt — de gezichtsdetectietests slaan zichzelf dan weer over
// en de suite staat groen om de verkeerde reden.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De receptregels van één doel: alles tot de eerste lege regel erna.
///
/// Gooit in plaats van te `expect`en, zodat dit ook buiten een test aangeroepen
/// mag worden zonder de hele suite te laten stranden op een OutsideTestException.
String _recipe(String makefile, String target) {
  final start = makefile.indexOf('\n$target:');
  if (start == -1) {
    throw StateError('doel $target staat niet in de Makefile');
  }
  final rest = makefile.substring(start + 1);
  final end = rest.indexOf('\n\n');
  return end == -1 ? rest : rest.substring(0, end);
}

void main() {
  final makefile = File('Makefile').readAsStringSync();

  group('de nabrander zit op elke suiteaanroep', () {
    test('elke `flutter test` in een recept sluit af met ON_SUITE_FAILURE', () {
      // Recepten zijn de regels met een tab ervoor; de `@echo "Command: …"`
      // regels ernaast beschrijven alleen wat er gaat gebeuren.
      final aanroepen = makefile
          .split('\n')
          .where(
            (r) =>
                r.startsWith('\t') &&
                r.contains('flutter test') &&
                !r.contains('@echo'),
          )
          .toList();

      // Tien op het moment van schrijven. De ondergrens staat er zodat een
      // regex die per ongeluk niets meer vindt niet als groen wegkomt.
      expect(aanroepen.length, greaterThanOrEqualTo(10));
      for (final regel in aanroepen) {
        expect(
          regel.trimRight(),
          endsWith(r'$(ON_SUITE_FAILURE)'),
          reason:
              'deze `flutter test` valt buiten de aanwijzing uit #798:\n$regel',
        );
      }
    });

    test('ON_SUITE_FAILURE roept het script aan en laat de afloop staan', () {
      final regel = makefile
          .split('\n')
          .firstWhere((r) => r.startsWith('ON_SUITE_FAILURE'));

      expect(regel, contains('scripts/suite_failure_hint.sh'));
      // Zonder deze `exit 1` slikt de `||`-tak de rode suite in en staat de
      // poort groen omdat de aanwijzing gelukt is. Dat is erger dan geen
      // aanwijzing.
      expect(regel, contains('exit 1'));
      expect(regel, contains(r'$(CARRIED_TEST_CACHE)'));
      expect(File('scripts/suite_failure_hint.sh').existsSync(), isTrue);
    });

    test('CARRIED_TEST_CACHE wordt bij het inlezen uitgerekend', () {
      final regel = makefile
          .split('\n')
          .firstWhere((r) => r.startsWith('CARRIED_TEST_CACHE'));

      // `:=` en niet `=`: make rekent hem dan uit bij het inlezen van het
      // bestand, dus vóór de suite draait. Met een luie `=` wordt hij pas
      // uitgerekend als de suite al gedraaid heeft — en die heeft de cache dan
      // zelf net geschreven. Nagemeten: precies zo ging het in de eerste opzet.
      expect(regel, startsWith('CARRIED_TEST_CACHE :='));
      expect(regel, contains(r'$(wildcard build/test_cache/'));
    });
  });

  group('make clean-test-cache', () {
    final recept = _recipe(makefile, 'clean-test-cache');

    test('staat in .PHONY', () {
      final phony = makefile.split('\n').first;
      expect(phony, contains('clean-test-cache'));
    });

    test('verwijdert build/test_cache en niets erbuiten', () {
      // Alleen wat er werkelijk draait; de `@echo`-regels ernaast beschrijven
      // het recept en verwijderen niets.
      final verwijderingen = recept
          .split('\n')
          .where(
            (r) =>
                r.startsWith('\t') && !r.contains('@echo') && r.contains('rm '),
          )
          .toList();

      expect(verwijderingen, hasLength(1));
      expect(verwijderingen.single.trim(), 'rm -rf build/test_cache');
    });

    test('noemt wat het kost', () {
      // Het doel bestaat omdat het recept anders in iemands hoofd zit; dan
      // hoort de prijs erbij, anders wordt het een reflex vóór elke draai.
      expect(recept, contains('van nul'));
    });
  });

  group('het script zelf', () {
    // Draait een echt proces. Onder Windows is er geen bash en draait de poort
    // ook niet; daar zegt deze groep niets in plaats van iets onwaars.
    final script = 'scripts/suite_failure_hint.sh';

    ProcessResult draai(List<String> args) =>
        Process.runSync(script, args, stdoutEncoding: systemEncoding);

    test('zwijgt zonder meegedragen cache', () {
      expect(draai(<String>[]).stderr, isEmpty);
      expect(draai(<String>['']).stderr, isEmpty);
      // Een pad dat niet bestaat is geen meegedragen cache maar een vergissing;
      // ook dan liever niets zeggen dan iets beweren.
      expect(
        draai(<String>['build/test_cache/bestaat-niet.dill']).stderr,
        isEmpty,
      );
    }, skip: Platform.isWindows);

    test(
      'wijst bij een meegedragen cache het opruimdoel aan',
      () {
        final tijdelijk = Directory.systemTemp.createTempSync('hint798');
        addTearDown(() => tijdelijk.deleteSync(recursive: true));
        final dill = File('${tijdelijk.path}/cache.dill.track.dill')
          ..writeAsBytesSync(List<int>.filled(2048, 0));

        final uitvoer = draai(<String>[dill.path]).stderr as String;

        expect(uitvoer, contains('make clean-test-cache'));
        // De signatuur uit de melding zelf, zodat wie hem googelt hier landt.
        expect(uitvoer, contains('Failed to load'));
        // En de bescheidenheid: dit is een verdachte, geen diagnose.
        expect(uitvoer, contains('eerste verdachte'));
        expect(uitvoer, contains('docs/CHECKS.md'));
      },
      skip: Platform.isWindows,
    );
  });

  group('docs/CHECKS.md', () {
    final doc = File('docs/CHECKS.md').readAsStringSync();

    test('draagt de foutsignatuur waarop iemand zoekt', () {
      // Zonder de letterlijke tekst helpt de sectie alleen wie hem al kent —
      // en dat is precies de groep die de aanwijzing niet nodig heeft.
      expect(doc, contains('Failed to load'));
      expect(
        doc,
        contains(
          "type '_Map<String, dynamic>' is not a subtype of "
          "type 'List<dynamic>' in type cast",
        ),
      );
    });

    test('noemt het doel en waar de aanwijzing vandaan komt', () {
      expect(doc, contains('make clean-test-cache'));
      expect(doc, contains('scripts/suite_failure_hint.sh'));
    });

    test('houdt de drie weerlegde verklaringen vast', () {
      // Ze staan er zodat niemand ze nog eens uitprobeert. Verdwijnt de tabel,
      // dan verdwijnt de reden om het niet over te doen.
      expect(doc, contains('Truncated to half its length'));
      expect(doc, contains('bytes flipped mid-file'));
      expect(doc, contains('compiled from a different source tree'));
    });
  });
}
