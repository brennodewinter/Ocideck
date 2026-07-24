import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  const pickerSurfaces = <String, Color>{
    'bgDeepest': ImagePickerPalette.bgDeepest,
    'bgDeep': ImagePickerPalette.bgDeep,
    'bg': ImagePickerPalette.bg,
    'overlay': ImagePickerPalette.overlay,
    'surface1': ImagePickerPalette.surface1,
    'surfaceAlt': ImagePickerPalette.surfaceAlt,
    'surface2': ImagePickerPalette.surface2,
  };

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
    test('de tekstkleuren halen 4,5:1 op elk oppervlak', () {
      for (final (naam, ink) in [
        ('text', ImagePickerPalette.text),
        ('textMuted', ImagePickerPalette.textMuted),
      ]) {
        expect(
          shortfall(ink, pickerSurfaces, kWcagAaNormalText),
          isEmpty,
          reason: '$naam is tekst en zakt hier onder de AA-lat',
        );
      }
    });

    test('de gedempte icoonkleur haalt 3:1 op elk oppervlak', () {
      expect(
        shortfall(ImagePickerPalette.iconDim, pickerSurfaces, kWcagAaLargeText),
        isEmpty,
        reason:
            'iconDim kleurt grafische onderdelen; onder 3:1 is ook dat niet '
            'meer te zien',
      );
    });

    test('iconDim is en blijft ongeschikt als tekst', () {
      // Geen bewaking maar een vastlegging: dit token háált de tekstlat niet,
      // en dat is precies waarom het niet meer `textDim` heet. Trekt iemand de
      // waarde ooit op tot boven 4,5, dan valt deze toets — en dan is de vraag
      // of `iconDim` en `textMuted` nog twee tinten zijn of één.
      expect(
        shortfall(
          ImagePickerPalette.iconDim,
          pickerSurfaces,
          kWcagAaNormalText,
        ),
        isNotEmpty,
        reason:
            'iconDim haalt nu wél overal de tekstlat — heroverweeg of hij naast '
            'textMuted nog bestaansrecht heeft',
      );
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
    test('de tekstkleur haalt 4,5:1 op elk oppervlak', () {
      expect(
        shortfall(PresenterPalette.text, presenterSurfaces, kWcagAaNormalText),
        isEmpty,
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
}
