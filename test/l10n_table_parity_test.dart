import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_l10n_table_parity.dart';

/// Toetst de gelijkheidspoort tussen de taaltabellen, in TWEE richtingen.
///
/// "Meldt niets als de tabellen gelijk zijn" is de helft die een kapotte poort
/// ook haalt: een analyse die stilvalt is altijd groen. Elke groep hieronder
/// heeft daarom een tegenhanger die een gat SLAAT in een mini-repo en eist dat
/// het gemeld wordt.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('l10n_parity'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Schrijft één taalbestand: per tabelnaam de sleutels met een nepvertaling.
  void giveLanguage(String language, Map<String, List<String>> tables) {
    final buffer = StringBuffer("part of '../app_localizations.dart';\n");
    tables.forEach((name, keys) {
      buffer.writeln('\nconst $name = {');
      for (final key in keys) {
        buffer.writeln("  '$key': '$key-$language',");
      }
      buffer.writeln('};');
    });
    final file = File('${root.path}/lib/l10n/translations/$language.dart');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(buffer.toString());
  }

  List<String> gapKeys() =>
      findParityGaps(root.path).map((g) => g.key).toList();

  group('gelijke tabellen', () {
    test('leveren geen enkele melding op', () {
      giveLanguage('nl', {
        '_stringsNl': ['save'],
      });
      giveLanguage('en', {
        '_stringsEn': ['save'],
        '_dutchSourceEn': ['Opslaan'],
        '_dutchSourceAddEn': ['Sluiten'],
      });
      giveLanguage('de', {
        '_stringsDe': ['save'],
        '_dutchSourceDe': ['Opslaan'],
        '_dutchSourceAddDe': ['Sluiten'],
      });
      expect(gapKeys(), isEmpty);
    });

    test('nl hoeft geen Nederlandse-brontabellen te hebben', () {
      // De brontaal beantwoordt `d()` zonder tabel. Zonder deze uitzondering
      // zou élke bronsleutel als "ontbreekt in nl" worden gemeld.
      giveLanguage('nl', {
        '_stringsNl': ['save'],
      });
      giveLanguage('en', {
        '_stringsEn': ['save'],
        '_dutchSourceEn': ['Opslaan'],
      });
      expect(gapKeys(), isEmpty);
    });

    test(
      'de knip tussen de basis- en de Add-tabel mag per taal verschillen',
      () {
        // `make add-l10n` schrijft in de Add-tabel; waar de knip ligt is
        // toeval van volgorde. De twee tabellen zijn één naamruimte, dus een
        // sleutel die in de ene taal in de basis staat en in de andere in de
        // toevoegingen is géén gat.
        giveLanguage('en', {
          '_dutchSourceEn': ['Opslaan', 'Sluiten'],
          '_dutchSourceAddEn': <String>[],
        });
        giveLanguage('de', {
          '_dutchSourceDe': ['Opslaan'],
          '_dutchSourceAddDe': ['Sluiten'],
        });
        expect(gapKeys(), isEmpty);
      },
    );
  });

  group('een geslagen gat', () {
    test('wordt gemeld als één taal een bronsleutel mist', () {
      giveLanguage('en', {
        '_dutchSourceEn': ['Opslaan', 'Sluiten'],
      });
      giveLanguage('de', {
        '_dutchSourceDe': ['Opslaan'],
      });

      final gaps = findParityGaps(root.path);
      expect(gaps.map((g) => g.key), ['Sluiten']);
      expect(gaps.single.family, dutchSourceFamily);
      expect(gaps.single.missingIn, ['de']);
      expect(gaps.single.presentIn, ['en']);
    });

    test('wordt gemeld als één taal een t()-sleutel mist', () {
      giveLanguage('nl', {
        '_stringsNl': ['save', 'close'],
      });
      giveLanguage('en', {
        '_stringsEn': ['save'],
      });

      final gaps = findParityGaps(root.path);
      expect(gaps.map((g) => g.key), ['close']);
      expect(gaps.single.family, keyedFamily);
      expect(gaps.single.missingIn, ['en']);
    });

    test('wordt gemeld als een sleutel nog maar in één taal staat', () {
      // Het restantgeval: niet vullen maar weghalen. De melding noemt daarom
      // ook de talen die hem wél hebben.
      giveLanguage('en', {
        '_dutchSourceEn': ['Opslaan'],
      });
      giveLanguage('de', {
        '_dutchSourceDe': ['Opslaan'],
      });
      giveLanguage('fr', {
        '_dutchSourceFr': ['Opslaan', 'Restant'],
      });

      final gaps = findParityGaps(root.path);
      expect(gaps.single.key, 'Restant');
      expect(gaps.single.presentIn, ['fr']);
      expect(gaps.single.missingIn, ['de', 'en']);
    });

    test('wordt gemeld als een niet-brontaal haar brontabellen mist', () {
      // Geen uitzondering: alleen nl mag zonder. Een taal zonder brontabel
      // mist élke bronsleutel en dat hoort te knallen.
      giveLanguage('en', {
        '_dutchSourceEn': ['Opslaan', 'Sluiten'],
      });
      giveLanguage('de', {'_stringsDe': <String>[]});
      expect(gapKeys(), ['Opslaan', 'Sluiten']);
    });
  });

  group('op de echte boom', () {
    test('dragen alle 32 taaltabellen dezelfde sleutels', () {
      final gaps = findParityGaps('.');
      expect(
        gaps.map((g) => '${g.family}: ${g.key} ontbreekt in ${g.missingIn}'),
        isEmpty,
        reason:
            'Vul het gat met de vertaling uit een taal die de sleutel wél '
            'heeft, of haal de sleutel overal weg als hij een restant is.',
      );
    });

    test('leest alle taalbestanden, niet alleen het eerste', () {
      // Een poort die per ongeluk maar één bestand inleest is óók leeg.
      final tables = translationTables('.');
      expect(tables.length, greaterThan(30));
      expect(tables['nl']?[keyedFamily], isNotEmpty);
      expect(tables['nl']?[dutchSourceFamily], isNull);
      expect(tables['de']?[dutchSourceFamily], isNotEmpty);
    });
  });
}
