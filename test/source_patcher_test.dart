import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/source_patcher.dart';

void main() {
  group('patchVisualEdits', () {
    test('geen bewerking → origineel byte-identiek', () {
      const original = '# Titel\n\nEen alinea.\n\n## Kop\n\nNog een alinea.\n';
      const baseline = original; // perfecte round-trip
      const current = original;
      expect(
        patchVisualEdits(
          original: original,
          baseline: baseline,
          current: current,
        ),
        original,
      );
    });

    test('één woord toegevoegd aan kop → alleen die regel verandert', () {
      const original = '# Kern\n\nHier staat tekst.\n';
      // Simuleer een round-trip die witregels normaliseert (geen drift hier,
      // maar de test verifieert dat de patch alleen de gewijzigde regel aanpast).
      const baseline = '# Kern\n\nHier staat tekst.\n';
      const current = '# De Kern\n\nHier staat tekst.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, '# De Kern\n\nHier staat tekst.\n');
    });

    test(
      'round-trip normaliseert witregels, bewerking behoudt originele opmaak',
      () {
        // Origineel met compacte tabelscheidingsregel (zoals in #1613).
        const original = '# Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n';
        // Round-trip voegt spaties toe aan de scheidingsregel.
        const baseline =
            '# Notitie\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nTekst.\n';
        // Gebruiker voegt "Belangrijk" toe aan de kop.
        const current =
            '# Belangrijke Notitie\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nTekst.\n';
        final result = patchVisualEdits(
          original: original,
          baseline: baseline,
          current: current,
        );
        // De kop is gewijzigd, maar de tabel behoudt de compacte scheidingsregel.
        expect(
          result,
          '# Belangrijke Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n',
        );
      },
    );

    test('regel verwijderd → alleen die regel verdwijnt', () {
      const original = '# Kop\n\nEerste.\n\nTweede.\n\nDerde.\n';
      const baseline = original;
      const current = '# Kop\n\nEerste.\n\nDerde.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, '# Kop\n\nEerste.\n\nDerde.\n');
    });

    test('regel ingevoegd → alleen die regel verschijnt', () {
      const original = '# Kop\n\nEerste.\n\nDerde.\n';
      const baseline = original;
      const current = '# Kop\n\nEerste.\n\nTweede.\n\nDerde.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, '# Kop\n\nEerste.\n\nTweede.\n\nDerde.\n');
    });

    test(
      'round-trip verplaatst een kop, bewerking behoudt originele volgorde',
      () {
        // Origineel: kop staat vóór de alinea eronder.
        const original =
            '# 1. Kern\n\nInhoud hier.\n\n# 2. Detail\n\nMeer inhoud.\n';
        // Round-trip verplaatst de kop ná de alinea (fictieve drift).
        const baseline =
            'Inhoud hier.\n\n# 1. Kern\n\nMeer inhoud.\n\n# 2. Detail\n';
        // Gebruiker wijzigt "Inhoud hier" → "Gewijzigde inhoud".
        const current =
            'Gewijzigde inhoud.\n\n# 1. Kern\n\nMeer inhoud.\n\n# 2. Detail\n';
        final result = patchVisualEdits(
          original: original,
          baseline: baseline,
          current: current,
        );
        // De originele volgorde (kop vóór alinea) blijft behouden; alleen de
        // gewijzigde alinea is aangepast.
        expect(
          result,
          '# 1. Kern\n\nGewijzigde inhoud.\n\n# 2. Detail\n\nMeer inhoud.\n',
        );
      },
    );

    test('baseline == current → origineel ongeacht normalisatie', () {
      const original = '# Kop\n\nTekst.\n';
      const baseline = '# Kop\n\nTekst.\n\n'; // extra witregel genormaliseerd
      const current = baseline; // geen bewerking
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, original);
    });

    test('meerdere onafhankelijke bewerkingen', () {
      const original = '# A\n\nEerste.\n\n# B\n\nTweede.\n\n# C\n\nDerde.\n';
      const baseline = original;
      const current =
          '# A gewijzigd\n\nEerste.\n\n# B\n\nTweede gewijzigd.\n\n# C\n\nDerde.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, current);
    });

    test('lege current → lege output', () {
      const original = '# Kop\n\nTekst.\n';
      const baseline = '# Kop\n\nTekst.\n';
      const current = '';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, '');
    });

    test('compleet nieuw document (origineel leeg)', () {
      const original = '';
      const baseline = '';
      const current = '# Nieuw\n\nTekst.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, current);
    });

    // #1648: CRLF-bewaring — de originele bron kan \r\n regeleinden hebben,
    // terwijl Quill naar \n normaliseert. De uitvoer moet \r\n behouden.
    test('CRLF-origineel behoudt \\r\\n in uitvoer (#1648)', () {
      const original = '# Titel\r\n\r\nEen alinea.\r\n';
      // Quill normaliseert naar \n.
      const baseline = '# Titel\n\nEen alinea.\n';
      const current = '# Nieuwe Titel\n\nEen alinea.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, '# Nieuwe Titel\r\n\r\nEen alinea.\r\n');
    });

    test('LF-origineel blijft LF (geen CRLF-introductie)', () {
      const original = '# Titel\n\nEen alinea.\n';
      const baseline = '# Titel\n\nEen alinea.\n';
      const current = '# Nieuw\n\nEen alinea.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, '# Nieuw\n\nEen alinea.\n');
      expect(result.contains('\r'), isFalse);
    });

    // #1651: lineaire schaling via prefix/suffix-trimming. Een kleine
    // bewerking in een lang document moet niet de hele LCS-matrix opbouwen.
    test('kleine bewerking in lang document → alleen gewijzigde regel', () {
      final big = List.generate(5000, (i) => 'Regel $i').join('\n');
      final baseline = big;
      // Wijzig één regel in het midden.
      final currLines = big.split('\n');
      currLines[2500] = 'Gewijzigd 2500';
      final current = currLines.join('\n');
      final result = patchVisualEdits(
        original: big,
        baseline: baseline,
        current: current,
      );
      expect(result, current);
    });
  });
}
