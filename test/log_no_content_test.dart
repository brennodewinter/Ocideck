// Een logregel draagt nooit de inhoud van een deck of een bestand.
//
// De regel staat in de kop van `lib/utils/log.dart`: "Pass only an operation
// description and the caught error object — never deck or file *contents*,
// which can be personal data." Er stond alleen niets op die regel.
//
// En dat was te merken. `file_service_open.dart` schreef tot vijf wérkelijke
// celwaarden uit een grafiek-CSV in de waarschuwing. Een grafiekbestand kan een
// omzet per klant of een uitslag per persoon bevatten, en juist de cel die
// "geen getal" is, is vaak de tekstkolom ernaast — een naam dus. Het logboek
// gaat naar de VM-service en naar elke schermafdruk van DevTools.
//
// Wat deze test kan: de vórm herkennen waarmee inhoud in een melding belandt —
// een verzameling die wordt samengevoegd, afgekapt of uitgesneden. Wat hij niet
// kan: een losse variabele beoordelen die toevallig celinhoud bevat. Dat is een
// echte grens; deze test vangt de shapes die het in de praktijk deden.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Aanroepen waarvan de méldingstekst inhoud kan meedragen.
///
/// Alleen het eerste argument telt. Het tweede is het foutobject, en dat gaat
/// door de sanitizer in `log.dart` heen.
const List<String> _inhoudsvormen = [
  '.join(',
  '.take(',
  '.substring(',
  '.values',
  '.entries',
];

/// Het eerste argument van een aanroep die op [open] begint, of `null` wanneer
/// de haakjes niet sluiten.
String? _eersteArgument(String bron, int open) {
  var diepte = 0;
  for (var i = open; i < bron.length; i++) {
    final c = bron[i];
    if (c == '(' || c == '[' || c == '{') diepte++;
    if (c == ')' || c == ']' || c == '}') {
      diepte--;
      if (diepte == 0) return bron.substring(open + 1, i);
    }
    if (c == ',' && diepte == 1) return bron.substring(open + 1, i);
  }
  return null;
}

void main() {
  test('geen logmelding draagt de inhoud van een deck of een bestand', () {
    final lib = Directory('${Directory.current.path}/lib');
    expect(lib.existsSync(), isTrue, reason: lib.path);

    final aanroep = RegExp(r'\blog(?:Warning|Error)\s*\(');
    final overtredingen = <String>[];
    var gezien = 0;

    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final bron = f.readAsStringSync();
      for (final m in aanroep.allMatches(bron)) {
        gezien++;
        final arg = _eersteArgument(bron, m.end - 1);
        if (arg == null) continue;
        for (final vorm in _inhoudsvormen) {
          if (!arg.contains(vorm)) continue;
          final regel = '\n'.allMatches(bron.substring(0, m.start)).length + 1;
          overtredingen.add(
            '${f.path.split('/lib/').last}:$regel gebruikt "$vorm" in de '
            'meldingstekst',
          );
        }
      }
    }

    // Zonder ondergrens laat een hernoemde helper deze test groen door er niets
    // meer in te stoppen.
    expect(gezien, greaterThan(50), reason: 'te weinig logaanroepen gevonden');
    expect(
      overtredingen..sort(),
      isEmpty,
      reason:
          'een logmelding hoort te zeggen wát er misging en hoe vaak, nooit '
          'wélke waarden het waren (zie de kop van lib/utils/log.dart). Log het '
          'aantal, en laat de gebruiker de waarden in zijn eigen bestand zien.',
    );
  });
}
