import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_contact_rules.dart';
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
    test('een straat met een postcode erachter is één zeker adres', () {
      // Let op de vorm: dit was ooit twéé bevindingen die elkaar naar `certain`
      // duwden. Dat leverde twee losse blokjes op en liet de woonplaats staan.
      // Sinds `fullAddressPattern` is het één span van straat tot en met plaats
      // — zie `privacy_contact_rules.dart`: een adres in stukjes redigeren
      // redigeert geen adres.
      const text = 'Kalverstraat 12, 1234 AB Amsterdam';
      final result = scanText(text);
      final addresses = result.findings
          .where((f) => f.ruleId == 'contact.address')
          .toList();

      expect(addresses, hasLength(1));
      expect(addresses.single.confidence, PrivacyConfidence.certain);
      expect(result.certain, isNotEmpty);

      // De span dekt het hele adres, niet alleen de straat of alleen de postcode.
      expect(
        text.substring(addresses.single.start, addresses.single.end),
        text,
      );

      // En de postcode wordt niet nóg eens los gemeld: hij valt al onder het
      // adres, en een tweede melding over dezelfde tekens is ruis.
      expect(
        result.findings.where((f) => f.ruleId == 'contact.postcode_nl'),
        isEmpty,
      );
    });

    test('de afgewezen achtervoegsels blijven afgewezen', () {
      // Een lijst met een reden erbij is pas een afspraak als iets hem bewaakt.
      // Zonder deze test voegt de volgende lezer `markt` "even" toe en meldt de
      // scanner voortaan de arbeidsmarkt als woonadres.
      for (final suffix in rejectedStreetSuffixes) {
        expect(
          dutchStreetSuffixes,
          isNot(contains(suffix)),
          reason:
              '"$suffix" is afgewezen — lees de reden in privacy_contact_rules',
        );
      }
      // En de vorm die ze zou opleveren blijft stil.
      expect(rulesIn('Vergadering 12 gaat niet door'), isEmpty);
      expect(rulesIn('Arbeidsmarkt 2025 in cijfers'), isEmpty);
      expect(rulesIn('Amsterdam 2025 was een recordjaar'), isEmpty);
    });

    test('een straat zonder bekend achtervoegsel wordt niet gemist', () {
      // De melding die deze hele regel heeft opgeleverd. `Weidemolen` eindigt
      // niet op een achtervoegsel dat in de lijst stond, waardoor er géén
      // adresbevinding was, de postcode ernaast op `possible` bleef steken en
      // het adres uit het exportrapport viel. Een stille lek, door één woord.
      const text = 'Woonadres: Weidemolen 12, 1234 AB Amsterdam';
      final result = scanText(text);
      final address = result.findings.singleWhere(
        (f) => f.ruleId == 'contact.address',
      );

      expect(address.confidence, PrivacyConfidence.certain);
      // Het label blijft staan, de waarde gaat er integraal onder: de ontvanger
      // mag zien dát hier een woonadres weg is.
      expect(
        text.substring(address.start, address.end),
        'Weidemolen 12, 1234 AB Amsterdam',
      );
    });

    test('het postcode-anker heeft de straatnamenlijst niet nodig', () {
      // Geen van deze straten eindigt op een achtervoegsel uit de lijst. De
      // postcode erachter is wat ze tot adres maakt.
      for (final text in [
        'Zonnedauw 8, 3435 RX Nieuwegein',
        'De Savornin Lohmanplein 3, 2566 AB Den Haag',
        'Kleine Berg 44a, 5611 JV Eindhoven',
      ]) {
        final result = scanText(text);
        expect(
          result.findings.where(
            (f) =>
                f.ruleId == 'contact.address' &&
                f.confidence == PrivacyConfidence.certain,
          ),
          isNotEmpty,
          reason: 'geen zeker adres gevonden in "$text"',
        );
      }
    });

    test('een adreslabel zonder woonplaats telt ook', () {
      final result = scanText('Woonadres: Zonnedauw 8');
      final address = result.findings.singleWhere(
        (f) => f.ruleId == 'contact.address',
      );
      // "Woonadres" is per definitie van een persoon, dus dit hoeft geen
      // postcode ter bevestiging.
      expect(address.confidence, PrivacyConfidence.certain);
    });

    test('een zin óver adressen is geen adres', () {
      // Deze regel ging in haar eerste vorm af op de eigen documentatie: daar
      // staan zinnen als "een `Woonadres:`-label", en het label alleen maakte
      // dat al `certain`. Hetzelfde gold voor een leeg formulierveld.
      //
      // Deze test staat hier los van het docs-corpus met opzet. Die corpustest
      // kent een uitzonderingslijst per document, en een uitzondering kan een
      // teruggekeerde vals-positief maskeren — dan is de suite groen om de
      // verkeerde reden. Dit is de directe toets, zonder ontsnappingsluik.
      for (final text in [
        'Gebruik een `Woonadres:`-label om dit af te dwingen',
        'Woonadres:',
        'Woonadres: ',
        'Adres: onbekend',
        'Het veld Woonadres is verplicht',
      ]) {
        expect(
          scanText(text).certain.where((f) => f.ruleId == 'contact.address'),
          isEmpty,
          reason: 'ten onrechte een zeker adres in "$text"',
        );
      }
    });

    test('een kaal Adres-label zonder pandaanwijzing blijft een hint', () {
      // Dit kan het kantoor zijn, en een scanner die daarop rood kleurt wordt
      // uitgezet. Zie de vals-positieven-strategie in privacy_contact_rules.
      final result = scanText('Adres: zie de contactpagina');
      expect(
        result.findings
            .where((f) => f.ruleId == 'contact.address')
            .every((f) => f.confidence == PrivacyConfidence.possible),
        isTrue,
      );
      expect(result.certain, isEmpty);
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

    test('ook de woonplaats gaat eronder, niet alleen de postcode', () {
      // De slide uit de melding. Vóór het postcode-anker leverde dit
      // `Woonadres: Weidemolen 12, ██████ Amsterdam` op — straat,
      // huisnummer én plaats gewoon leesbaar. Een half geredigeerd adres is
      // geen geredigeerd adres.
      final deck = Deck(
        title: 'Briefing',
        privacy: PrivacyDisposition.redact,
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(bullets: ['Woonadres: Weidemolen 12, 1234 AB Amsterdam']),
        ],
      );

      final line = PrivacyProjection.forAudience(
        deck,
      ).slides.single.bullets.single;

      expect(line.contains('Weidemolen'), isFalse);
      expect(line.contains('12'), isFalse);
      expect(line.contains('1234 AB'), isFalse);
      expect(line.contains('Amsterdam'), isFalse);
      // Het label blijft juist wél staan: de ontvanger mag zien dát hier een
      // woonadres is weggehaald.
      expect(line, startsWith('Woonadres:'));
    });

    test('een niet-geredigeerde slide meldt het adres wél als zeker', () {
      // De stille kant van dezelfde bug: zonder adresbevinding bleef de
      // postcode `possible`, en `possible` valt uit het exportrapport. De
      // gebruiker kreeg dus nooit de vraag of dit weg moest.
      final deck = Deck(
        title: 'Briefing',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(bullets: ['Woonadres: Weidemolen 12, 1234 AB Amsterdam']),
        ],
      );

      expect(PrivacyScanner().scan(deck).certain, isNotEmpty);
    });
  });
}
