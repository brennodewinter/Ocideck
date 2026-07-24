// De verklaring bij een omgevallen suite (#798), en het opruimdoel ernaast.
//
// **Wat hier bewaakt wordt en wat niet.** De storing zelf laat zich onder
// `flutter test` niet naspelen: hij zit in de verbinding tussen het harnas en
// het testproces, een laag onder deze suite. Wat wél toetsbaar is, is de
// verklaring — en daarvan is één eigenschap belangrijker dan alle andere:
//
//   **een échte laadfout mag nooit als "bekend" worden weggezet.**
//
// Een bestand dat niet compileert is óók een laadfout, en die kost stilte in de
// suite: de tests erin draaien niet en tellen niet mee. Zou de verklaring die
// afdoen als de bekende kanaalstoring, dan is dit hulpmiddel erger dan geen
// hulpmiddel. Vandaar de toets met beide soorten naast elkaar.
//
// De rest bewaakt de bedrading, die stil kan wegvallen zonder dat iets anders
// rood wordt: geen `flutter test` zonder rapport én zonder verklaring, de
// afloop van de suite blijft de afloop van de suite, en `clean-test-cache`
// blijft binnen `build/test_cache` — een `rm -rf build` neemt de
// platformbuilds mee, en daarmee de native OpenCV-bibliotheek waar DARTCV_LIB
// aan hangt; de gezichtsdetectietests slaan zichzelf dan weer over en de suite
// staat groen om de verkeerde reden.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/explain_suite_failure.dart';

/// De receptregels van één doel: alles tot de eerste lege regel erna.
///
/// Gooit in plaats van te `expect`en, zodat dit ook buiten een test aangeroepen
/// mag worden zonder de suite te laten stranden op een OutsideTestException.
String _recipe(String makefile, String target) {
  final start = makefile.indexOf('\n$target:');
  if (start == -1) {
    throw StateError('doel $target staat niet in de Makefile');
  }
  final rest = makefile.substring(start + 1);
  final end = rest.indexOf('\n\n');
  return end == -1 ? rest : rest.substring(0, end);
}

/// Bouwt een regelgescheiden JSON-rapport zoals `--file-reporter json:…` het
/// schrijft. De vorm is overgenomen van een echt rapport, niet verzonnen.
String _report(List<Map<String, Object?>> events) =>
    events.map(jsonEncode).join('\n');

Map<String, Object?> _loadingOf(int id, String path) => <String, Object?>{
  'test': <String, Object?>{
    'id': id,
    'name': 'loading $path',
    'suiteID': 0,
    'groupIDs': <int>[],
  },
  'type': 'testStart',
  'time': 0,
};

Map<String, Object?> _errorOn(int id, String error) => <String, Object?>{
  'testID': id,
  'error': error,
  'stackTrace': '',
  'type': 'error',
  'time': 1,
};

