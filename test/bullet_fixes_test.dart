import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/bullet_fixes.dart';

void main() {
  group('splitSentencesInBullets', () {
    test('knipt een meerzinnige bullet op zinsgrenzen', () {
      expect(
        splitSentencesInBullets(['Eerste zin. Tweede zin! Derde zin?']),
        ['Eerste zin.', 'Tweede zin!', 'Derde zin?'],
      );
    });

    test('laat enkelzinnige bullets ongemoeid', () {
      expect(
        splitSentencesInBullets(['Eén zin.', 'Zonder leesteken']),
        ['Eén zin.', 'Zonder leesteken'],
      );
    });

    test('behoudt inspring-niveau', () {
      expect(
        splitSentencesInBullets(['\t\tDiep. Genest.']),
        ['\t\tDiep.', '\t\tGenest.'],
      );
    });

    test('behoudt restzin zonder afsluitend leesteken', () {
      expect(
        splitSentencesInBullets(['Af. En nog wat lopends']),
        ['Af.', 'En nog wat lopends'],
      );
    });

    test('checklist-items behouden hun status per deel', () {
      expect(
        splitSentencesInBullets(['[x] Gedaan. Echt gedaan.', '[ ] Nog. Doen.']),
        ['[x] Gedaan.', '[x] Echt gedaan.', '[ ] Nog.', '[ ] Doen.'],
      );
    });

    test('een punt midden in een woord splitst niet', () {
      expect(
        splitSentencesInBullets(['Versie 1.2 van het plan']),
        ['Versie 1.2 van het plan'],
      );
    });
  });

  group('splitSentenceBullets / canSplitSentenceBullets', () {
    test('werkt op beide kolommen en meldt vooraf of er iets te doen is', () {
      final slide = Slide.create(SlideType.twoBullets).copyWith(
        bullets: ['Links één. Links twee.'],
        bullets2: ['Rechts blijft staan.'],
      );
      expect(canSplitSentenceBullets(slide), isTrue);
      final fixed = splitSentenceBullets(slide);
      expect(fixed.bullets, ['Links één.', 'Links twee.']);
      expect(fixed.bullets2, ['Rechts blijft staan.']);
      expect(canSplitSentenceBullets(fixed), isFalse);
    });

    test('niets te splitsen → canSplit is false', () {
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: ['Eén zin.', 'Nog één.']);
      expect(canSplitSentenceBullets(slide), isFalse);
    });
  });
}
