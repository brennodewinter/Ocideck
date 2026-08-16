import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';

/// Feature 5: de tabelstijl-velden op `ThemeProfile` (zebrastrepen, randstijl,
/// celopvulling, accentkoprand, zebrakleur, randkleur) horen door de JSON
/// round-trip heen byte-getrouw te blijven — een profiel dat ze zet, leest
/// ze ongewijzigd terug, en een profiel zonder ze houdt de defaults.
void main() {
  group('ThemeProfile tabelstijl — JSON round-trip', () {
    test(
      'defaults: boxed, geen zebrastrepen, 8px opvulling, geen accentlijn',
      () {
        const p = ThemeProfile(name: 'Test');
        expect(p.tableBorderStyle, TableBorderStyle.boxed);
        expect(p.tableZebraStriped, isFalse);
        expect(p.tableAccentHeaderBorder, isFalse);
        expect(p.tableCellPaddingPx, 8.0);
        expect(p.tableZebraColor, '#F1F5F9');
        expect(p.tableBorderColor, '#CBD5E1');
      },
    );

    test('ingevulde tabelstijl overleeft toJson → fromJson', () {
      const p = ThemeProfile(
        name: 'Huisstijl',
        tableZebraStriped: true,
        tableZebraColor: '#EEF2FF',
        tableBorderStyle: TableBorderStyle.lined,
        tableBorderColor: '#1E293B',
        tableCellPaddingPx: 12.0,
        tableAccentHeaderBorder: true,
      );
      final round = ThemeProfile.fromJson(p.toJson());
      expect(round.tableZebraStriped, isTrue);
      expect(round.tableZebraColor, '#EEF2FF');
      expect(round.tableBorderStyle, TableBorderStyle.lined);
      expect(round.tableBorderColor, '#1E293B');
      expect(round.tableCellPaddingPx, 12.0);
      expect(round.tableAccentHeaderBorder, isTrue);
    });

    test('een profiel zonder tabelstijl-sleutels valt terug op defaults', () {
      final round = ThemeProfile.fromJson({
        'name': 'Oud profiel',
        'accentColor': '#003399',
      });
      expect(round.tableBorderStyle, TableBorderStyle.boxed);
      expect(round.tableZebraStriped, isFalse);
      expect(round.tableAccentHeaderBorder, isFalse);
      expect(round.tableCellPaddingPx, 8.0);
    });

    test(
      'copyWith behoudt bestaande tabelstijl bij ongerelateerde wijziging',
      () {
        const p = ThemeProfile(
          name: 'Test',
          tableZebraStriped: true,
          tableBorderStyle: TableBorderStyle.none,
        );
        final updated = p.copyWith(name: 'Nieuwe naam');
        expect(updated.tableZebraStriped, isTrue);
        expect(updated.tableBorderStyle, TableBorderStyle.none);
        expect(updated.name, 'Nieuwe naam');
      },
    );

    test('TableBorderStyle heeft drie waarden: lined, boxed, none', () {
      expect(TableBorderStyle.values, hasLength(3));
      expect(TableBorderStyle.values, contains(TableBorderStyle.lined));
      expect(TableBorderStyle.values, contains(TableBorderStyle.boxed));
      expect(TableBorderStyle.values, contains(TableBorderStyle.none));
    });
  });
}
