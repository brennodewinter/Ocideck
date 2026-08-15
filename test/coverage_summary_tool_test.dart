import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/coverage_summary.dart';

/// De omgekeerde ratchet van `tool/coverage_summary.dart`: welke bestanden mogen
/// `uncoveredBaseline` verlaten?
///
/// Het instrument krijgt hier vaste tellingen in plaats van een echt
/// lcov-rapport — geen testrun, geen werkkopie, geen afhankelijkheid van de
/// dekking van vandaag. Elk geval wordt in twee richtingen getoetst: een stand
/// waarin het advies klopt, en een stand waarin het advies de poort zou breken.
///
/// De aanleiding is dat tweede geval. De tip keek alleen of een bestand in het
/// rapport stond, niet of het genoeg van zichzelf draaide. Daardoor adviseerde
/// hij `meeting_media_core_webrtc.dart` te schrappen — geïnstrumenteerd via een
/// preflight-tegel, maar op 0 van 9 regels. Wie dat advies opvolgde, liet de
/// per-bestandsvloer meteen vallen, want die zondert baseline-bestanden juist
/// uit.
void main() {
  ({String path, int hit, int found}) telling(
    String path,
    int hit,
    int found,
  ) => (path: path, hit: hit, found: found);

  group('een baseline-bestand dat mag vertrekken', () {
    test('ruim boven de vloer komt in de tip', () {
      final verdict = classifyBaselined(
        baseline: {'lib/a.dart'},
        tallies: {'lib/a.dart': telling('lib/a.dart', 65, 65)},
      );

      expect(verdict.leavers, ['lib/a.dart (65/65)']);
      expect(verdict.tooThin, isEmpty);
    });

    test('precies op de vloer telt als gehaald, niet als net-niet', () {
      // 34 van 100 is exact perFileFloorPercent; de vloer faalt pas eronder,
      // dus dit bestand overleeft buiten de lijst en mag weg.
      final verdict = classifyBaselined(
        baseline: {'lib/a.dart'},
        tallies: {'lib/a.dart': telling('lib/a.dart', 34, 100)},
      );

      expect(verdict.leavers, ['lib/a.dart (34/100)']);
      expect(verdict.tooThin, isEmpty);
    });
  });

  group('een baseline-bestand dat moet blijven', () {
    test('geïnstrumenteerd maar op nul regels wordt niet aangeraden', () {
      final verdict = classifyBaselined(
        baseline: {'lib/meetings/meeting_media_core_webrtc.dart'},
        tallies: {
          'lib/meetings/meeting_media_core_webrtc.dart': telling(
            'lib/meetings/meeting_media_core_webrtc.dart',
            0,
            9,
          ),
        },
      );

      expect(verdict.leavers, isEmpty);
      expect(verdict.tooThin, [
        'lib/meetings/meeting_media_core_webrtc.dart (0/9)',
      ]);
    });

    test('één regel onder de vloer valt nog aan de verkeerde kant', () {
      final verdict = classifyBaselined(
        baseline: {'lib/a.dart'},
        tallies: {'lib/a.dart': telling('lib/a.dart', 33, 100)},
      );

      expect(verdict.leavers, isEmpty);
      expect(verdict.tooThin, ['lib/a.dart (33/100)']);
    });
  });

  group('een baseline-bestand zonder rapportregel', () {
    test('wordt in geen van beide lijsten genoemd', () {
      // Geen enkele test importeert het, of het heeft geen uitvoerbare regel.
      // In beide gevallen staat de reden in de lijst nog overeind en valt er
      // niets te adviseren.
      final verdict = classifyBaselined(
        baseline: {'lib/theme/presenter_palette.dart'},
        tallies: const {},
      );

      expect(verdict.leavers, isEmpty);
      expect(verdict.tooThin, isEmpty);
    });
  });

  group('meerdere bestanden tegelijk', () {
    test('elk bestand landt in zijn eigen lijst, op alfabetische volgorde', () {
      final verdict = classifyBaselined(
        baseline: {'lib/z.dart', 'lib/a.dart', 'lib/m.dart', 'lib/weg.dart'},
        tallies: {
          'lib/z.dart': telling('lib/z.dart', 10, 10),
          'lib/a.dart': telling('lib/a.dart', 1, 10),
          'lib/m.dart': telling('lib/m.dart', 9, 10),
          // 'lib/weg.dart' heeft geen rapportregel.
        },
      );

      expect(verdict.leavers, ['lib/m.dart (9/10)', 'lib/z.dart (10/10)']);
      expect(verdict.tooThin, ['lib/a.dart (1/10)']);
    });
  });

  group('de lijst zelf', () {
    test('noemt geen bestand dat niet meer bestaat', () {
      // Een pad dat wegverhuist blijft anders stil in de lijst staan en dekt
      // dan niets meer af — precies het soort regel dat de volgende lezer voor
      // een bewuste uitzondering aanziet.
      for (final path in uncoveredBaseline) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path staat in uncoveredBaseline maar bestaat niet meer',
        );
      }
    });
  });
}
