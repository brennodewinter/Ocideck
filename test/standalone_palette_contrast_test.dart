import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/image_picker_palette.dart';
import 'package:ocideck/theme/presenter_palette.dart';
import 'package:ocideck/utils/color_contrast.dart';

/// De twee **op zichzelf staande donkere paletten**: de afbeeldingkiezer en de
/// presentatiemodus.
///
/// `app_theme_contrast_test.dart` dekt het app-thema en de profielen. Deze twee
/// staan daar bewust buiten — het zijn eigen donkere oppervlakken, en om die
/// reden zondert `check_conventions` ze ook uit van de rauwe-kleurratchet. Het
/// gevolg was dat ze buiten élke contrastmeting vielen: `textDim` kleurde zowel
/// iconen als tekst en haalde als tékst op geen enkel oppervlak van zijn eigen
/// palet de 4,5:1 (#779).
///
/// De opzet volgt `appearance_contrast.dart` (#750): een paar draagt zijn eigen
/// lat mee, want de lat hángt af van de rol. 4,5:1 voor tekst (WCAG 1.4.3),
/// 3:1 voor een grafisch onderdeel zoals een icoon of een randstreep (1.4.11).
/// Alles over één kam scheren levert of valse schuld of een blinde vlek op.
void main() {
  /// Elk oppervlak waarop de afbeeldingkiezer inkt legt. Een token wordt tegen
  /// **alle** getoetst en niet tegen "het" oppervlak: dezelfde tekst staat in
  /// dit venster op de kop, op een kaart en op een overlay, en het donkerste
  /// oppervlak is niet het krapste geval — het lichtste is dat.
  ///
  /// De tokens zijn nu mode-afhankelijk, dus dit leest ze **per thema** vers uit
  /// (niet const): de lichte kiezer heeft zijn eigen krapste geval, de donkere
  /// het zijne.
  Map<String, Color> pickerSurfaces() => {
    'bgDeepest': ImagePickerPalette.bgDeepest,
    'bgDeep': ImagePickerPalette.bgDeep,
    'bg': ImagePickerPalette.bg,
    'overlay': ImagePickerPalette.overlay,
    'surface1': ImagePickerPalette.surface1,
    'surfaceAlt': ImagePickerPalette.surfaceAlt,
    'surface2': ImagePickerPalette.surface2,
  };

  /// Draai [body] onder beide app-thema's (licht én donker), en zet [AppTheme.isDark]
  /// daarna terug. De kiezer volgt nu het thema, dus elke contrastlat geldt in
  /// beide — een licht token dat de lat mist is net zo fout als een donker.
  void inBothThemes(void Function(String thema) body) {
    final saved = AppTheme.isDark;
    addTearDown(() => AppTheme.isDark = saved);
    for (final dark in [false, true]) {
      AppTheme.isDark = dark;
      body(dark ? 'donker' : 'licht');
    }
  }

  const presenterSurfaces = <String, Color>{
    'bgDeepest': PresenterPalette.bgDeepest,
    'bg': PresenterPalette.bg,
    'bg2': PresenterPalette.bg2,
    'surface': PresenterPalette.surface,
    'surface2': PresenterPalette.surface2,
    'surface3': PresenterPalette.surface3,
    'surface4': PresenterPalette.surface4,
  };

  /// Meet [ink] tegen elk oppervlak en geeft terug wat onder [bar] zakt.
  Map<String, double> shortfall(
    Color ink,
    Map<String, Color> surfaces,
    double bar,
  ) => {
    for (final entry in surfaces.entries)
      if (contrastRatio(ink, entry.value) < bar)
        entry.key: contrastRatio(ink, entry.value),
  };

  group('afbeeldingkiezer', () {
    test('de tekstkleuren halen 4,5:1 op elk oppervlak (licht + donker)', () {
      inBothThemes((thema) {
        final surfaces = pickerSurfaces();
        for (final (naam, ink) in [
          ('text', ImagePickerPalette.text),
          ('textMuted', ImagePickerPalette.textMuted),
        ]) {
          expect(
            shortfall(ink, surfaces, kWcagAaNormalText),
            isEmpty,
            reason:
                '$naam is tekst en zakt in het $thema-thema onder de AA-lat',
          );
        }
      });
    });

    test(
      'de gedempte icoonkleur haalt 3:1 op elk oppervlak (licht + donker)',
      () {
        inBothThemes((thema) {
          expect(
            shortfall(
              ImagePickerPalette.iconDim,
              pickerSurfaces(),
              kWcagAaLargeText,
            ),
            isEmpty,
            reason:
                'iconDim kleurt grafische onderdelen; onder 3:1 is ook dat niet '
                'meer te zien ($thema-thema)',
          );
        });
      },
    );

    test('iconDim is en blijft ongeschikt als tekst (licht + donker)', () {
      // Geen bewaking maar een vastlegging: dit token háált de tekstlat niet,
      // en dat is precies waarom het niet meer `textDim` heet. Trekt iemand de
      // waarde ooit op tot boven 4,5, dan valt deze toets — en dan is de vraag
      // of `iconDim` en `textMuted` nog twee tinten zijn of één.
      inBothThemes((thema) {
        expect(
          shortfall(
            ImagePickerPalette.iconDim,
            pickerSurfaces(),
            kWcagAaNormalText,
          ),
          isNotEmpty,
          reason:
              'iconDim haalt in het $thema-thema wél overal de tekstlat — '
              'heroverweeg of hij naast textMuted nog bestaansrecht heeft',
        );
      });
    });

    test('het label op een gekleurde vulling leest', () {
      // De vullingen zelf tegen de tekstlat leggen zou een categoriefout zijn
      // (dat vulde de helft van #606's basislijn). Wat er wél toe doet is wat
      // eróp staat — dezelfde klasse als het knoplabel dat in #750 op 2,54:1
      // bleek te staan.
      const wit = Color(0xFFFFFFFF);
      final tekort = <String, double>{};
      for (final (naam, vulling) in [
        ('successStrong', ImagePickerPalette.successStrong),
        ('dangerStrong', ImagePickerPalette.dangerStrong),
        ('accentStrong', ImagePickerPalette.accentStrong),
      ]) {
        final ratio = contrastRatio(wit, vulling);
        if (ratio < kWcagAaNormalText) tekort[naam] = ratio;
      }
      expect(tekort, isEmpty, reason: 'wit label op deze vulling: $tekort');
    });
  });

  group('presentatiemodus', () {
    test('de tekstkleuren halen 4,5:1 op elk oppervlak', () {
      // `textMuted` kwam er in #780 bij. Tot dan improviseerde de presenter
      // zijn tweede tekstniveau met `Colors.white24`, `white30` en `white38` op
      // tien plekken — 2,06 tot 3,60:1, waaronder de sneltoetsbalk die de énige
      // uitleg is die een presentator tijdens een presentatie op het scherm
      // heeft. Dat ontsnapte aan élke poort: het is geen `Color(0x…)`, dus de
      // ratchet ziet het niet, en aan `white38` valt op de aanroepplek niet af
      // te lezen wat het wordt.
      for (final (naam, ink) in [
        ('text', PresenterPalette.text),
        ('textMuted', PresenterPalette.textMuted),
      ]) {
        expect(
          shortfall(ink, presenterSurfaces, kWcagAaNormalText),
          isEmpty,
          reason: '$naam is tekst en zakt hier onder de AA-lat',
        );
      }
    });

    test('de ring om een inkkleur is te onderscheiden op de annotatiebalk', () {
      // De annotatiebalk vult zich met zwart op 82%, dus zijn achtergrond hangt
      // af van de dia eronder — een witte dia is voor een lichte ring het
      // krapste geval, en dat oppervlak staat in geen enkele lijst hierboven.
      //
      // Waarom dit een eigen toets verdient: de zwarte inkkleur haalt 1,4:1
      // tegen die balk. Zonder een zichtbare ring is het geen keuze maar een
      // gat in de rij. Tot #780 was die ring `Colors.white24` (2,17:1).
      final balkOpWitteDia = Color.alphaBlend(
        Colors.black.withValues(alpha: 0.82),
        const Color(0xFFFFFFFF),
      );
      expect(
        contrastRatio(PresenterPalette.outline, balkOpWitteDia),
        greaterThanOrEqualTo(kWcagAaLargeText),
        reason: 'de ring is een keuze-affordance (WCAG 1.4.11)',
      );
    });

    test('de laserkleuren zijn als markering te onderscheiden', () {
      // Laserrood en -groen zijn aanwijzers op een dia, geen tekst: 3:1. Ze
      // liggen bovendien op de dia zelf en niet op de chrome, maar het donkerste
      // presentatie-oppervlak is de strengste ondergrond die ze hier raken.
      for (final (naam, kleur) in [
        ('laserGreen', PresenterPalette.laserGreen),
        ('laserRed', PresenterPalette.laserRed),
      ]) {
        expect(
          shortfall(kleur, presenterSurfaces, kWcagAaLargeText),
          isEmpty,
          reason: '$naam is als aanwijzer niet te onderscheiden',
        );
      }
    });
  });

  test('geen palet-token buiten zijn rol gebruikt', () {
    // De bronwacht. De rekensom hierboven bewaakt de kleuren; deze bewaakt waar
    // ze landen — want de fout in #779 was niet een verkeerde waarde maar een
    // token dat op twee soorten plekken stond. `iconDim` in een `TextStyle` is
    // per definitie fout, ongeacht wat de meting zegt.
    final overtreders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final regels = entity.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        final regel = regels[i];
        if (!regel.contains('ImagePickerPalette.iconDim')) continue;
        // Een icoonkleur hoort in een `Icon(...)` of een `IconThemeData`. Staat
        // hij in een tekststijl, dan is het een tekstgebruik.
        final venster = regels
            .sublist((i - 3).clamp(0, i), (i + 2).clamp(0, regels.length))
            .join(' ');
        if (venster.contains('TextStyle') || venster.contains('hintStyle')) {
          overtreders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(
      overtreders,
      isEmpty,
      reason:
          'iconDim haalt de tekstlat niet — gebruik textMuted:\n'
          '${overtreders.join('\n')}',
    );
  });

  // De tweede bronwacht, en de wijdere: hierboven gaat het over één token dat
  // op de verkeerde soort plek staat, hier over kleuren die aan élke poort
  // ontsnappen.
  //
  // `check_conventions` telt `Color(0x…)`-literals en staat op nul.
  // `Colors.white38` is dezelfde vrijheid met dezelfde gevolgen en matcht die
  // regex niet. Alle tien de presenter-plekken uit #780 kwamen daar vandaan —
  // 2,06 tot 3,60:1, jarenlang, in de modus waarin de app het meest gebruikt
  // wordt.
  //
  // De grens is bewust `TextStyle` en niet elke `color:`. Een vulling, een
  // schaduw, een scheidingslijn of een scrim draagt geen letters; daar is een
  // doorzichtig zwart juist het goede gereedschap, en de lat van 1.4.11 voor
  // wat wél een affordance is staat per plek hierboven.
  //
  // En waarom élke alpha en niet alleen de lage: het bezwaar is niet dat 38
  // toevallig te weinig is, maar dat je aan `Colors.white38` op de aanroepplek
  // niet kunt zíen wat het wordt. Bij een token uit een palet kan dat wel —
  // dat staat hierboven met zijn gemeten verhouding erbij.
  test('geen doorzichtige Colors.white/black in een TextStyle', () {
    final doorzichtig = RegExp(r'Colors\.(white|black)([0-9]+)\b');
    final overtreders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final regels = entity.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        final match = doorzichtig.firstMatch(regels[i]);
        if (match == null) continue;
        final venster = regels.sublist(i >= 4 ? i - 4 : 0, i + 1).join(' ');
        if (!venster.contains('TextStyle(')) continue;
        overtreders.add('${entity.path}:${i + 1}  ${match[0]}');
      }
    }
    expect(
      overtreders,
      isEmpty,
      reason:
          'Neem een token uit het palet van dat oppervlak (PresenterPalette / '
          'ImagePickerPalette / AppTheme) en zet het paar in dit bestand, '
          'zodat de verhouding gemeten wordt in plaats van geschat:\n'
          '${overtreders.join('\n')}',
    );
  });
}
