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
/// ruis wordt weggeklikt. Daarom is er een woorddrempel: onder [minimumWords]
/// woorden telt gelijkheid niet mee.
///
/// ── Waarom die drempel van drie naar TWEE ging (#1534) ──────────────────────
///
/// Hij stond op drie toen deze poort de enige van zijn soort was. Inmiddels
/// staan er twee poorten naast: `check-l10n-parity` (staat elke sleutel in elke
/// taal?) en `check-l10n-passthrough` (draagt een taal de NEDERLANDSE bron
/// letterlijk?). Die vangen een deel van de ruis nu elders af, dus is er
/// opnieuw gemeten op de boom van #1534 — geteld op unieke (sleutel, waarde),
/// niet op regels, want één onvertaalde string telt in dertig talen mee:
///
///   drempel 1 → 175 unieke waarden, 851 regels — onbruikbaar, vrijwel alles
///               is `Logo`, `Audio`, `Status`, `OK`;
///   drempel 2 →  38 unieke waarden, 350 regels;
///   drempel 3 →   3 unieke waarden — de drie in [allowed] hieronder.
///
/// Van die 38 bij drempel twee waren er **22 echt onvertaald** en 16 een echt
/// leenwoord of cognaat. Dat is een verhouding van bijna 60% raak, en 22
/// bronstrings zijn op te ruimen — dat is gebeurd; ze zijn vertaald. De 16
/// resterende staan hieronder in [allowed], elk met zijn reden.
///
/// Wat die verlaging goedkoop maakt en niet duur, is de VORM van de
/// uitzondering hier: `allowed` gaat per (taal, waarde). Een Franse `Image 1`
/// vrijstellen zegt niets over het Grieks, waar `Image 1` wél fout zou zijn.
/// De zusterpoort in tool/check_l10n_dutch_passthrough.dart kan dat niet — daar
/// gaat de uitzondering per sleutel en dekt ze meteen alle 31 talen — en dáárom
/// blijft de drempel dáár op drie staan. Zie de kop van dat bestand voor die
/// meting.
///
/// Wat de drempel nog steeds kost, staat er eerlijk bij: een onvertaalde string
/// van één woord glipt hier doorheen. Dat is de prijs voor een poort die niet
/// liegt.
void main() {
  const allowed = <(String, String)>{
    // Een lettertypevoorbeeld. De pangram is het punt; vertalen zou hem breken.
    ('id', 'The quick brown fox jumps over the lazy dog.'),
    // Vakterm uit de CVSS-standaard, die geen Klingon-vorm heeft.
    ('tlh', 'CVSS 4.0 vector'),
    // Klingon heeft geen vakwoord voor paginaopmaak of marges; de melding
    // over ongeldige geometry (#1681) staat er in het Engels.
    (
      'tlh',
      'The page setup in this document contains invalid values and was ignored. Your settings are used instead.',
    ),
    // Klingon heeft geen gangbare vertaling voor deze conflictmelding.
    ('tlh', 'The file has been modified by another program.'),
    // Klingon heeft geen woord voor "presentaties" of "server" in deze
    // context; de welkomstscherm-sectie staat er in het Engels (#1986).
    ('tlh', 'Presentations on this server'),
    // Deense interfaceterm die letterlijk zo geleend is.
    ('da', 'Look and feel'),

    // ── Cognaten: het Engelse woord ÍS het woord in deze taal ───────────────
    //
    // Hieronder staat geen enkele vrijstelling omdat vertalen lastig was. Elk
    // paar is nagelopen tegen wat de taal elders in ditzelfde bestand doet.
    //
    // `Link` is het gewone woord in het Deens, Duits, Zwitserduits en Estisch;
    // wat er verder in staat is een plaatshouder en aanhalingstekens.
    ('da', 'Link "{tekst}"'),
    ('de', 'Link "{tekst}"'),
    ('gsw', 'Link "{tekst}"'),
    ('et', 'Link "{tekst}"'),
    // `System` is Deens en Zweeds; `monospace` is in elke taal de vakterm.
    ('da', 'System (monospace)'),
    ('sv', 'System (monospace)'),
    // `Branch` is de Duitse git-term, en `optional` is gewoon Duits.
    ('de', 'Branch (optional)'),
    ('gsw', 'Branch (optional)'),
    // Het Deens zegt zelf `Multiple choice`; de losse sleutel `Meerkeuze` doet
    // dat in ditzelfde bestand ook. `Stop` en `Top` zijn eveneens Deens — vgl.
    // `Stoppen` → `Stop` een paar duizend regels hoger.
    ('da', 'Multiple choice'),
    ('da', 'Stop (Esc)'),
    ('da', 'Top (mm)'),
    // Frans. `fraction`, `confirmation`, `reproduction`, `image` en `images`
    // zijn stuk voor stuk Franse woorden; er valt niets aan te vertalen.
    ('fr', 'Fraction p'),
    ('fr', 'Confirmation (reproduction)'),
    ('fr', '{n} image'),
    ('fr', '{n} images'),
    ('fr', 'Image 1'),
    ('fr', 'Image 2'),
    // Latijn. `e.g.` is de afkorting van *exempli gratia* en dus Latijn; het
    // Engels heeft hem geleend, niet andersom. Wat erachter staat is een
    // eigennaam, een datum of een versienummer.
    ('la', 'E.g. Vigilis'),
    ('la', 'E.g. 2026-05-30'),
    ('la', 'e.g. 2024'),
    ('la', 'E.g. 1.0'),
  };

  /// Vanaf hoeveel woorden een gelijke waarde als onvertaald telt.
  ///
  /// Zie de kop van dit bestand voor de meting achter deze twee.
  const minimumWords = 2;

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
        if (value.trim().split(RegExp(r'\s+')).length < minimumWords) return;
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

    test('een sleutel in dubbele quotes komt mee', () {
      // Dit is de vorm die `dart format` écht schrijft zodra er een apostrof
      // in staat — niet de ontsnapte variant hierboven. Zolang deze regel niet
      // gelezen werd, was `"dia's geïmporteerd.": 'slides imported.'` in
      // dertig talen onzichtbaar voor de poort die er nu net over gaat.
      const body = '''
final x = {
  "dia's geïmporteerd.": 'slides imported.',
  'zonder apostrof': "een waarde met 'aanhaling'",
};
''';
      expect(_pairs(body), {
        "dia's geïmporteerd.": 'slides imported.',
        'zonder apostrof': "een waarde met 'aanhaling'",
      });
    });
  });
}

