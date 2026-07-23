import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';

/// Elk diatype-label moet in élke taal een eigen vertaling hebben.
///
/// Dit ontbrak, en het kostte precies één label. `SlideType.quote` droeg als
/// bronsleutel het Engelse `'Quote'` terwijl alle drieëntwintig andere labels
/// Nederlands zijn. Vijfentwintig talen hadden er toevallig wél een vertaling
/// voor, het Duits niet — dus stond er in de Duitse diatypekiezer "Quote"
/// tussen "Abschnittsüberschrift" en "Tabelle" (#646).
///
/// Dat is de stille soort fout: de tekst verschijnt gewoon, alleen in de
/// verkeerde taal, en geen enkele poort keek ernaar. De vertaaldekking wordt
/// per *sleutel* bewaakt, niet per *gebruik* — een sleutel die nergens door
/// `d()` heen komt valt dus buiten die controle, en een sleutel die wel door
/// `d()` gaat maar in de brontaal Engels is, ziet er voor die controle uit als
/// een geldige bronstring.
void main() {
  test('elk diatype-label is in elke taal vertaald', () {
    final ontbreekt = <String>[];
    for (final entry in slideTypeMeta.entries) {
      final label = entry.value.label;
      for (final code in AppLocalizations.languageNames.keys) {
        if (code == 'nl') continue; // de brontaal
        if (!AppLocalizations.hasDirectDutchSourceTranslation(code, label)) {
          ontbreekt.add('${entry.key.name}: "$label" niet vertaald in $code');
        }
      }
    }
    expect(
      ontbreekt,
      isEmpty,
      reason:
          'Een label dat onvertaald blijft verschijnt in de brontaal tussen '
          'vertaalde labels. Voeg de vertaling toe met `make add-l10n`, of — '
          'als de bronsleutel Engels is — maak er de Nederlandse van, want die '
          'draagt de 31 vertalingen al.\n${ontbreekt.join('\n')}',
    );
  });
}
