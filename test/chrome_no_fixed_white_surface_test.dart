import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Geen vast wit *oppervlak* in de interface-chrome.
///
/// De chrome (editors, panelen, dialogen, de lezer) volgt het app-thema. Een
/// kaart die zich vast op `Colors.white` schildert wordt in donkere modus een
/// wit blok in een verder donkere omgeving — en de tekst erop is vrijwel altijd
/// mode-afhankelijk (licht in donkere modus), dus die verdwijnt: de meterkaart
/// in de cockpiteditor stond op 1,53:1, een tegel in het documentatiezoeken op
/// 1,30:1 (#825). Dezelfde klasse als de opslagkaart (#821) en het notitieveld.
///
/// Dit is een *oppervlak*, niet een label. Een wit label op een gekleurde
/// vulling is prima (het label draagt daar het contrast) en valt hier buiten:
/// de toets kijkt alleen naar `color:` binnen een `BoxDecoration`/`Material`/
/// `Container`/`DecoratedBox`, niet naar tekst- of randkleuren.
///
/// Uitzondering: een schakelaar-knop is per conventie een licht schijfje op zijn
/// gekleurde spoor — dat is een affordance, geen kaart. Die staat op de
/// allowlist, met de reden erbij.
void main() {
  test('geen vast wit oppervlak in editors/panels/dialogs/reader', () {
    final white = RegExp(
      r'\bcolor:\s*(?:Colors\.white|const Color\(0xFFFFFFFF\)|Color\(0xFFFFFFFF\))\s*,',
    );

    // Bestanden met een bewust wit oppervlak. Per plek de reden.
    const allowlist = <String>{
      // De duim van de aangepaste schakelaar in de vind-en-vervang-balk: een
      // licht schijfje op zijn gekleurde spoor, geen kaart. Een schakelaar-duim
      // is per Material-conventie licht in beide modi.
      'lib/widgets/editors/markdown_deck_editor.dart',
    };

    final dirs = [
      'lib/widgets/editors',
      'lib/widgets/panels',
      'lib/widgets/dialogs',
      'lib/widgets/shell',
      'lib/widgets/reader',
    ];

    final overtreders = <String>[];
    for (final dir in dirs) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        if (allowlist.any(rel.endsWith)) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!white.hasMatch(lines[i])) continue;
          // Alleen een oppervlak-vulling staat als `color:` áán het begin van
          // zijn eigen regel. Een randkleur begint met `border:`, en een
          // icoon-/tekstkleur staat achter `Icon(`/`Text(` op diezelfde regel
          // (`const Icon(..., color: Colors.white, ...)`). Zo vallen die er
          // vanzelf buiten, zonder een lijst uitzonderingen.
          if (!lines[i].trimLeft().startsWith('color:')) continue;
          // Alleen tellen als de kleur een oppervlak vult. Kijk terug over de
          // vijf voorafgaande *codelijnen* — commentaar overgeslagen, zodat een
          // lange toelichting tussen `BoxDecoration(` en `color:` het oppervlak
          // niet uit beeld duwt (dat was precies het gat waardoor de rood-toets
          // eerst groen bleef).
          final codeBefore = <String>[];
          for (var j = i - 1; j >= 0 && codeBefore.length < 5; j--) {
            final t = lines[j].trimLeft();
            if (t.isEmpty || t.startsWith('//')) continue;
            codeBefore.add(lines[j]);
          }
          final context = codeBefore.join(' ');
          final isSurface =
              context.contains('BoxDecoration(') ||
              context.contains('DecoratedBox(') ||
              context.contains('Material(') ||
              context.contains('Container(');
          if (!isSurface) continue;
          overtreders.add('$rel:${i + 1}');
        }
      }
    }

    expect(
      overtreders,
      isEmpty,
      reason:
          'Een vast wit oppervlak in de chrome wordt in donkere modus een wit '
          'blok, en de mode-afhankelijke tekst erop verdwijnt. Gebruik '
          '`AppTheme.paper` (donker in donkere modus). Is het bewust een '
          'affordance (een schakelaar-knop), zet het bestand dan op de '
          'allowlist mét reden:\n${overtreders.join('\n')}',
    );
  });
}
