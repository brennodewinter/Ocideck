import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/bullet_fixes.dart';

void main() {
  group('splitSentencesInBullets', () {
    test('knipt een meerzinnige bullet op zinsgrenzen', () {
      expect(splitSentencesInBullets(['Eerste zin. Tweede zin! Derde zin?']), [
        'Eerste zin.',
        'Tweede zin!',
        'Derde zin?',
      ]);
    });

    test('laat enkelzinnige bullets ongemoeid', () {
      expect(splitSentencesInBullets(['Eén zin.', 'Zonder leesteken']), [
        'Eén zin.',
        'Zonder leesteken',
      ]);
    });

    test('behoudt inspring-niveau', () {
      expect(splitSentencesInBullets(['\t\tDiep. Genest.']), [
        '\t\tDiep.',
        '\t\tGenest.',
      ]);
    });

    test('behoudt restzin zonder afsluitend leesteken', () {
      expect(splitSentencesInBullets(['Af. En nog wat lopends']), [
        'Af.',
        'En nog wat lopends',
      ]);
    });

    test('checklist-items behouden hun status per deel', () {
      expect(
        splitSentencesInBullets(['[x] Gedaan. Echt gedaan.', '[ ] Nog. Doen.']),
        ['[x] Gedaan.', '[x] Echt gedaan.', '[ ] Nog.', '[ ] Doen.'],
      );
    });

    test('een punt midden in een woord splitst niet', () {
      expect(splitSentencesInBullets(['Versie 1.2 van het plan']), [
        'Versie 1.2 van het plan',
      ]);
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

    test('de hele oorspronkelijke regel gaat naar de sprekersnotities', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        bullets: ['Blijft heel.', 'Eerste zin. Tweede zin.'],
        notes: 'Bestaande notitie',
      );
      final fixed = splitSentenceBullets(slide);
      expect(fixed.bullets, ['Blijft heel.', 'Eerste zin.', 'Tweede zin.']);
      // Bestaande notities blijven staan, de volzin komt eronder — alleen van
      // de regel die daadwerkelijk is opgeknipt.
      expect(fixed.notes, 'Bestaande notitie\nEerste zin. Tweede zin.');
    });

    test('de notities krijgen de tussenkop als context mee', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        bullets: [
          groupHeadingBullet('Aanpak'),
          'Eerste zin. Tweede zin.',
          'Derde zin. Vierde zin.',
        ],
      );
      // De kop staat er eenmaal boven, niet bij elke regel opnieuw.
      expect(splitSentenceBullets(slide).notes, [
        'Aanpak',
        'Eerste zin. Tweede zin.',
        'Derde zin. Vierde zin.',
      ].join('\n'));
    });

    test('een slide die te vol zou worden krijgt de actie niet aangeboden', () {
      // Zeven bullets waarvan één uit twee zinnen bestaat: opknippen maakt er
      // acht, nog net binnen de leesbaarheidsdrempel.
      final passend = Slide.create(SlideType.bullets).copyWith(
        bullets: [
          for (var i = 0; i < 6; i++) 'Regel $i.',
          'Eerste zin. Tweede zin.',
        ],
      );
      expect(canSplitSentenceBullets(passend), isTrue);

      // Eén bullet erbij en het resultaat gaat eroverheen: dan hoort alleen
      // "Splits slide" te blijven staan.
      final teVol = passend.copyWith(
        bullets: [...passend.bullets, 'Nog een regel.'],
      );
      expect(canSplitSentenceBullets(teVol), isFalse);
      // Wat de fix zou doen verandert niet — alleen of we hem aanbieden.
      expect(splitSentenceBullets(teVol).bullets.length, 9);
    });
  });
}
