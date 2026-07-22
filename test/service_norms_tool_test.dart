import 'package:flutter_test/flutter_test.dart';

import '../tool/check_service_norms.dart';

/// Het meetinstrument voor de servicenormen (`tool/check_service_norms.dart`).
///
/// Er is nog geen enkele echte melding — geen release, geen incident. Dat is
/// juist de reden dat dit met verzonnen invoer wordt getoetst: het instrument
/// moet aantoonbaar werken vóórdat de eerste melding binnenkomt, niet erna.
///
/// Alle datums zijn verzonnen en alle melders heten `melder` of `beheerder`.
/// Er staat geen persoonsgegeven en geen sleutel in dit bestand.
void main() {
  group('werkdagen', () {
    test('pasen valt waar de kerk hem legt', () {
      // Ankerjaren; het hele feestdagenrooster hangt hieraan.
      expect(paaszondag(2026), DateTime(2026, 4, 5));
      expect(paaszondag(2027), DateTime(2027, 3, 28));
      expect(paaszondag(2024), DateTime(2024, 3, 31));
    });

    test('een weekend telt niet mee', () {
      // Vrijdag 3 juli 2026 → maandag 6 juli 2026 is één werkdag.
      expect(werkdagenTussen(DateTime(2026, 7, 3), DateTime(2026, 7, 6)), 1);
      // Vrijdag → zaterdag is er geen.
      expect(werkdagenTussen(DateTime(2026, 7, 3), DateTime(2026, 7, 4)), 0);
      // Dezelfde dag ook niet.
      expect(werkdagenTussen(DateTime(2026, 7, 3), DateTime(2026, 7, 3)), 0);
    });

    test('een feestdag telt niet mee', () {
      // Tweede kerstdag 2025 valt op een vrijdag. Do 24 dec → ma 29 dec is dus
      // 1 werkdag (donderdag 25e en vrijdag 26e zijn kerst, weekend erna).
      expect(
        werkdagenTussen(DateTime(2025, 12, 24), DateTime(2025, 12, 29)),
        1,
      );
      expect(isWerkdag(DateTime(2026, 1, 1)), isFalse);
      // Tweede paasdag 2026: maandag 6 april.
      expect(isWerkdag(DateTime(2026, 4, 6)), isFalse);
      // De dinsdag erna is een gewone werkdag.
      expect(isWerkdag(DateTime(2026, 4, 7)), isTrue);
    });

    test('koningsdag wijkt voor de zondag', () {
      // 27 april 2025 is een zondag; dan is de 26e de vrije dag. Beide vallen
      // in het weekend, dus dit toetst vooral de verschuiving zelf.
      expect(feestdagen(2025), contains(DateTime(2025, 4, 26)));
      expect(feestdagen(2025), isNot(contains(DateTime(2025, 4, 27))));
      // 27 april 2026 is een maandag en dus een echte vrije werkdag.
      expect(isWerkdag(DateTime(2026, 4, 27)), isFalse);
    });

    test('een lange termijn telt alleen de werkdagen', () {
      // Wo 1 juli 2026 → wo 15 juli 2026: twee volle weken, 10 werkdagen.
      expect(werkdagenTussen(DateTime(2026, 7, 1), DateTime(2026, 7, 15)), 10);
    });

    test('kalenderdagen tellen wél gewoon door', () {
      expect(
        kalenderdagenTussen(DateTime(2026, 7, 1), DateTime(2026, 7, 15)),
        14,
      );
      // Terug in de tijd is geen negatieve afstand maar geen afstand.
      expect(
        kalenderdagenTussen(DateTime(2026, 7, 15), DateTime(2026, 7, 1)),
        0,
      );
    });
  });
}
