import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// Massa-persoonsgegevens.
//
// Eén e-mailadres is een contactgegeven. Veertig e-mailadressen in een tabel is
// een geëxporteerde ledenlijst — een heel ander gesprek. De scanner ziet die
// veertig al, veertig keer, maar veertig losse meldingen zijn precies wat een
// gebruiker leert wegklikken. Wat ontbrak was het inzicht dat erbovenop ligt.
void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanSlide(Slide slide) =>
      scanner.scan(Deck(title: 'D', slides: [slide]));

  Slide tabel(List<String> kop, List<List<String>> rijen) =>
      Slide.create(SlideType.table).copyWith(tableRows: [kop, ...rijen]);

  group('bulk.table_column — de tabelkop is het sterkste signaal', () {
    test('een naamkolom met genoeg rijen is een ledenlijst', () {
      // Niemand noemt een kolom "BSN" als er geen BSN's in staan. Dat maakt dit
      // vrijwel vals-positief-vrij, en het is precies het scenario dat ertoe doet:
      // een geplakte CSV.
      final result = scanSlide(
        tabel(
          ['Naam', 'E-mail', 'BSN'],
          [
            ['Jan', 'j@politie.nl', '728398242'],
            ['Piet', 'p@politie.nl', '100000009'],
            ['Klaas', 'k@politie.nl', '123456782'],
          ],
        ),
      );

      final bulk = result.findings.firstWhere(
        (f) => f.ruleId == 'bulk.table_column',
      );
      expect(bulk.family, PrivacyFamily.bulk);
      expect(bulk.confidence, PrivacyConfidence.certain);
      // Het aantal, niet de waarden: dít is wat de gebruiker moet weten.
      expect(bulk.maskedSample, '3×3');
    });

    test('een tabel zonder persoonsgegeven-kop is gewoon een tabel', () {
      final result = scanSlide(
        tabel(
          ['Kwartaal', 'Omzet', 'Groei'],
          [
            ['Q1', '1.2M', '4%'],
            ['Q2', '1.4M', '9%'],
            ['Q3', '1.5M', '7%'],
          ],
        ),
      );
      expect(result.firedRules, isEmpty);
    });

    test('één voorbeeldrij onder de kop is geen lijst', () {
      // Een uitleg-slide die laat zien hóé een tabel eruitziet, mag niet afgaan.
      final result = scanSlide(
        tabel(
          ['Naam', 'E-mail'],
          [
            ['Jan Jansen', 'jan@example.com'],
          ],
        ),
      );
      expect(
        result.findings.where((f) => f.ruleId == 'bulk.table_column'),
        isEmpty,
      );
    });

    test('herkent koppen in andere talen', () {
      final result = scanSlide(
        tabel(
          ['Name', 'Date of birth'],
          [
            ['A', '1985'],
            ['B', '1990'],
            ['C', '1992'],
          ],
        ),
      );
      expect(result.firedRules, contains('bulk.table_column'));
    });
  });

  group('bulk.repeat — de geplakte lijst die geen tabel is', () {
    test('drie adressen in bullets is massa', () {
      final result = scanSlide(
        Slide.create(SlideType.bullets).copyWith(
          bullets: [
            'j.jansen@politie.nl',
            'p.smit@politie.nl',
            'k.bakker@politie.nl',
          ],
        ),
      );

      final bulk = result.findings.firstWhere((f) => f.ruleId == 'bulk.repeat');
      expect(bulk.family, PrivacyFamily.bulk);
      expect(bulk.maskedSample, '3× contact.email');

      // De losse bevindingen blijven ook staan — de massa-melding komt eróverheen,
      // niet in plaats ervan.
      expect(
        result.findings.where((f) => f.ruleId == 'contact.email'),
        hasLength(3),
      );
    });

    test('een gewone contactslide is geen massa', () {
      // Naam, mail, telefoon van één persoon: dat is een contactslide, niet een
      // ledenlijst. De drempel moet die met rust laten.
      final result = scanSlide(
        Slide.create(SlideType.bullets).copyWith(
          bullets: [
            'Jan Jansen',
            'j.jansen@politie.nl',
            'Bereikbaar op werkdagen',
          ],
        ),
      );
      expect(
        result.findings.where((f) => f.family == PrivacyFamily.bulk),
        isEmpty,
      );
    });

    test('één melding per regel, niet één per treffer', () {
      // Veertig losse massa-meldingen zouden precies het probleem zijn dat we
      // wilden oplossen.
      final result = scanSlide(
        Slide.create(SlideType.bullets).copyWith(
          bullets: [for (var i = 0; i < 10; i++) 'persoon$i@politie.nl'],
        ),
      );
      expect(
        result.findings.where((f) => f.ruleId == 'bulk.repeat'),
        hasLength(1),
      );
      expect(
        result.findings
            .firstWhere((f) => f.ruleId == 'bulk.repeat')
            .maskedSample,
        '10× contact.email',
      );
    });

    test('informatieve hints tellen niet mee', () {
      // Drie 9-cijferige getallen zonder contextwoord zijn geen ledenlijst — we
      // weten zelf niet eens of het BSN's zijn.
      final result = scanSlide(
        Slide.create(SlideType.bullets).copyWith(
          bullets: ['Order 728398242', 'Order 100000009', 'Order 123456790'],
        ),
      );
      expect(
        result.findings.where((f) => f.family == PrivacyFamily.bulk),
        isEmpty,
      );
    });

    test('een gebruikerspad drie keer is geen ledenlijst', () {
      // Structurele bevindingen tellen bewust niet mee: drie paden zijn drie
      // paden, geen massa-persoonsgegevens.
      final result = scanSlide(
        Slide.create(SlideType.freeMarkdown).copyWith(
          customMarkdown:
              '/Users/jan.jansen/a.png\n'
              '/Users/jan.jansen/b.png\n'
              '/Users/jan.jansen/c.png',
        ),
      );
      expect(
        result.findings.where((f) => f.family == PrivacyFamily.bulk),
        isEmpty,
      );
    });
  });

  test('uitzetten werkt ook op de massa-regel', () {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['a@politie.nl', 'b@politie.nl', 'c@politie.nl']);
    final result = const PrivacyScanner(
      disabledRules: {'bulk.repeat'},
    ).scan(Deck(title: 'D', slides: [slide]));

    expect(result.findings.where((f) => f.ruleId == 'bulk.repeat'), isEmpty);
    expect(
      result.findings.where((f) => f.ruleId == 'contact.email'),
      hasLength(3),
    );
  });
}
