import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/two_images_geometry.dart';

/// Unitchecks voor de 'Gelijke hoogte'-geometrie (#2867): gelijke hoogtes,
/// behouden beeldverhoudingen en geen overflow bij extreme bronverhoudingen.
void main() {
  test('landschap + portret krijgen exact dezelfde hoogte', () {
    final row = twoImagesEqualHeight(
      aspect1: 16 / 9,
      aspect2: 3 / 4,
      availW: 1180,
      availH: 620,
      gap: 20,
    )!;

    expect(row.height, (1180 - 20) / (16 / 9 + 3 / 4));
    expect(row.leftWidth, closeTo(row.height * 16 / 9, 1e-9));
    expect(row.rightWidth, closeTo(row.height * 3 / 4, 1e-9));
    // Top- én onderlijn zijn gelijk per constructie.
    expect(row.totalWidth, lessThanOrEqualTo(1180));
    expect(row.height, lessThanOrEqualTo(620));
  });

  test('een hoge dia-ruimte laat de rij op de breedte begrenzen', () {
    final row = twoImagesEqualHeight(
      aspect1: 1,
      aspect2: 1,
      availW: 400,
      availH: 10000,
      gap: 0,
    )!;

    // (400 - 0) / (1 + 1) = 200 — de hoogte volgt de breedte, niet de ruimte.
    expect(row.height, 200);
    expect(row.totalWidth, 400);
  });

  test('een extreme panorama deugt zonder overflow', () {
    final row = twoImagesEqualHeight(
      aspect1: 8,
      aspect2: 0.2,
      availW: 800,
      availH: 450,
      gap: 16,
    )!;

    expect(row.totalWidth, closeTo(800, 1e-6));
    expect(row.height, lessThanOrEqualTo(450));
    expect(row.leftWidth, greaterThan(0));
    expect(row.rightWidth, greaterThan(0));
  });

  test('de tussenruimte meetelt in de breedte', () {
    final noGap = twoImagesEqualHeight(
      aspect1: 1,
      aspect2: 1,
      availW: 400,
      availH: 300,
    )!;
    final withGap = twoImagesEqualHeight(
      aspect1: 1,
      aspect2: 1,
      availW: 400,
      availH: 300,
      gap: 40,
    )!;

    expect(withGap.totalWidth, 400);
    expect(withGap.height, lessThan(noGap.height));
  });

  test('ongeldige invoer levert null, nooit NaN of een negatieve rij', () {
    for (final args in [
      (0.0, 1.0, 800.0, 450.0),
      (1.0, -2.0, 800.0, 450.0),
      (double.nan, 1.0, 800.0, 450.0),
      (double.infinity, 1.0, 800.0, 450.0),
      (1.0, 1.0, 0.0, 450.0),
      (1.0, 1.0, 800.0, -10.0),
    ]) {
      expect(
        twoImagesEqualHeight(
          aspect1: args.$1,
          aspect2: args.$2,
          availW: args.$3,
          availH: args.$4,
        ),
        isNull,
        reason: 'verwacht null voor $args',
      );
    }
  });
}
