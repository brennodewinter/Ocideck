import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bewaakt dat een vertaling ook werkelijk vertááld is.
///
/// `make l10n-check` toetst **dekking**: staat er een waarde bij deze sleutel?
/// Een Engelse zin in het Duitse bestand is voor die poort een ingevulde
/// waarde, en dat is precies het gat waar dit in kon blijven zitten: zes talen
/// droegen vijftien kwaliteitsmeldingen als onvertaald Engels, en het
/// kwaliteitspaneel zette die pal naast correct vertaalde meldingen (#677).
///
/// De regel hier is simpel en daarom betrouwbaar: **een waarde die letterlijk
/// gelijk is aan de Engelse vertaling van dezelfde sleutel, in een taal die
/// geen Engels is, is vrijwel altijd een niet-vertaalde string.**
///
/// Vrijwel — en de uitzondering is het hele ontwerp van deze test. Losse
/// woorden zijn massaal identiek zonder dat er iets mis is: `Logo`, `Design`,
/// `Version`, `Classification` in het Frans. Een naïeve gelijkheidstoets vindt
/// er 446 en heeft in 350 gevallen ongelijk; dat is geen poort maar ruis, en
/// ruis wordt weggeklikt. Daarom telt alleen wat **drie woorden of meer** is:
/// een hele zin die in twee talen identiek is, is geen toeval.
///
/// Wat die keuze kost, staat er eerlijk bij: een onvertaalde string van één of
/// twee woorden glipt hier doorheen. Dat is de prijs voor een poort die niet
/// liegt, en hij is te betalen — de fout die dit issue opleverde bestond uit
/// hele zinnen.
void main() {
  const allowed = <(String, String)>{
    // Een lettertypevoorbeeld. De pangram is het punt; vertalen zou hem breken.
    ('id', 'The quick brown fox jumps over the lazy dog.'),
    // Vakterm uit de CVSS-standaard, die geen Klingon-vorm heeft.
    ('tlh', 'CVSS 4.0 vector'),
    // Deense interfaceterm die letterlijk zo geleend is.
    ('da', 'Look and feel'),
  };

  test('geen enkele taal draagt een Engelse zin als vertaling', () {
    final dir = Directory('lib/l10n/translations');
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'geen vertaalbestanden gevonden');

    final english = _pairs(
      File('lib/l10n/translations/en.dart').readAsStringSync(),
    );
    expect(english, isNotEmpty, reason: 'en.dart leverde geen paren op');

    final problems = <String>[];
    for (final file in files) {
      final lang = file.uri.pathSegments.last.replaceAll('.dart', '');
      if (lang == 'en') continue;
      _pairs(file.readAsStringSync()).forEach((key, value) {
        if (english[key] != value) return;
        // Een leenwoord dat in het Nederlands al zo is.
        if (value == key) return;
        if (value.trim().split(RegExp(r'\s+')).length < 3) return;
        if (allowed.contains((lang, value))) return;
        problems.add('$lang: "$value"');
      });
    }

    expect(
      problems,
      isEmpty,
      reason:
          'deze waarden staan in het Engels in een niet-Engels vertaalbestand. '
          'Vertaal ze, of zet ze in `allowed` hierboven mét de reden — een '
          'pangram, een vakterm of een leenwoord:\n${problems.join('\n')}',
    );
  });

  group('de parser leest paren, ook gebroken (zelftoets)', () {
    test('een waarde met dubbele punt en komma is geen sleutel', () {
      const body = '''
final x = {
  'a': 'value: with, punctuation',
  'b': 'gewoon',
};
''';
      expect(_pairs(body), {'a': 'value: with, punctuation', 'b': 'gewoon'});
    });

    test('een ontsnapt aanhalingsteken breekt de sleutel niet', () {
      const body = r'''
final x = {
  'De voorbeelddia\'s': 'The sample slides',
};
''';
      expect(_pairs(body), {"De voorbeelddia's": 'The sample slides'});
    });

    test(
      'een paar dat de formatter over twee regels brak, komt heel terug',
      () {
        // De formatter breekt een lange regel na de dubbele punt, en juist de
        // lange waarden zijn de zinnen waar deze test over gaat. Werd zo'n paar
        // overgeslagen, dan keek de poort precies langs zijn eigen doelgroep.
        const body = '''
final x = {
  'kort': 'short',
  'een hele lange sleutel die niet meer past':
      'a very long value on its own line',
};
''';
        expect(_pairs(body), {
          'kort': 'short',
          'een hele lange sleutel die niet meer past':
              'a very long value on its own line',
        });
      },
    );
  });
}

/// Sleutel → waarde voor elk paar in [source].
///
/// Ook de paren die `dart format` na de dubbele punt over twee regels brak: de
/// witruimte tussen sleutel en waarde mag een regeleinde bevatten. Dat is geen
/// detail — juist de lange waarden worden gebroken, en dat zijn precies de
/// zinnen waar deze poort over gaat. Een parser die alleen enkelregelige paren
/// las, keek langs zijn eigen doelgroep heen.
Map<String, String> _pairs(String source) {
  final out = <String, String>{};
  final re = RegExp(
    r"^\s*'((?:[^'\\]|\\.)*)':\s*'((?:[^'\\]|\\.)*)',\s*$",
    multiLine: true,
  );
  for (final m in re.allMatches(source)) {
    out[_unescape(m.group(1)!)] = _unescape(m.group(2)!);
  }
  return out;
}

String _unescape(String literal) =>
    literal.replaceAll(r"\'", "'").replaceAll(r'\\', r'\');