/// Eén Dart-stringliteral: met enkele óf met dubbele aanhalingstekens.
const _literal = r"""('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""";

/// Sleutel → waarde voor elk paar in [source].
///
/// Ook de paren die `dart format` na de dubbele punt over twee regels brak: de
/// witruimte tussen sleutel en waarde mag een regeleinde bevatten. Dat is geen
/// detail — juist de lange waarden worden gebroken, en dat zijn precies de
/// zinnen waar deze poort over gaat. Een parser die alleen enkelregelige paren
/// las, keek langs zijn eigen doelgroep heen.
///
/// En ook de paren die `dart format` in DUBBELE aanhalingstekens zette. Dat
/// doet hij zodra de string zelf een apostrof draagt en geen dubbele quote:
/// `"dia's geïmporteerd."`. De zelftoets hieronder dacht dat af te dekken met
/// `'De voorbeelddia\'s'`, maar díe vorm schrijft de formatter juist nooit —
/// hij normaliseert hem weg naar de dubbele quote. Gevolg: elke sleutel met
/// een apostrof was voor deze poort onzichtbaar, en dat is in het Nederlands
/// geen zeldzame vorm (`dia's`, `'s ochtends`).
Map<String, String> _pairs(String source) {
  final out = <String, String>{};
  final re = RegExp('^\\s*$_literal:\\s*$_literal,\\s*\$', multiLine: true);
  for (final m in re.allMatches(source)) {
    out[_unescape(m.group(1)!)] = _unescape(m.group(2)!);
  }
  return out;
}

/// De inhoud van een Dart-stringliteral [literal], quotes eraf.
String _unescape(String literal) => literal
    .substring(1, literal.length - 1)
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\\', r'\');
