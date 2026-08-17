import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_ratchet_trend.dart';

/// Het meetinstrument voor de ratchets (`tool/check_ratchet_trend.dart`).
///
/// De vergelijking krijgt hier vaste brontekst in plaats van een werkkopie:
/// geen git, geen netwerk, geen afhankelijkheid van de stand van vandaag. Elk
/// blok wordt in twee richtingen getoetst — op een stand waar niets aan de hand
/// is, en op een geplante afwijking.
///
/// Eén groep aan het eind kijkt wél naar de echte bronbestanden. Niet om een
/// waarde te bevestigen (die verandert), maar om te bewaken dat dit instrument
/// de basislijnen nog kán vinden. Een meting die haar eigen meetpunt kwijt is,
/// meldt vrolijk nul.
void main() {
  group('regelcommentaar wegsnijden', () {
    test('commentaar verdwijnt, strings blijven heel', () {
      const bron = "const a = 'https://x/y'; // een, komma, in commentaar\n";
      final schoon = zonderRegelcommentaar(bron);
      expect(schoon, contains("'https://x/y'"));
      expect(schoon, isNot(contains('commentaar')));
    });

    test('een dubbele schuine streep binnen een string overleeft', () {
      // Zonder deze regel zou alles na de eerste // in een pad wegvallen en
      // telde de basislijn ineens één regel.
      const bron = "const s = {'a//b', 'c'};";
      expect(omvangUit(bron, 's'), 2);
    });
  });

  group('een getal uit de brontekst', () {
    test('een gewone constante', () {
      expect(getalUit('const int fooBaseline = 7;', 'fooBaseline'), 7);
    });

    test('commentaar met een ander getal telt niet mee', () {
      const bron = '// was ooit 99\nconst int fooBaseline = 7;';
      expect(getalUit(bron, 'fooBaseline'), 7);
    });

    test('een constante die er niet is, levert null', () {
      expect(getalUit('const int fooBaseline = 7;', 'barBaseline'), isNull);
    });
  });

  group('de omvang van een verzameling', () {
    test('leeg is nul', () {
      expect(omvangUit('const Map<String, int> b = {};', 'b'), 0);
    });

    test('één regel zonder afsluitende komma telt als één', () {
      expect(omvangUit("const Set<String> b = {'a'};", 'b'), 1);
    });

    test('meerdere regels mét afsluitende komma', () {
      const bron = '''
const Set<String> b = {
  'a',
  'b',
  'c',
};''';
      expect(omvangUit(bron, 'b'), 3);
    });

    test('commentaar met komma\'s blaast de telling niet op', () {
      // Dit is geen bedacht randgeval: uncoveredBaseline legt per regel uit
      // waarom een bestand er staat, en die uitleg zit vol komma's. Wie die
      // meetelt, leest een basislijn van 25 als 60.
      const bron = '''
const Set<String> b = {
  // PLATFORM: de webhelft, met een komma, en nog een komma
  'a',
  // GEEN UITVOERBARE REGELS: een kale gevel, verder niets
  'b',
};''';
      expect(omvangUit(bron, 'b'), 2);
    });

    test('geneste haken tellen niet als regel', () {
      const bron = '''
const Map<String, List<String>> b = {
  'a': ['x', 'y'],
  'b': ['z'],
};''';
      expect(omvangUit(bron, 'b'), 2);
    });

    test('de sleutels komen er in bronvolgorde uit', () {
      const bron = '''
const Map<String, String> b = {
  'lib/een.dart': 'reden',
  'lib/twee.dart': 'reden',
};''';
      expect(sleutelsUit(bron, 'b'), [
        'lib/een.dart',
        'reden',
        'lib/twee.dart',
        'reden',
      ]);
    });
  });

  group('een vlag uit de Makefile', () {
    test('de dekkingsvloer', () {
      const regel = 'dart run tool/coverage_summary.dart --min=80 --require';
      expect(vlagUit(regel, '--min'), 80);
    });

    test('een vlag die er niet staat', () {
      expect(vlagUit('dart run iets', '--min'), isNull);
    });
  });

  group('de vergelijking, met vaste brontekst', () {
    // Genoeg brontekst om elke basislijn uit de echte lijst te vinden. De
    // waarden zijn verzonnen; het gaat om de beweging.
    String conventies({
      required int katch,
      required int service,
      required int nosemgrep,
      int picker = 2,
      int klassen = 2,
    }) =>
        '''
const int catchUnderscoreBaseline = $katch;
const int rawColorBaseline = 0;
const int debugPrintBaseline = 0;
const int controlByteBaseline = 0;
const int serviceUiImportBaseline = $service;
const int modelUiImportBaseline = 0;
const Map<String, int> fileSizeBaseline = {};
const Map<String, int> classSizeBaseline = {
${List.generate(klassen, (i) => "  'lib/x.dart#Klasse\$i': 1200,").join('\n')}
};
const Map<String, String> filePickerPathBaseline = {
${List.generate(picker, (i) => "  'lib/een$i.dart': 'reden',").join('\n')}
};
const int nosemgrepBaseline = $nosemgrep;
''';

    const methodeLengte = 'const Map<String, int> methodLengthBaseline = {};';

    String dekking({required int ongedekt, required int bestandsvloer}) =>
        '''
const Set<String> uncoveredBaseline = {
${List.generate(ongedekt, (i) => "  'lib/a$i.dart',").join('\n')}
};
const int perFileFloorPercent = $bestandsvloer;
''';

    Map<String, String?> stand({
      required int katch,
      required int service,
      required int nosemgrep,
      int picker = 2,
      int klassen = 2,
      int vloer = 80,
      int ongedekt = 1,
      int bestandsvloer = 20,
      // Nul, zodat deze ratchet in de vergelijkingen hieronder meedoet als
      // "al af" en de tellingen daar over hun eigen onderwerp blijven gaan.
      int gemengd = 0,
      // Idem voor de wezenratchet uit check_l10n_orphans.dart.
      int wezen = 0,
    }) => {
      'tool/check_conventions.dart': conventies(
        katch: katch,
        service: service,
        nosemgrep: nosemgrep,
        picker: picker,
        klassen: klassen,
      ),
      'tool/check_method_length.dart': methodeLengte,
      'tool/coverage_summary.dart': dekking(
        ongedekt: ongedekt,
        bestandsvloer: bestandsvloer,
      ),
      'tool/check_comment_language.dart':
          'const int mixedCommentBaseline = $gemengd;',
      'tool/check_l10n_orphans.dart': 'const int orphanBaseline = $wezen;',
      'Makefile': 'coverage_summary.dart --min=$vloer --require-instrumented',
    };

    /// Twee momentopnames waartussen élke basislijn de goede kant op bewoog of
    /// al op nul stond. `nu: false` geeft het oudere beeld.
    Map<String, String?> alleenVooruit({required bool nu}) => stand(
      katch: 0,
      service: nu ? 2 : 6,
      nosemgrep: 0,
      picker: nu ? 1 : 3,
      klassen: nu ? 1 : 3,
      vloer: nu ? 82 : 80,
      ongedekt: nu ? 0 : 4,
      bestandsvloer: nu ? 25 : 20,
    );

    test('alles op nul of gekrompen: geen stilstand', () {
      final standen = vergelijk(
        alleenVooruit(nu: true),
        alleenVooruit(nu: false),
      );
      expect(standen.where((s) => s.onvindbaar), isEmpty);
      expect(standen.where((s) => s.stilstand), isEmpty);
      // Zes: service, picker, klassen, vloer, ongedekt en bestandsvloer —
      // precies de zes die `alleenVooruit` laat bewegen. Geteld en niet
      // afgeleid, want dit ís de bewering van deze test.
      expect(standen.where((s) => s.verbeterd).length, 6);
      expect(exitCodeVoor(standen), 0);
    });

    test('een basislijn die niet nul is en niet beweegt heet stilstand', () {
      final standen = vergelijk(
        stand(katch: 0, service: 4, nosemgrep: 1),
        stand(katch: 0, service: 4, nosemgrep: 1),
      );
      final stil = standen.where((s) => s.stilstand).map((s) => s.ratchet.naam);
      expect(
        stil,
        containsAll(['serviceUiImportBaseline', 'nosemgrepBaseline']),
      );
      // Nul is geen stilstand maar de eindstand: daar valt niets te winnen.
      expect(stil, isNot(contains('catchUnderscoreBaseline')));
      expect(stil, isNot(contains('rawColorBaseline')));
      expect(exitCodeVoor(standen), 1);
    });

    test('een dekkingsvloer die stilstaat telt wél mee', () {
      // Een vloer is nooit af: hij hoort te stijgen zolang er ruimte is.
      final standen = vergelijk(
        stand(katch: 0, service: 0, nosemgrep: 0, picker: 0),
        stand(katch: 0, service: 0, nosemgrep: 0, picker: 0),
      );
      final stil = standen.where((s) => s.stilstand).map((s) => s.ratchet.naam);
      expect(stil, contains('--min'));
      expect(stil, contains('perFileFloorPercent'));
    });

    test('groei wordt als de verkeerde kant op gemeld', () {
      final standen = vergelijk(
        stand(katch: 3, service: 4, nosemgrep: 1),
        stand(katch: 0, service: 4, nosemgrep: 1),
      );
      final gegroeid = standen.firstWhere(
        (s) => s.ratchet.naam == 'catchUnderscoreBaseline',
      );
      expect(gegroeid.verschil, 3);
      expect(gegroeid.verbeterd, isFalse);
    });

    test(
      'een verdwenen constante is een kapotte meting, geen goede uitslag',
      () {
        final kapot = stand(katch: 0, service: 4, nosemgrep: 1)
          ..['tool/check_conventions.dart'] = 'const int ietsAnders = 0;';
        final standen = vergelijk(
          kapot,
          stand(katch: 0, service: 4, nosemgrep: 1),
        );
        // Afgeleid, niet overgetypt: dit getal is het aantal ratchets dat in
        // check_conventions.dart woont, en dat verandert zodra er een
        // basislijn bijkomt. Een hardgecodeerde 9 maakte deze test rood op
        // werk dat er niets mee te maken had — precies de fout die
        // docs_claims_match_code_test elders bestrijdt.
        final inConventions = ratchets
            .where((r) => r.bestand == 'tool/check_conventions.dart')
            .length;
        expect(standen.where((s) => s.onvindbaar).length, inConventions);
        final tekst = rapport(
          standen: standen,
          dekking: const [],
          oudsteRegels: const [],
          ijkpunt: null,
          nu: DateTime(2026, 7, 22),
        ).join('\n');
        expect(tekst, contains('kapotte meting'));
        expect(exitCodeVoor(standen), 1);
      },
    );

    test('het rapport benoemt stilstand zonder er een fout van te maken', () {
      final tekst = rapport(
        standen: vergelijk(
          stand(katch: 0, service: 4, nosemgrep: 1),
          stand(katch: 0, service: 4, nosemgrep: 1),
        ),
        dekking: const [],
        oudsteRegels: const [],
        ijkpunt: Ijkpunt(
          commit: 'abcdef1234',
          datum: DateTime(2026, 4, 23),
          dagenTerug: 90,
        ),
        nu: DateTime(2026, 7, 22),
      ).join('\n');
      expect(tekst, contains('STIL'));
      expect(tekst, contains('comfortabel'));
      expect(tekst, contains('abcdef12'));
      expect(tekst, contains('90 dagen'));
    });

    test('het rapport zegt het ook als alles beweegt', () {
      final tekst = rapport(
        standen: vergelijk(alleenVooruit(nu: true), alleenVooruit(nu: false)),
        dekking: const [],
        oudsteRegels: const [],
        ijkpunt: null,
        nu: DateTime(2026, 7, 22),
      ).join('\n');
      expect(tekst, contains('geen enkele stond stil'));
      expect(tekst, contains('geen goedkeuring'));
    });
  });

  group('dekking per map', () {
    const verslag = '''
SF:lib/services/een.dart
LF:100
LH:90
end_of_record
SF:lib/services/twee.dart
LF:100
LH:70
end_of_record
SF:lib/widgets/drie.dart
LF:200
LH:20
end_of_record
''';

    test('de zwakste map staat bovenaan', () {
      final dekking = dekkingPerMap(verslag);
      expect(dekking.first.pad, 'lib/widgets');
      expect(dekking.first.percentage, closeTo(10, 0.01));
      expect(dekking.last.pad, 'lib/services');
      expect(dekking.last.percentage, closeTo(80, 0.01));
    });

    test('de bestanden per map worden geteld', () {
      final services = dekkingPerMap(
        verslag,
      ).firstWhere((d) => d.pad == 'lib/services');
      expect(services.bestanden, 2);
      expect(services.geraakt, 160);
      expect(services.gevonden, 200);
    });

    test('een diepere groepering splitst verder uit', () {
      const diep = '''
SF:lib/services/git/een.dart
LF:10
LH:1
end_of_record
SF:lib/services/cve/twee.dart
LF:10
LH:9
end_of_record
''';
      final dekking = dekkingPerMap(diep, diepte: 3);
      expect(dekking.map((d) => d.pad), [
        'lib/services/git',
        'lib/services/cve',
      ]);
    });

    test('het gemiddelde verbergt wat deze uitsplitsing laat zien', () {
      // 180 van 400 regels is 45% over de hele boom. Dat getal zegt niets over
      // de map die op 10% staat — precies de reden dat dit blok bestaat.
      final dekking = dekkingPerMap(verslag);
      final geraakt = dekking.fold(0, (som, d) => som + d.geraakt);
      final gevonden = dekking.fold(0, (som, d) => som + d.gevonden);
      expect(geraakt / gevonden * 100, closeTo(45, 0.01));
      expect(dekking.first.percentage, lessThan(15));
    });

    test('zonder verslag zegt het rapport dat er niet gemeten is', () {
      final tekst = rapport(
        standen: const [],
        dekking: const [],
        oudsteRegels: const [],
        ijkpunt: null,
        nu: DateTime(2026, 7, 22),
      ).join('\n');
      expect(tekst, contains('geen coverage/lcov.info'));
      expect(tekst, contains('iets\n    anders dan een goede uitslag'));
    });
  });

  group('de meting kent de echte basislijnen nog', () {
    test('elke gevolgde basislijn is in de echte bron te vinden', () {
      final bronnen = <String, String?>{
        for (final pad in ratchetBestanden)
          pad: File(pad).existsSync() ? File(pad).readAsStringSync() : null,
      };
      final kwijt = [
        for (final ratchet in ratchets)
          if (waardeUit(ratchet, bronnen[ratchet.bestand]) == null)
            ratchet.naam,
      ];
      expect(
        kwijt,
        isEmpty,
        reason:
            'deze basislijnen staan niet meer waar check_ratchet_trend.dart ze '
            'zoekt: ${kwijt.join(', ')}. Werk de lijst `ratchets` bij — een '
            'meting die haar meetpunt kwijt is, meldt vrolijk niets.',
      );
    });

    test('elke basislijn in tool/ wordt ook echt gevolgd', () {
      // De omgekeerde richting, en de belangrijkste: een nieuwe ratchet die
      // niemand aan deze lijst toevoegt, is een ratchet die stil kan blijven
      // staan zonder dat het rapport het ooit laat zien.
      final gevolgd = {for (final r in ratchets) r.naam};
      final gevonden = <String>{};
      for (final bestand in Directory('tool').listSync()) {
        if (bestand is! File || !bestand.path.endsWith('.dart')) continue;
        // Dit gereedschap zelf beschrijft de basislijnen, het heeft ze niet.
        if (bestand.path.endsWith('check_ratchet_trend.dart')) continue;
        for (final treffer in RegExp(
          r'^const\s+[\w<>,\s]+\s+(\w+Baseline)\s*=',
          multiLine: true,
        ).allMatches(bestand.readAsStringSync())) {
          gevonden.add(treffer.group(1)!);
        }
      }
      expect(gevonden, isNotEmpty, reason: 'geen enkele basislijn gevonden');
      expect(
        gevonden.difference(gevolgd),
        isEmpty,
        reason:
            'deze basislijnen staan in tool/ maar niet in de lijst `ratchets` '
            'van tool/check_ratchet_trend.dart, en bewegen dus onzichtbaar.',
      );
    });
  });
}
