import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/export_progress_text.dart';

/// De voortgangsregel van het exportvenster.
///
/// Deze toets bestaat omdat #714 hier zat en niemand erlangs kwam: de functie
/// was een private methode op de dialoogstate, en alle exporttoetsen roepen de
/// rasteraar aan zónder voortgangs-callback. De fout was pas zichtbaar door de
/// héle dialoog aan te sturen — een dure toets voor een regel tekstkeuze.
/// Losgetrokken is de grens hier in milliseconden te bewaken.
void main() {
  const l10n = AppLocalizations(Locale('nl'));

  group('total == 0 — de grens waar #714 op omviel', () {
    // `(done + 1).clamp(1, 0)` gooit ArgumentError(1), en dat is letterlijk de
    // tekst die de gebruiker kreeg: "Invalid argument(s): 1". Een deck zonder
    // ook maar één afbeelding meldt precache met nul.
    for (final phase in const [
      'precache',
      'prepare',
      'render',
      'done',
      'onbekend',
    ]) {
      test('$phase overleeft een deck zonder afbeeldingen', () {
        expect(
          () => exportProgressText(l10n, phase, 0, 0),
          returnsNormally,
          reason: 'total 0 mag geen ArgumentError opleveren',
        );
        expect(exportProgressText(l10n, phase, 0, 0), isNotEmpty);
      });
    }

    test('precache zonder afbeeldingen noemt geen aantallen', () {
      // De tekst zou anders "0 van 0" zeggen, en dat leest als een fout.
      expect(exportProgressText(l10n, 'precache', 0, 0), 'Afbeeldingen laden…');
    });
  });

  group('de gewone gevallen blijven staan', () {
    test('precache mét afbeeldingen telt mee', () {
      expect(exportProgressText(l10n, 'precache', 2, 5), contains('2'));
      expect(exportProgressText(l10n, 'precache', 2, 5), contains('5'));
    });

    test('dia\'s tellen vanaf 1, niet vanaf 0', () {
      // De gebruiker ziet "Slide 1", niet "Slide 0" — daarom de ondergrens.
      expect(exportProgressText(l10n, 'render', 0, 5), contains('1'));
      expect(exportProgressText(l10n, 'prepare', 0, 5), contains('1'));
    });

    test('het nummer loopt niet voorbij het totaal', () {
      // De bovengrens: bij de laatste dia mag er geen "Slide 6 van 5" staan.
      expect(exportProgressText(l10n, 'render', 4, 5), contains('5'));
      expect(exportProgressText(l10n, 'render', 9, 5), contains('5'));
    });

    test('done meldt pas "gerenderd" als alles er is', () {
      expect(exportProgressText(l10n, 'done', 5, 5), 'Slides gerenderd.');
      expect(exportProgressText(l10n, 'done', 2, 5), contains('2'));
    });

    test('een onbekende fase valt terug op een leesbare regel', () {
      expect(exportProgressText(l10n, 'iets-nieuws', 1, 3), isNotEmpty);
    });
  });
}
