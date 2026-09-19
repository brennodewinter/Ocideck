import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/font_substitution.dart';

/// De plaatsvervanger voor een vreemd lettertype.
///
/// Wat hier bewaakt wordt is niet de tabel zelf, maar de drie beloften erop:
/// een letter die we aanbieden blijft zichzelf (ook als dikte-variant), een
/// schreefletter wordt een schreefletter, en een onbekende naam valt op iets
/// dat overal bestaat — nooit op een lege of onaangeboden naam.
void main() {
  group('classifyFontFamily', () {
    test('herkent schreef, schreefloos en vaste breedte', () {
      expect(classifyFontFamily('Cambria'), FontClass.serif);
      expect(classifyFontFamily('Times New Roman'), FontClass.serif);
      expect(classifyFontFamily('Garamond Premier Pro'), FontClass.serif);
      expect(classifyFontFamily('Aptos'), FontClass.sans);
      expect(classifyFontFamily('Calibri Light'), FontClass.sans);
      expect(classifyFontFamily('Consolas'), FontClass.mono);
      expect(classifyFontFamily('JetBrains Mono NL'), FontClass.mono);
    });

    test('Century Gothic is schreefloos, Century Schoolbook niet', () {
      expect(classifyFontFamily('Century Gothic'), FontClass.sans);
      expect(classifyFontFamily('Century Schoolbook'), FontClass.serif);
    });

    test('hoofdletters en witruimte doen er niet toe', () {
      expect(classifyFontFamily('  GEORGIA '), FontClass.serif);
      expect(classifyFontFamily(''), FontClass.sans);
    });
  });

  group('nearestAvailableFont', () {
    test('een aangeboden letter blijft zichzelf', () {
      for (final font in AppSettings.availableFonts) {
        expect(nearestAvailableFont(font), font);
        expect(nearestAvailableFont(font.toUpperCase()), font);
      }
    });

    test('een dikte of variant van een aangeboden letter wordt die letter', () {
      expect(nearestAvailableFont('Calibri Light'), 'Calibri');
      expect(nearestAvailableFont('Segoe UI Semibold'), 'Segoe UI');
      expect(nearestAvailableFont('Arial Narrow'), 'Arial');
    });

    test('een bekende buur gaat vóór de klasse', () {
      expect(nearestAvailableFont('Aptos'), 'Calibri');
      expect(nearestAvailableFont('Aptos Light'), 'Calibri');
      expect(nearestAvailableFont('Aptos Display'), 'Calibri');
      expect(nearestAvailableFont('Helvetica'), 'Helvetica Neue');
      expect(nearestAvailableFont('Liberation Sans'), 'Arial');
      expect(nearestAvailableFont('Liberation Serif'), 'Times New Roman');
    });

    test('schreef → EB Garamond, mono → Courier New, rest → Arial', () {
      expect(nearestAvailableFont('Cambria'), 'EB Garamond');
      expect(nearestAvailableFont('Consolas'), 'Courier New');
      expect(nearestAvailableFont('Volstrekt Onbekend'), 'Arial');
    });

    test('de uitkomst staat altijd in de aangeboden lijst', () {
      for (final name in ['', 'x', 'Cambria Math', 'Noto Sans Mono CJK']) {
        expect(
          AppSettings.availableFonts,
          contains(nearestAvailableFont(name)),
        );
      }
    });
  });
}
