import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// Adres, postcode en persoonsnaam.
//
// Deze familie heeft geen checksum, dus de test bewaakt vooral de negatieven: een
// straatnaam-lookalike, een hexkleur die op een postcode lijkt, een hoofdletter
// die geen naam is. De centrale claim is die van het ontwerp: een adres of
// postcode alléén is hooguit een hint (`possible`); pas postcode én huisnummer
// samen zijn `certain`, want die wijzen in Nederland één woonadres aan.
void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanText(String text) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [Slide.create(SlideType.bullets).copyWith(title: text)],
    ),
  );

  Set<String> rulesIn(String text) => scanText(text).firedRules;

  PrivacyFinding? findingFor(String text, String ruleId) {
    final matches = scanText(
      text,
    ).findings.where((f) => f.ruleId == ruleId).toList();
    return matches.isEmpty ? null : matches.first;
  }

  group('contact.address', () {
    test('vindt een straatnaam met huisnummer', () {
      expect(rulesIn('Kalverstraat 12'), contains('contact.address'));
      expect(
        rulesIn('Woont aan de Beethovenlaan 3a'),
        contains('contact.address'),
      );
      expect(rulesIn('Stationsweg 100'), contains('contact.address'));
    });

    test('een los adres is hooguit een hint, geen onderbreking', () {
      final finding = findingFor('Kalverstraat 12', 'contact.address');
      expect(finding, isNotNull);
      expect(finding!.confidence, PrivacyConfidence.possible);
    });

    test('vuurt niet op een gewoon woord met een nummer', () {
      expect(rulesIn('Hoofdstuk 4 gaat over beleid'), isEmpty);
      expect(rulesIn('Zie pagina 118 en zaal 3'), isEmpty);
      expect(rulesIn('Beleid 12 is achterhaald'), isEmpty);
    });
  });

  group('contact.postcode_nl', () {
    test('vindt een Nederlandse postcode, met en zonder spatie', () {
      expect(rulesIn('Postbus, 1234 AB'), contains('contact.postcode_nl'));
      expect(rulesIn('1234AB'), contains('contact.postcode_nl'));
    });

    test('een losse postcode is een hint, geen onderbreking', () {
      final finding = findingFor('Postbus, 1234 AB', 'contact.postcode_nl');
      expect(finding, isNotNull);
      expect(finding!.confidence, PrivacyConfidence.possible);
    });

    test('een hexkleur is geen postcode', () {
      expect(rulesIn('De accentkleur is #2563EB'), isEmpty);
      expect(rulesIn('color: #1234ABxx'), isEmpty);
    });

    test('een niet-uitgegeven lettercombinatie telt niet', () {
      expect(rulesIn('code 1234 SS'), isEmpty);
      expect(rulesIn('code 1234 SD'), isEmpty);
    });

    test('een jaartal zonder letters is geen postcode', () {
      expect(rulesIn('In 2024 en 2025 groeide de omzet'), isEmpty);
      expect(rulesIn('Postbus 0123 AB bestaat niet'), isEmpty);
    });
  });

  group('postcode + huisnummer samen', () {
    test('een straat dicht bij een postcode escaleert beide naar zeker', () {
      final result = scanText('Kalverstraat 12, 1234 AB Amsterdam');
      final address = result.findings.firstWhere(
        (f) => f.ruleId == 'contact.address',
      );
      final postcode = result.findings.firstWhere(
        (f) => f.ruleId == 'contact.postcode_nl',
      );
      expect(address.confidence, PrivacyConfidence.certain);
      expect(postcode.confidence, PrivacyConfidence.certain);
      expect(result.certain, isNotEmpty);
    });

    test('een straat en een postcode ver uit elkaar escaleren niet', () {
      // Een voorbeeld hier, een ander tweehonderd tekens verderop: geen adres.
      final ver = 'Kalverstraat 12${' woorden ter opvulling' * 4} 1234 AB';
      final result = scanText(ver);
      expect(
        result.findings.every(
          (f) => f.confidence == PrivacyConfidence.possible,
        ),
        isTrue,
      );
      expect(result.certain, isEmpty);
    });
  });

  group('contact.name', () {
    test('vindt een naam achter een aanhef', () {
      expect(rulesIn('Zie dhr. Jansen voor vragen'), contains('contact.name'));
      expect(rulesIn('Mevrouw De Boer tekent'), contains('contact.name'));
    });

    test('vindt een naam achter een label', () {
      expect(
        rulesIn('Contactpersoon: Marieke de Vries'),
        contains('contact.name'),
      );
      expect(rulesIn('naam: Jan van der Berg'), contains('contact.name'));
    });

    test('een aanhef is een structurele uitspraak, geen gok', () {
      // `likely` en niet `possible`: de auteur schrijft er met "dhr." letterlijk
      // bij dat dit een persoon is. Nog steeds geen onderbreking — dat is aan
      // `certain` voorbehouden — maar wél genoeg om als persoonskoppeling te
      // tellen.
      final finding = findingFor('dhr. Jansen', 'contact.name');
      expect(finding, isNotNull);
      expect(finding!.confidence, PrivacyConfidence.likely);
      expect(finding.family, PrivacyFamily.contact);
      expect(scanText('dhr. Jansen').certain, isEmpty);
    });

    test('een persoonspredicaat wijst een naam aan zonder label', () {
      // De formulering waar artikel 10 over gaat draagt geen `naam:`-label.
      expect(
        rulesIn('Marieke de Vries wordt verdacht van diefstal'),
        contains('contact.name'),
      );
      expect(
        rulesIn('Sandra Bakker meldde zich ziek'),
        contains('contact.name'),
      );
    });

    test('een bevestigend e-mailadres maakt de naam zeker', () {
      // Twee onafhankelijke structuren die elkaar bevestigen: het lokale deel
      // zegt de naam terug. Dat is het sterkste bewijs dat deze familie kent.
      final finding = findingFor(
        'Neem contact op met Marieke de Vries, m.devries@acme.nl',
        'contact.name',
      );
      expect(finding, isNotNull);
      expect(finding!.confidence, PrivacyConfidence.certain);
    });

    test('een e-mailadres bevestigt alleen de naam die erin staat', () {
      // Zonder deze eis zou élke naam op de slide door élk adres bevestigd
      // worden, en dan is de poort geen poort meer.
      expect(
        findingFor('Peter Bakker, m.devries@acme.nl', 'contact.name'),
        isNull,
      );
    });

    test('een kale naam zonder structuur blijft buiten beeld', () {
      // §5.5 blijft staan: geen NER, en dus geen melding op een woord met een
      // hoofdletter alleen.
      expect(rulesIn('Marieke de Vries was er ook'), isEmpty);
      expect(rulesIn('Amsterdam Zuidoost groeit hard'), isEmpty);
    });

    test('een placeholder-persoon telt niet', () {
      expect(rulesIn('Bijvoorbeeld dhr. John Doe'), isEmpty);
      expect(rulesIn('naam: Jan Jansen'), isEmpty);
    });

    test('een kale hoofdletter zonder label is geen naam', () {
      expect(rulesIn('Jansen kwam langs met het rapport'), isEmpty);
      expect(rulesIn('Het Beleid is vastgesteld'), isEmpty);
    });

    test('maskeert de naam in plaats van hem te bewaren', () {
      final finding = findingFor(
        'Contactpersoon: Marieke de Vries',
        'contact.name',
      );
      expect(finding!.maskedSample.contains('Marieke'), isFalse);
    });
  });

  group('redactie haalt het woonadres en de naam weg', () {
    test('een slide op redact laat geen adres, postcode of naam staan', () {
      final deck = Deck(
        title: 'Briefing',
        privacy: PrivacyDisposition.redact,
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Dossier dhr. Jansen',
            bullets: ['Woont op Kalverstraat 12, 1234 AB Amsterdam'],
          ),
        ],
      );

      final audience = PrivacyProjection.forAudience(deck);
      final slide = audience.slides.single;
      final text = '${slide.title}\n${slide.bullets.join('\n')}';

      expect(text.contains('Kalverstraat 12'), isFalse);
      expect(text.contains('1234 AB'), isFalse);
      expect(text.contains('Jansen'), isFalse);
      expect(audience.hasRedactions, isTrue);
    });
  });
}
