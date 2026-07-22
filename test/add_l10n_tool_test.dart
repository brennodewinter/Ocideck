import 'package:flutter_test/flutter_test.dart';

import '../tool/add_l10n.dart';

/// De inschuifhulp van `tool/add_l10n.dart` — het gereedschap dat een nieuwe
/// `d('…')`-bronstring in alle 31 taalbestanden zet.
///
/// Regressie: het schoof in ná de REGEL waarop de overlay-declaratie begint. Dat
/// gaat goed zolang de map over meerdere regels loopt, maar een nog lege overlay
/// staat op één regel (`const _dutchSourceAddTr = <String, String>{};`, zoals
/// Turks die had). De nieuwe sleutel belandde dan ónder de sluitende `};` —
/// buiten elke declaratie — en het taalbestand parseerde niet meer. Het
/// gereedschap schrijft vóór het opmaakt, dus die kapotte versie bleef op schijf
/// achter en moest met de hand teruggedraaid.
void main() {
  const anchor = 'const _dutchSourceAddTr = ';
  const entry = "  'Nieuw': 'Yeni',";

  test(
    'een lege overlay op één regel krijgt de sleutel binnen de accolades',
    () {
      const source =
          'const _base = <String, String>{};\n\n'
          'const _dutchSourceAddTr = <String, String>{};\n';

      final out = withOverlayEntries(source, anchor, const [entry])!;

      // De sleutel staat ná de openende accolade en vóór de sluitende.
      final open = out.indexOf('{', out.indexOf(anchor));
      final close = out.indexOf('};', open);
      final at = out.indexOf(entry);
      expect(at, greaterThan(open));
      expect(at, lessThan(close));
      expect(out, contains("<String, String>{\n$entry};"));
    },
  );

  test('een gevulde overlay krijgt de sleutel bovenaan, zonder lege regel', () {
    const source =
        'const _dutchSourceAddTr = <String, String>{\n'
        "  'Oud': 'Eski',\n"
        '};\n';

    final out = withOverlayEntries(source, anchor, const [entry])!;

    expect(out, contains("{\n$entry\n  'Oud': 'Eski',\n};"));
    // Geen dubbele lege regel — het bestand blijft opmaak-schoon.
    expect(out, isNot(contains('\n\n')));
  });

  test('meerdere sleutels komen in volgorde binnen', () {
    const source = 'const _dutchSourceAddTr = <String, String>{};\n';

    final out = withOverlayEntries(source, anchor, const [
      "  'A': 'A1',",
      "  'B': 'B1',",
    ])!;

    expect(out.indexOf("'A'"), lessThan(out.indexOf("'B'")));
    expect(out, contains("{\n  'A': 'A1',\n  'B': 'B1',};"));
  });

  test('een ontbrekende overlay geeft null in plaats van rommel', () {
    expect(
      withOverlayEntries('const iets = 1;\n', anchor, const [entry]),
      isNull,
    );
  });

  test('zonder accolade na het anker geeft het ook null', () {
    expect(
      withOverlayEntries('const _dutchSourceAddTr = ', anchor, const [entry]),
      isNull,
    );
  });

  // ── dartStr ────────────────────────────────────────────────────────────────
  //
  // Tweede gebrek in hetzelfde gereedschap, van dezelfde stille soort: het
  // escapen kende alleen `\` en `'`. Een bronstring met een echt regeleinde —
  // 'Selecteer een\nafbeelding', de toestemmingsteksten — kwam als de
  // regeleinde-BYTE in een enkelquote-literal terecht. Dart parseert dat niet,
  // dus viel de opmaakstap om en bleef de kapotte overlay op schijf staan. De
  // omweg die iemand toen koos, `\n` met de hand in de spec, maakte het
  // erger: de backslash werd geëscapet tot `\\n` en de lezer kreeg de twee
  // tekens backslash-n te zien in plaats van een regelovergang.

  test('een echt regeleinde wordt de escape \\n, niet de byte zelf', () {
    expect(
      dartStr('Selecteer een\nafbeelding'),
      r"'Selecteer een\nafbeelding'",
    );
    expect(dartStr('Kop\n\nTekst'), r"'Kop\n\nTekst'");
    expect(dartStr('a\tb\rc'), r"'a\tb\rc'");
  });

  test('een backslash-n die al tekst was blijft twee tekens', () {
    // Andersom moet ook kloppen: een bronstring die letterlijk een backslash
    // en een n bevat mag geen regelovergang worden.
    expect(dartStr(r'pad\naam'), r"'pad\\naam'");
  });

  test('aanhalingsteken en dollar worden geëscapet', () {
    // Een niet-geëscapete `$` begint een interpolatie: compileerfout, of erger,
    // een string die iets anders zegt.
    expect(dartStr("video's"), r"'video\'s'");
    expect(dartStr(r'kost $5'), r"'kost \$5'");
  });

  test('een gewone string blijft ongemoeid', () {
    expect(dartStr('Presentatietitel'), "'Presentatietitel'");
  });

  test('overlayAnchor volgt de naamgeving in de taalbestanden', () {
    expect(overlayAnchor('tr'), 'const _dutchSourceAddTr = ');
    expect(overlayAnchor('gsw'), 'const _dutchSourceAddGsw = ');
  });

  group('dutchSourceRegion', () {
    // Regressie: de dubbeltest van het gereedschap keek het HELE bestand door.
    // De `t()`-map `_strings<Lang>` staat daar ook in en heeft een eigen
    // sleutelruimte — `t('slides')` en `d('slides')` zijn twee verschillende
    // dingen. Een bronstring die toevallig zo heet als een bestaande t()-sleutel
    // werd daardoor in alle 31 talen overgeslagen, en `make l10n-check` bleef
    // rood zonder dat `make add-l10n` er nog iets aan kon doen.
    const source =
        'const _stringsTr = {\n'
        "  'slides': 'slayt',\n"
        '};\n\n'
        'const _dutchSourceTr = {\n'
        "  'Opslaan': 'Kaydet',\n"
        '};\n\n'
        'const _dutchSourceAddTr = <String, String>{\n'
        "  'Toch opslaan': 'Yine de kaydet',\n"
        '};\n';

    test('laat de t()-map buiten beeld', () {
      expect(dutchSourceRegion(source, 'tr'), isNot(contains('_stringsTr')));
    });

    test('houdt beide Nederlandse bronmappen binnen beeld', () {
      final region = dutchSourceRegion(source, 'tr');
      expect(region, contains("'Opslaan':"));
      expect(region, contains("'Toch opslaan':"));
    });

    test('een t()-sleutel telt niet als bestaande bronvertaling', () {
      expect(dutchSourceRegion(source, 'tr'), isNot(contains("'slides':")));
    });

    test('zonder bronmap valt het terug op het hele bestand', () {
      // Liever te veel overslaan dan een dubbele sleutel schrijven.
      const zonder = "const _stringsTr = {\n  'slides': 'slayt',\n};\n";
      expect(dutchSourceRegion(zonder, 'tr'), zonder);
    });
  });
}