void main() {
  group('loadFailuresFrom', () {
    test('pikt een bestand op dat niet geladen kon worden', () {
      final failures = loadFailuresFrom(
        _report(<Map<String, Object?>>[
          _loadingOf(1, '/repo/test/snappy_test.dart'),
          _errorOn(
            1,
            'Failed to load "/repo/test/snappy_test.dart": '
            "type '_Map<String, dynamic>' is not a subtype of "
            "type 'List<dynamic>' in type cast",
          ),
        ]),
      );

      expect(failures, hasLength(1));
      expect(failures.single.path, '/repo/test/snappy_test.dart');
    });

    test('een gewoon rode test is géén laadfout', () {
      // Zonder dit onderscheid staat de verklaring onder élke rode suite, en
      // dan leest niemand hem meer.
      final failures = loadFailuresFrom(
        _report(<Map<String, Object?>>[
          <String, Object?>{
            'test': <String, Object?>{'id': 5, 'name': 'telt tot tien'},
            'type': 'testStart',
            'time': 0,
          },
          <String, Object?>{
            'testID': 5,
            'error': 'Expected: <2>\n  Actual: <1>\n',
            'isFailure': true,
            'type': 'error',
            'time': 1,
          },
        ]),
      );

      expect(failures, isEmpty);
    });

    test('een leeg of onleesbaar rapport levert niets op', () {
      expect(loadFailuresFrom(''), isEmpty);
      expect(loadFailuresFrom('geen json\nook niet\n'), isEmpty);
    });

    test('een half weggeschreven laatste regel breekt het lezen niet af', () {
      // Precies wat er gebeurt als de suite midden in een run omvalt: het
      // rapport houdt op halverwege een regel. Wat ervóór staat blijft geldig.
      final compleet = _report(<Map<String, Object?>>[
        _loadingOf(1, '/repo/test/a_test.dart'),
        _errorOn(1, 'Failed to load "/repo/test/a_test.dart": kapot'),
      ]);

      final failures = loadFailuresFrom('$compleet\n{"type":"do');

      expect(failures, hasLength(1));
    });
  });

  group('de bekende storing scheiden van een echte laadfout', () {
    test('de handtekening uit #798 geldt als de bekende storing', () {
      const failure = LoadFailure(
        '/repo/test/snappy_test.dart',
        'Failed to load "/repo/test/snappy_test.dart": '
            "type '_Map<String, dynamic>' is not a subtype of "
            "type 'List<dynamic>' in type cast",
      );

      expect(failure.isKnownTransient, isTrue);
    });

    test('een bestand dat niet compileert wordt NIET weggezet als bekend', () {
      // De belangrijkste toets van dit bestand. Zou dit als "bekend" gelden,
      // dan stuurt de verklaring iemand weg bij een echte fout — en draaien er
      // stilletjes minder tests dan het aantal suggereert.
      const gevallen = <String>[
        'Failed to load "x": Missing definition of `main` method.',
        'Failed to load "x": Compilation failed',
        'Failed to load "x": '
            "type 'String' is not a subtype of type 'int' in type cast",
      ];

      for (final reason in gevallen) {
        expect(
          LoadFailure('x', reason).isKnownTransient,
          isFalse,
          reason: 'deze laadfout hoort een echte te blijven: $reason',
        );
      }
    });

    test('de handtekening staat op de kale List-cast uit stream_channel', () {
      // `MultiChannel` leest zijn verbinding met `stream.cast<List>()`, en een
      // kale `List` leest de VM voor als `List<dynamic>`. Verandert die tekst
      // bovenstrooms, dan herkent de verklaring niets meer — en dat hoort hier
      // op te vallen, niet in een stille draai.
      expect(
        kChannelFramingSignature,
        "is not a subtype of type 'List<dynamic>' in type cast",
      );
    });
  });

  group('de bedrading in de Makefile', () {
    final makefile = File('Makefile').readAsStringSync();

    List<String> suiteAanroepen() => makefile
        .split('\n')
        .where(
          (r) =>
              r.startsWith('\t') &&
              r.contains('flutter test') &&
              !r.contains('@echo'),
        )
        .toList();

    test('elke `flutter test` schrijft een rapport én verklaart een val', () {
      final aanroepen = suiteAanroepen();

      // Tien op het moment van schrijven. De ondergrens staat er zodat een
      // filter dat per ongeluk niets meer vindt niet als groen wegkomt.
      expect(aanroepen.length, greaterThanOrEqualTo(10));
      for (final regel in aanroepen) {
        expect(
          regel,
          contains(r'$(SUITE_REPORT)'),
          reason: 'zonder rapport valt er niets te verklaren:\n$regel',
        );
        expect(
          regel.trimRight(),
          endsWith(r'$(ON_SUITE_FAILURE)'),
          reason:
              'deze `flutter test` valt buiten de verklaring (#798):\n$regel',
        );
      }
    });

    test('het rapport is een zijkanaal, niet een filter over de uitvoer', () {
      final regel = makefile
          .split('\n')
          .firstWhere((r) => r.startsWith('SUITE_REPORT :='));

      // `--file-reporter` schrijft ernáást; `--reporter` zou de uitvoer op het
      // scherm vervangen, en een pipe zou de voortgangsregel kosten. Dat
      // onderscheid is de hele reden dat dit niets kan wegpoetsen.
      expect(regel, contains('--file-reporter json:'));
      expect(regel, isNot(contains('| ')));
    });

    test(
      'ON_SUITE_FAILURE roept de verklaring aan en laat de afloop staan',
      () {
        final regel = makefile
            .split('\n')
            .firstWhere((r) => r.startsWith('ON_SUITE_FAILURE :='));

        expect(regel, contains('tool/explain_suite_failure.dart'));
        // Zonder deze `exit 1` slikt de `||`-tak de rode suite in en staat de
        // poort groen omdat het afdrukken van de verklaring lukte. Dat is erger
        // dan geen verklaring.
        expect(regel, contains('exit 1'));
      },
    );
  });

  group('make clean-test-cache', () {
    final makefile = File('Makefile').readAsStringSync();
    final recept = _recipe(makefile, 'clean-test-cache');

    test('staat in .PHONY', () {
      expect(makefile.split('\n').first, contains('clean-test-cache'));
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

  group('docs/CHECKS.md', () {
    final doc = File('docs/CHECKS.md').readAsStringSync();

    test('draagt de foutsignatuur waarop iemand zoekt', () {
      // Zonder de letterlijke tekst helpt de sectie alleen wie hem al kent —
      // en dat is precies de groep die de uitleg niet nodig heeft.
      expect(doc, contains('Failed to load'));
      expect(doc, contains(kChannelFramingSignature));
    });

    test('wijst de regel aan die werkelijk gooit', () {
      // De cache was de eerste verdachte en bleek het niet. Verdwijnt deze
      // verwijzing, dan begint de volgende lezer weer bij die verdachte.
      expect(doc, contains('multi_channel.dart'));
      expect(doc, contains('stream_channel'));
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
