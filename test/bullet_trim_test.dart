import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/bullet_fixes.dart';

// De derde dichtheidsfix: haal de uitleg van een "label : uitleg"-bullet van de
// slide af naar de notities. Anders dan de twee bestaande fixes (splitsen,
// zinnen opknippen) haalt deze tekst wég — dus de test bewaakt zowel dát het
// gebeurt als dat het níét te gretig gebeurt (korte uitleg, geen scheiding, een
// dubbele punt in een URL).
void main() {
  Slide bulletsWith(List<String> bullets, {String notes = ''}) =>
      Slide.create(SlideType.bullets).copyWith(bullets: bullets, notes: notes);

  group('canTrimBulletExplanations', () {
    test('waar bij een label met een substantiële uitleg', () {
      expect(
        canTrimBulletExplanations(
          bulletsWith(['Autorisatie: geregeld via de centrale IAM-oplossing']),
        ),
        isTrue,
      );
    });

    test('onwaar zonder scheiding of bij een te korte uitleg', () {
      expect(
        canTrimBulletExplanations(bulletsWith(['Gewone bullet zonder meer'])),
        isFalse,
      );
      expect(
        canTrimBulletExplanations(bulletsWith(['Status: klaar'])),
        isFalse,
      );
    });
  });

  group('trimBulletExplanations', () {
    test('dubbele punt: label blijft, uitleg gaat naar de notities', () {
      final out = trimBulletExplanations(
        bulletsWith(['Autorisatie: geregeld via de centrale IAM-oplossing']),
      );
      expect(out.bullets, ['Autorisatie']);
      expect(
        out.notes,
        '- Autorisatie: geregeld via de centrale IAM-oplossing',
      );
    });

    test('koppelstreepje splitst label en uitleg', () {
      final out = trimBulletExplanations(
        bulletsWith(['Toegang - alleen na goedkeuring van de eigenaar']),
      );
      expect(out.bullets, ['Toegang']);
      expect(out.notes.contains('alleen na goedkeuring'), isTrue);
    });

    test('de eerste punt splitst een lange bullet', () {
      final out = trimBulletExplanations(
        bulletsWith(['Beleid. Dit regelt de toegang en de naleving ervan']),
      );
      expect(out.bullets, ['Beleid']);
    });

    test('een korte uitleg blijft ongemoeid', () {
      final slide = bulletsWith(['Status: klaar']);
      final out = trimBulletExplanations(slide);
      expect(out.bullets, ['Status: klaar']);
      expect(out.notes, '');
    });

    test('een dubbele punt in een URL splitst niet', () {
      final slide = bulletsWith([
        'Zie https://example.com/pagina voor de details hier',
      ]);
      expect(trimBulletExplanations(slide).bullets, slide.bullets);
    });

    test('een koppelteken binnen een woord splitst niet', () {
      final slide = bulletsWith([
        'Well-known probleem in de configuratie hier',
      ]);
      expect(trimBulletExplanations(slide).bullets, slide.bullets);
    });

    test('behoudt het inspring-niveau', () {
      final out = trimBulletExplanations(
        bulletsWith(['\tRisico: de sleutel staat in de repository geschreven']),
      );
      expect(out.bullets, ['\tRisico']);
    });

    test('checklist-items behouden hun aangevinkt-status', () {
      final input = checklistBullet(
        level: 0,
        text: 'Taak: rond het rapport netjes af',
        checked: true,
      );
      final out = trimBulletExplanations(bulletsWith([input]));
      expect(out.bullets.single, '[x] Taak');
      expect(checklistItemChecked(out.bullets.single), isTrue);
    });

    test('voegt de uitleg toe onder bestaande notities', () {
      final out = trimBulletExplanations(
        bulletsWith([
          'Term: uitgebreide uitleg over het onderwerp',
        ], notes: 'Bestaande notitie'),
      );
      expect(
        out.notes,
        'Bestaande notitie\n- Term: uitgebreide uitleg over het onderwerp',
      );
    });

    test('de tussenkop gaat als context mee naar de notities', () {
      // Zonder de kop leest de spreker een vlakke lijst zinnen en weet hij niet
      // meer bij welk deel van de slide ze hoorden.
      final out = trimBulletExplanations(
        bulletsWith([
          groupHeadingBullet('Techniek'),
          'Autorisatie: geregeld via de centrale IAM-oplossing',
          groupHeadingBullet('Beleid'),
          'Naleving: jaarlijks getoetst door de interne auditdienst',
        ]),
      );
      expect(
        out.notes,
        [
          'Techniek',
          '- Autorisatie: geregeld via de centrale IAM-oplossing',
          'Beleid',
          '- Naleving: jaarlijks getoetst door de interne auditdienst',
        ].join('\n'),
      );
    });

    test('de kop komt één keer mee, hoeveel bullets er ook onder vallen', () {
      final out = trimBulletExplanations(
        bulletsWith([
          groupHeadingBullet('Techniek'),
          'Autorisatie: geregeld via de centrale IAM-oplossing',
          'Logging: bewaard gedurende twaalf volle maanden',
        ]),
      );
      expect('Techniek\n'.allMatches(out.notes), hasLength(1));
      expect(out.notes.startsWith('Techniek\n'), isTrue);
    });

    test('een kop zonder bullets eronder blijft uit de notities', () {
      final out = trimBulletExplanations(
        bulletsWith([
          groupHeadingBullet('Leeg'),
          'Gewone bullet zonder meer',
          groupHeadingBullet('Techniek'),
          'Autorisatie: geregeld via de centrale IAM-oplossing',
        ]),
      );
      expect(out.notes.contains('Leeg'), isFalse);
      expect(out.notes.startsWith('Techniek\n'), isTrue);
    });

    test('een naamloze scheidingsstreep levert geen lege regel op', () {
      final out = trimBulletExplanations(
        bulletsWith([
          groupHeadingBullet(''),
          'Autorisatie: geregeld via de centrale IAM-oplossing',
        ]),
      );
      expect(
        out.notes,
        '- Autorisatie: geregeld via de centrale IAM-oplossing',
      );
    });

    test('de notitieregel houdt het inspring-niveau van zijn bullet', () {
      final out = trimBulletExplanations(
        bulletsWith(['\tRisico: de sleutel staat in de repository geschreven']),
      );
      expect(
        out.notes,
        '\t- Risico: de sleutel staat in de repository geschreven',
      );
    });

    test(
      'een volzin zonder scheidingsteken houdt zijn eerste vijf woorden',
      () {
        // Juist de regel die van de slide af moet — een volzin als bullet — had
        // geen dubbele punt om op te knippen, dus bleef de fix weg waar hij het
        // hardst nodig was.
        final out = trimBulletExplanations(
          bulletsWith([
            'Wij hebben besloten de infrastructuur te migreren omdat dat '
                'goedkoper uitpakt',
          ]),
        );
        expect(out.bullets, ['Wij hebben besloten de infrastructuur']);
        expect(
          out.notes,
          '- Wij hebben besloten de infrastructuur te migreren omdat dat '
          'goedkoper uitpakt',
        );
      },
    );

    test('een korte regel zonder scheidingsteken blijft ongemoeid', () {
      // Zeven woorden is de ondergrens: vijf label plus twee uitleg.
      final kort = bulletsWith(['Een bullet van maar zes woorden']);
      expect(canTrimBulletExplanations(kort), isFalse);
      expect(trimBulletExplanations(kort).bullets, kort.bullets);

      final net = bulletsWith(['Een bullet met precies zeven woorden hier']);
      expect(canTrimBulletExplanations(net), isTrue);
      expect(trimBulletExplanations(net).bullets, [
        'Een bullet met precies zeven',
      ]);
    });

    test('een scheidingsteken wint van de woordentelling', () {
      // Met een dubbele punt blijft het label het label, niet de eerste vijf.
      final out = trimBulletExplanations(
        bulletsWith(['Autorisatie: geregeld via de centrale IAM-oplossing']),
      );
      expect(out.bullets, ['Autorisatie']);
    });

    test('werkt over beide kolommen', () {
      final slide = Slide.create(SlideType.twoBullets).copyWith(
        bullets: ['Links: de eerste uitgebreide toelichting hier'],
        bullets2: ['Rechts: de tweede uitgebreide toelichting hier'],
      );
      final out = trimBulletExplanations(slide);
      expect(out.bullets, ['Links']);
      expect(out.bullets2, ['Rechts']);
      expect(out.notes.contains('eerste uitgebreide'), isTrue);
      expect(out.notes.contains('tweede uitgebreide'), isTrue);
    });
  });
}
