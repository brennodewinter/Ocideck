import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/image_picker_palette.dart';
import 'package:ocideck/theme/presenter_palette.dart';
import 'package:ocideck/utils/color_contrast.dart';

/// Het contrast van de twee **vast-donkere** oppervlakken: de presentatiemodus
/// (met presenter-view, overlays en de annotatiebalk) en de afbeeldingskiezer.
///
/// `app_theme_contrast_test.dart` meet wat `ThemeData` uitdeelt. Deze twee
/// oppervlakken schilderen zichzelf: ze hebben een eigen palet dat níet met het
/// app-thema meebeweegt, en ze zijn daarmee precies het gat dat #780 benoemde —
/// een oppervlak dat zijn kleuren met de hand zet, valt buiten de tokentoets.
/// Vier defecten in de presentatiemodus en drie in de kiezer stonden er
/// daardoor sinds hun eerste regel.
///
/// Wat hier gemeten wordt is niet "welke tokens bestaan" maar **welke paren
/// werkelijk samen op het scherm staan**. Een palet met louter goede kleuren
/// zegt niets: het defect zit in de combinatie, en in dit geval vooral in
/// tokens die voor een rand bedoeld zijn en als tekst landden.
void main() {
  /// Een gemeten paar met de plek waar het staat. De naam is de vindplaats in
  /// mensentaal — een regelnummer verschuift, een oppervlak niet.
  ({Color fg, Color bg, double lat}) tekst(Color fg, Color bg) =>
      (fg: fg, bg: bg, lat: kWcagAaNormalText);

  /// Een grafisch object (rand, vulling, keuzeaffordance): 3:1, WCAG 1.4.11 —
  /// niet de bodytekst-lat, want er valt niets te lezen.
  ({Color fg, Color bg, double lat}) object(Color fg, Color bg) =>
      (fg: fg, bg: bg, lat: kWcagAaLargeText);

  /// De annotatiebalk vult zichzelf met zwart op 82% — dus zijn achtergrond
  /// hangt af van de dia eronder. Voor een lichte voorgrond is een *witte* dia
  /// het krapste geval, en dat is de achtergrond waartegen de ring gemeten hoort
  /// te worden.
  final inkbalkLichtst = Color.alphaBlend(
    Colors.black.withValues(alpha: 0.82),
    const Color(0xFFFFFFFF),
  );

  group('presentatiemodus (PresenterPalette — altijd donker)', () {
    // `textMuted` staat op elk van deze oppervlakken; de tabel meet hem tegen
    // het donkerste én het lichtste, want daartussen zit niets krapper.
    final paren = <String, ({Color fg, Color bg, double lat})>{
      // presenter_views.dart — kolomkoppen, eindmelding, voortgangsbalk.
      'tweede tekstniveau op het diepste oppervlak': tekst(
        PresenterPalette.textMuted,
        PresenterPalette.bgDeepest,
      ),
      'tweede tekstniveau op het lichtste oppervlak': tekst(
        PresenterPalette.textMuted,
        PresenterPalette.surface4,
      ),
      // presenter_overlays.dart — de sneltoetsbalk onder in presenter-view, de
      // ondertitel en de slidenummers van het slide-overzicht, de timerlabels
      // en de afsluitregel van de toetsenlegenda. Dit is de énige uitleg die
      // een presentator tijdens een presentatie op het scherm heeft.
      'sneltoetsbalk en slide-overzicht': tekst(
        PresenterPalette.textMuted,
        PresenterPalette.bgDeepest,
      ),
      'timerlabels en legenda-afsluitregel': tekst(
        PresenterPalette.textMuted,
        PresenterPalette.surface,
      ),
      'legenda: de toetsomschrijving': tekst(
        PresenterPalette.text,
        PresenterPalette.bg2,
      ),
      // presenter_ink.dart — de kleurkeuze van pen/markeerstift. De zwarte
      // inkkleur is op deze balk alleen aan zijn ring te herkennen.
      'ring om een niet-gekozen inkkleur': object(
        PresenterPalette.outline,
        inkbalkLichtst,
      ),
    };

    paren.forEach((plek, paar) {
      test(plek, () {
        final ratio = contrastRatio(paar.fg, paar.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(paar.lat),
          reason:
              '$plek haalt ${ratio.toStringAsFixed(2)}:1 en de lat is '
              '${paar.lat}:1. Dit oppervlak is altijd donker, dus er is geen '
              'lichte modus die het goedmaakt.',
        );
      });
    });
  });

  group('afbeeldingskiezer (ImagePickerPalette — altijd donker)', () {
    final paren = <String, ({Color fg, Color bg, double lat})>{
      'bestandsnaam en koppen in de kiezer': tekst(
        ImagePickerPalette.text,
        ImagePickerPalette.bg,
      ),
      'bijschrift / beschrijving onder een afbeelding': tekst(
        ImagePickerPalette.textMuted,
        ImagePickerPalette.surface2,
      ),
      'uitleg onder de leegstaat ("Gebruik Bladeren…")': tekst(
        ImagePickerPalette.textMuted,
        ImagePickerPalette.bg,
      ),
      'plaatshouder in de voorbeeldkolom ("Selecteer een afbeelding")': tekst(
        ImagePickerPalette.textMuted,
        ImagePickerPalette.bgDeepest,
      ),
      'zoekhint en metaregel op het lichtste oppervlak': tekst(
        ImagePickerPalette.textMuted,
        ImagePickerPalette.surface2,
      ),
      'sneltoetshint in de voettekst': tekst(
        ImagePickerPalette.textMuted,
        ImagePickerPalette.bg,
      ),
      // `iconDim` is de gedempte tint die #779 uit `textDim` heeft
      // overgehouden: te dun voor tekst, maar als icoon geldt 1.4.11 en haalt
      // hij overal 3:1. Dat is een grens die alleen blijft kloppen als hij
      // gemeten wordt — de naam zegt het, de test bewijst het.
      'gedempt icoon op het lichtste oppervlak': object(
        ImagePickerPalette.iconDim,
        ImagePickerPalette.surface2,
      ),
      // De rand van een níet-gekozen tegel is decoratie (`surface2`): de tegel
      // is aan zijn afbeelding te herkennen, niet aan zijn lijntje. Wat wél
      // informatie draagt, is welke tegel gekozen is.
      'rand van de gekozen tegel — de selectie-affordance': object(
        AppTheme.blue500,
        ImagePickerPalette.bg,
      ),
    };

    paren.forEach((plek, paar) {
      test(plek, () {
        final ratio = contrastRatio(paar.fg, paar.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(paar.lat),
          reason:
              '$plek haalt ${ratio.toStringAsFixed(2)}:1 en de lat is '
              '${paar.lat}:1.',
        );
      });
    });
  });

  // ── De bronwacht ──────────────────────────────────────────────────────────
  //
  // De rekensom hierboven bewaakt de paren die we kennen. Deze bewaakt dat er
  // geen nieuwe bijkomen langs de deur die de ratchet niet dichthoudt.
  //
  // `check_conventions` telt `Color(0x…)`-literals en staat op nul. Material's
  // `Colors.white38` is dezelfde kleur met dezelfde vrijheid, maar matcht die
  // regex niet — en juist de doorzichtige varianten zijn het probleem: ze zien
  // er in de code onschuldig uit ("iets gedempter") terwijl 38% wit op zwart
  // 3,5:1 is en 24% wit 2,2:1. Zeven van de negen defecten uit #780 in de
  // presentatiemodus kwamen hier vandaan.
  test('geen doorzichtige Colors.white/black in een TextStyle in lib/', () {
    // Alleen de doorzichtige varianten: `Colors.white` en `Colors.black` zelf
    // zijn dekkend en op hun eigen oppervlak te beoordelen.
    //
    // De grens is bewust `TextStyle` en niet elke `color:`. Een vulling, een
    // schaduw, een scheidingslijn of een scrim dráágt geen tekst; daar is een
    // doorzichtig zwart juist het goede gereedschap, en de lat van 1.4.11 voor
    // wat wél een affordance is, staat per plek in de tabel hierboven.
    //
    // Waarom élke alpha en niet alleen de lage: het bezwaar is niet dat 38%
    // toevallig te weinig is, maar dat je aan `Colors.white38` niet kunt zíen
    // wat het wordt. Bij een token uit een palet kan dat wel, want dat token
    // staat in de tabel hierboven met zijn gemeten verhouding erbij.
    final doorzichtig = RegExp(r'Colors\.(white|black)([0-9]+)\b');
    final overtreders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final regels = entity.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        final match = doorzichtig.firstMatch(regels[i]);
        if (match == null) continue;
        final context = regels.sublist(i >= 4 ? i - 4 : 0, i + 1).join(' ');
        if (!context.contains('TextStyle(')) continue;
        final pad = entity.path.replaceAll(r'\', '/');
        overtreders.add('$pad:${i + 1}  ${match[0]}');
      }
    }

    expect(
      overtreders,
      isEmpty,
      reason:
          'Een doorzichtige Material-kleur als tekstkleur ontsnapt aan de '
          'ruwe-kleur-ratchet (die matcht `Color(0x…)`) én aan de tokentoets. '
          'Neem een token uit het palet van dat oppervlak (PresenterPalette / '
          'ImagePickerPalette / AppTheme) en zet het paar in de tabel bovenaan '
          'deze test, zodat de verhouding gemeten wordt in plaats van '
          'geschat:\n${overtreders.join('\n')}',
    );
  });
}
