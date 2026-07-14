import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

/// Per regel minstens één positief en dríé negatieven. De negatieven zijn de
/// eigenlijke test: een scanner die alles vindt is even nutteloos als een die
/// niets vindt, want hij wordt uitgezet.
void main() {
  const scanner = PrivacyScanner();

  /// Scant één tekst als de titel van één slide.
  PrivacyScanResult scanText(String text) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [Slide.create(SlideType.bullets).copyWith(title: text)],
    ),
  );

  Set<String> rulesIn(String text) => scanText(text).firedRules;

  group('contact.email', () {
    test('vindt een gewoon adres', () {
      final result = scanText('Mail naar jan.jansen@politie.nl voor vragen.');
      expect(result.firedRules, contains('contact.email'));
      expect(result.findings.single.confidence, PrivacyConfidence.certain);
      expect(result.findings.single.family, PrivacyFamily.contact);
    });

    test('maskeert de waarde in plaats van hem te bewaren', () {
      final finding = scanText('jan.jansen@politie.nl').findings.single;
      expect(finding.maskedSample, 'j…l');
      expect(finding.maskedSample.contains('jansen'), isFalse);
    });

    test('negeert voorbeelddomeinen', () {
      expect(rulesIn('Mail naar jan@example.com'), isEmpty);
      expect(rulesIn('test@example.org en a@foo.invalid'), isEmpty);
      expect(rulesIn('root@localhost'), isEmpty);
    });

    test('negeert onpersoonlijke postbussen', () {
      expect(rulesIn('noreply@politie.nl'), isEmpty);
      expect(rulesIn('abuse@politie.nl'), isEmpty);
    });

    test('vuurt niet op gewone tekst met een apenstaartje', () {
      expect(rulesIn('Zie @override in de code'), isEmpty);
      expect(rulesIn('E-mailadres: nog invullen'), isEmpty);
    });
  });

  group('fin.iban', () {
    test('vindt een geldig IBAN, ook met spaties', () {
      // Een echt geldig, niet-voorbeeld NL-IBAN (mod-97 klopt).
      expect(rulesIn('Rekening NL18RABO0123459876'), contains('fin.iban'));
      expect(rulesIn('NL18 RABO 0123 4598 76'), contains('fin.iban'));
    });

    test('negeert het voorbeeld-IBAN uit elke handleiding', () {
      // Zou dit vuren, dan kleurt onze eigen documentatie rood — en dan gelooft
      // niemand de volgende melding meer.
      expect(rulesIn('bijv. NL91ABNA0417164300'), isEmpty);
      expect(rulesIn('DE89370400440532013000'), isEmpty);
    });

    test('negeert iets dat op een IBAN lijkt maar de checksum niet haalt', () {
      expect(rulesIn('NL92ABNA0417164300'), isEmpty);
      expect(rulesIn('AB12CDEF3456789012'), isEmpty);
    });

    test('vuurt niet op een gewone hoofdletterreeks', () {
      expect(rulesIn('Zie NEN 7510 en ISO 27001'), isEmpty);
    });
  });

  group('nl.bsn — de contextpoort', () {
    // 728398242 doorstaat de 11-proef en staat op geen enkele voorbeeldlijst.
    const geldig = '728398242';

    test('met contextwoord is het een zekere melding', () {
      final result = scanText('BSN $geldig van betrokkene');
      final finding = result.findings.single;
      expect(finding.ruleId, 'nl.bsn');
      expect(finding.confidence, PrivacyConfidence.certain);
      expect(finding.family, PrivacyFamily.identifier);
    });

    test('herkent de context ook voluit geschreven', () {
      final result = scanText('Het burgerservicenummer is $geldig.');
      expect(result.findings.single.confidence, PrivacyConfidence.certain);
    });

    test('zónder contextwoord blijft het informatief', () {
      // DIT is de kern. Ongeveer één op de elf willekeurige 9-cijferige getallen
      // doorstaat de 11-proef. Zou dit een waarschuwing geven, dan vuurt de
      // scanner op elk elfde ordernummer — en wordt hij uitgezet.
      final result = scanText('Ordernummer $geldig is verwerkt.');
      expect(result.findings.single.confidence, PrivacyConfidence.possible);
      expect(result.certain, isEmpty);
    });

    test('een contextwoord ver weg telt niet mee', () {
      final ver =
          'BSN staat elders in het dossier vermeld, '
          'en dit is een heel ander getal: $geldig';
      expect(
        scanText(ver).findings.single.confidence,
        PrivacyConfidence.possible,
      );
    });

    test('negeert het officiële testbereik', () {
      expect(rulesIn('BSN 999999990'), isEmpty);
      expect(rulesIn('BSN 999999011'), isEmpty);
    });

    test('negeert het voorbeeld-BSN van het internet', () {
      // 123456782 haalt de 11-proef — het is zo gekozen — en staat overal als
      // "een geldig BSN". Een oplopende-reeks-check vangt het niet.
      expect(rulesIn('BSN 123456782'), isEmpty);
    });

    test('negeert betekenisloze cijferreeksen', () {
      expect(rulesIn('BSN 111111111'), isEmpty);
      expect(rulesIn('BSN 123456789'), isEmpty);
    });

    test('negeert een getal dat de 11-proef niet haalt', () {
      expect(rulesIn('BSN 728398248'), isEmpty);
      expect(rulesIn('Factuur 100000001'), isEmpty);
    });

    test('vuurt niet op een langer getal', () {
      expect(rulesIn('Referentie 1728398242 en 7283982420'), isEmpty);
    });
  });

  group('velddekking', () {
    test('scant de sprekersnotities — die gaan mee in PPTX', () {
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(notes: 'BSN 728398242 niet noemen'),
        ],
      );
      final result = scanner.scan(deck);
      expect(result.findings.single.field, 'notes');
      expect(result.findings.single.confidence, PrivacyConfidence.certain);
    });

    test('scant bullets, tabelcellen en bijschriften met hun index', () {
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            bullets: ['eerste', 'mail a.bakker@politie.nl'],
            tableRows: [
              ['Naam', 'Mail'],
              ['Piet', 'p.smit@politie.nl'],
            ],
          ),
        ],
      );
      final result = scanner.scan(deck);
      final velden = {for (final f in result.findings) f.field};
      expect(velden, containsAll(<String>['bullets', 'tableRows']));

      final bullet = result.findings.firstWhere((f) => f.field == 'bullets');
      expect(bullet.fragmentIndex, 1);
    });

    test('scant de deckvelden die de documentmetadata voeden', () {
      final deck = Deck(
        title: 'Dossier',
        author: 'r.devries@politie.nl',
        slides: [Slide.create(SlideType.bullets)],
      );
      final result = scanner.scan(deck);
      expect(result.findings.single.field, 'author');
      expect(result.findings.single.isDeckWide, isTrue);
    });

    test('een schoon deck levert niets op', () {
      final deck = Deck(
        title: 'Kwartaalcijfers',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Resultaten',
            bullets: ['Omzet 1.2 miljoen', 'Groei 12% in Q3 2025'],
            notes: 'Rustig praten, 4 minuten.',
          ),
        ],
      );
      expect(scanner.scan(deck).isEmpty, isTrue);
    });
  });
}
