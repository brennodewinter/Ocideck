import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';

/// De kopletter en de gewenste letters van een documentstijl (#2119).
///
/// Twee dingen worden bewaakt. Ten eerste de terugval: zonder kopletter
/// volgen de koppen de bodyletter, zonder voorkeur noemt de export wat het
/// scherm toont. Ten tweede de poort: een kopletter komt alleen uit de
/// aangeboden lijst, en een gewenste letter is vrije tekst die in CSS en XML
/// belandt — alles wat daaruit kan breken moet er bij het lezen al uit.
void main() {
  group('terugval', () {
    test('zonder kopletter volgen de koppen de bodyletter', () {
      const profile = ThemeProfile(fontFamily: 'Georgia');
      expect(profile.documentHeadingFontFamily, isNull);
      expect(profile.effectiveDocumentHeadingFontFamily, 'Georgia');
      expect(profile.exportFontFamily, 'Georgia');
      expect(profile.exportDocumentHeadingFontFamily, 'Georgia');
    });

    test('een gewenste letter wint bij export, niet op het scherm', () {
      const profile = ThemeProfile(
        fontFamily: 'Arial',
        preferredFontFamily: 'Aptos Light',
      );
      expect(profile.effectiveDocumentHeadingFontFamily, 'Arial');
      expect(profile.exportFontFamily, 'Aptos Light');
      // Geen aparte kopletter: de kop volgt de lopende tekst, mét voorkeur.
      expect(profile.exportDocumentHeadingFontFamily, 'Aptos Light');
    });

    test('de kopletter cascadeert: gewenst → gezet → body', () {
      const explicit = ThemeProfile(
        fontFamily: 'Arial',
        documentHeadingFontFamily: 'Georgia',
        preferredFontFamily: 'Aptos Light',
      );
      expect(explicit.effectiveDocumentHeadingFontFamily, 'Georgia');
      expect(explicit.exportDocumentHeadingFontFamily, 'Georgia');

      const preferred = ThemeProfile(
        fontFamily: 'Arial',
        documentHeadingFontFamily: 'Georgia',
        preferredDocumentHeadingFontFamily: 'Aptos',
      );
      expect(preferred.exportDocumentHeadingFontFamily, 'Aptos');
    });
  });

  group('opslag', () {
    test('de drie velden overleven toJson → fromJson', () {
      const profile = ThemeProfile(
        name: 'Huisstijl',
        documentHeadingFontFamily: 'Calibri',
        preferredFontFamily: 'Aptos Light',
        preferredDocumentHeadingFontFamily: 'Aptos',
      );
      final back = ThemeProfile.fromJson(profile.toJson());
      expect(back.documentHeadingFontFamily, 'Calibri');
      expect(back.preferredFontFamily, 'Aptos Light');
      expect(back.preferredDocumentHeadingFontFamily, 'Aptos');
    });

    test('een profiel van vóór deze velden leest als niet-gezet', () {
      final legacy = ThemeProfile.fromJson(const {'name': 'Oud'});
      expect(legacy.documentHeadingFontFamily, isNull);
      expect(legacy.preferredFontFamily, isNull);
      expect(legacy.preferredDocumentHeadingFontFamily, isNull);
    });

    test('copyWith kan de velden gericht wissen', () {
      const profile = ThemeProfile(
        documentHeadingFontFamily: 'Calibri',
        preferredFontFamily: 'Aptos Light',
        preferredDocumentHeadingFontFamily: 'Aptos',
      );
      final cleared = profile.copyWith(
        clearDocumentHeadingFontFamily: true,
        clearPreferredFontFamily: true,
        clearPreferredDocumentHeadingFontFamily: true,
      );
      expect(cleared.documentHeadingFontFamily, isNull);
      expect(cleared.preferredFontFamily, isNull);
      expect(cleared.preferredDocumentHeadingFontFamily, isNull);
      // Zonder vlag blijft alles staan.
      expect(profile.copyWith().preferredFontFamily, 'Aptos Light');
    });
  });

  group('poort', () {
    test('een kopletter buiten de aangeboden lijst wordt null', () {
      final profile = ThemeProfile.fromJson(const {
        'documentHeadingFontFamily': "Aptos'; } body{",
      });
      expect(profile.documentHeadingFontFamily, isNull);
      expect(
        ThemeProfile.fromJson(const {
          'documentHeadingFontFamily': 'Georgia',
        }).documentHeadingFontFamily,
        'Georgia',
      );
    });

    test('een gewenste letter met CSS- of XML-breekpunten valt af', () {
      for (final bad in [
        "Aptos'; } body{",
        'Aptos" onload="x',
        'Aptos<b>',
        'Aptos & Co',
        'Aptos;',
        '{Aptos}',
        ' ',
        '-Aptos',
        'A' * 65,
      ]) {
        expect(
          ThemeProfile.fromJson({
            'preferredFontFamily': bad,
          }).preferredFontFamily,
          isNull,
          reason: bad,
        );
      }
    });

    test('een gewone lettertypenaam blijft staan, getrimd', () {
      for (final good in [
        'Aptos',
        'Aptos Light',
        'Neue Haas Grotesk Text Pro',
        'Source Sans 3',
        'Avenir Next LT Pro',
        'Fira Sans Condensed',
        'Times New Roman',
        'Segoe UI',
        'Noto Sans CJK JP',
        '游ゴシック',
        'Helvetica.Neue',
        'A' * 64,
      ]) {
        expect(
          ThemeProfile.fromJson({
            'preferredFontFamily': ' $good ',
          }).preferredFontFamily,
          good,
          reason: good,
        );
      }
    });

    test('een niet-string wordt null', () {
      expect(
        ThemeProfile.fromJson(const {
          'preferredFontFamily': 12,
        }).preferredFontFamily,
        isNull,
      );
    });
  });
}
