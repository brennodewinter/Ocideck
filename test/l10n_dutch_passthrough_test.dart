import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_l10n_dutch_passthrough.dart';

/// Toetst de doorlaatpoort in TWEE richtingen.
///
/// "Meldt niets" is de helft die een kapotte poort ook haalt: een analyse die
/// stilvalt is altijd groen. Elke groep hieronder heeft daarom een tegenhanger
/// die een Nederlandse zin PLANT in een mini-repo en eist dat hij gemeld wordt.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('l10n_passthrough'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Schrijft één taalbestand: per tabelnaam de paren zoals ze er staan.
  void giveLanguage(String language, Map<String, Map<String, String>> tables) {
    final buffer = StringBuffer("part of '../app_localizations.dart';\n");
    tables.forEach((name, pairs) {
      buffer.writeln('\nconst $name = {');
      pairs.forEach((key, value) {
        buffer.writeln("  '${_escape(key)}': '${_escape(value)}',");
      });
      buffer.writeln('};');
    });
    final file = File('${root.path}/lib/l10n/translations/$language.dart');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(buffer.toString());
  }

  group('een echte vertaling', () {
    test('levert geen enkele melding op', () {
      giveLanguage('de', {
        '_dutchSourceDe': {
          'Kies welke slides u wilt halen.':
              'Wählen Sie die gewünschten Folien.',
        },
      });
      expect(findDutchPassthroughs(root.path), isEmpty);
    });

    test('nl zelf telt nooit mee, ook al is de waarde gelijk aan de bron', () {
      // Voor de brontaal IS de waarde de bron. Zonder deze uitzondering zou
      // élke Nederlandse regel als doorlaat gelden.
      giveLanguage('nl', {
        '_stringsNl': {'saveButton': 'Sla dit bestand op'},
      });
      expect(findDutchPassthroughs(root.path), isEmpty);
    });

    test('een leenwoord uit loanKeys wordt niet gemeld', () {
      // Het geval waarvoor de uitzonderingenlijst bestaat: de bronzin bevat
      // geen vertaalbaar Nederlands woord, dus gelijkheid is hier het juiste
      // antwoord en geen vergeten vertaling.
      const loan = 'Sprint review / demo';
      expect(loanKeys, contains(loan));
      giveLanguage('tlh', {
        '_dutchSourceTlh': {loan: loan},
      });
      expect(findDutchPassthroughs(root.path), isEmpty);
    });

    test('een korte gelijke waarde blijft onder de drempel', () {
      // `Mermaid`, `Gantt`, `Enter`, `PDF`: één of twee woorden zijn massaal
      // identiek zonder dat er iets mis is. Bewust een valse negatief; zie de
      // kop van de poort.
      giveLanguage('fr', {
        '_dutchSourceFr': {'Mermaid': 'Mermaid', 'Logo px': 'Logo px'},
      });
      expect(findDutchPassthroughs(root.path), isEmpty);
    });
  });

  group('een geplante Nederlandse zin', () {
    test('wordt gemeld als hij als d()-vertaling doorgaat', () {
      const dutch = 'Kies welke slides u uit het project wilt halen.';
      giveLanguage('tlh', {
        '_dutchSourceTlh': {dutch: dutch, 'Verbinding geslaagd': 'yIchel wej'},
      });

      final found = findDutchPassthroughs(root.path);
      expect(found.map((f) => f.key), [dutch]);
      expect(found.single.language, 'tlh');
      expect(found.single.family, dutchSourceFamily);
    });

    test('wordt ook in de Add-tabel gemeld', () {
      // `make add-l10n` schrijft nieuwe bronstrings in `_dutchSourceAdd*`;
      // een poort die alleen de basistabel las, keek langs al het jonge werk.
      const dutch = 'Geen slides gevonden in dit project.';
      giveLanguage('tlh', {
        '_dutchSourceAddTlh': {dutch: dutch},
      });
      expect(findDutchPassthroughs(root.path).single.key, dutch);
    });

    test('wordt gemeld als hij als t()-vertaling doorgaat', () {
      // Daar is de sleutel een naam, dus de bron komt uit `_stringsNl`.
      giveLanguage('nl', {
        '_stringsNl': {'connectOk': 'De verbinding is tot stand gebracht'},
      });
      giveLanguage('tlh', {
        '_stringsTlh': {'connectOk': 'De verbinding is tot stand gebracht'},
      });

      final found = findDutchPassthroughs(root.path);
      expect(found.single.key, 'connectOk');
      expect(found.single.family, keyedFamily);
      expect(found.single.language, 'tlh');
    });

    test('wordt in elke taal apart geteld', () {
      // Het beeld uit #1526: hetzelfde blok staat in tientallen talen. Eén
      // melding per taal, want elke taal moet hem apart oplossen.
      const dutch = 'De connector is alleen beschikbaar op de desktop.';
      for (final language in ['da', 'el', 'tlh']) {
        giveLanguage(language, {
          '_dutchSource${language[0].toUpperCase()}${language.substring(1)}': {
            dutch: dutch,
          },
        });
      }
      expect(findDutchPassthroughs(root.path).map((f) => f.language), [
        'da',
        'el',
        'tlh',
      ]);
    });
  });

  group('de zeef zelf', () {
    test('telt woorden over regeleinden en dubbele spaties heen', () {
      expect(wordCount('een  zin\nmet vier woorden'), 5);
      expect(wordCount('  Mermaid  '), 1);
      expect(wordCount(''), 0);
    });

    test('elke sleutel in loanKeys draagt geen vertaalbaar Nederlands', () {
      // Geen automatische toets — wel een grendel op de vorm: de lijst gaat
      // over SLEUTELS, niet over talen. Een paar als ('tlh', '…') hoort hier
      // niet in en zou de volgende fout in die taal toedekken.
      expect(loanKeys, isNotEmpty);
      for (final key in loanKeys) {
        expect(key.trim(), key, reason: 'sleutel met losse witruimte: "$key"');
      }
    });
  });

  group('op de echte boom', () {
    test('leest alle taalbestanden, niet alleen het eerste', () {
      // Een poort die per ongeluk maar één bestand inleest is óók leeg.
      final tables = translationEntries('.');
      expect(tables.length, greaterThan(30));
      expect(tables['nl']?[keyedFamily], isNotEmpty);
      expect(tables['tlh']?[dutchSourceFamily], isNotEmpty);
    });

    test('blijft op of onder de basislijn', () {
      final found = findDutchPassthroughs('.');
      expect(
        found.length,
        lessThanOrEqualTo(passthroughBaseline),
        reason:
            'Er is een taal of een blok bijgekomen dat de Nederlandse bron '
            'letterlijk doorlaat. Vertaal het, of zet de sleutel in loanKeys '
            'als er niets aan te vertalen valt — niet de basislijn omhoog.',
      );
    });
  });
}

String _escape(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
