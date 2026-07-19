// Wat de auteur zelf markeert, hoeft geen melding meer (OCIWACHT §6.4).
//
// De `[[…]]`-markering is de sterkste beslissing die de feature kent: ze
// redigeert onvoorwaardelijk, ongeacht welke regel vuurt of welke stand de slide
// heeft. Er dan alsnog over waarschuwen vraagt de auteur iets te doen aan iets
// wat hij net gedáán heeft — en dat is precies het soort melding waardoor mensen
// de hele controle uitzetten.
//
// De onderdrukking zit in `_finding`, op de plek waar ook de eigen identiteit
// wordt weggefilterd. Dat is bewust één plek: elke regel die een waarde uit de
// tekst haalt loopt daardoorheen, dus een nieuwe regel erft dit gratis. De
// tests hieronder dekken daarom meerdere families — niet omdat elke familie
// eigen logica heeft, maar om te bewaken dat die aanname klopt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  Set<String> rulesIn(String text) => scanner
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .firedRules;

  group('een gemarkeerde waarde zwijgt', () {
    test('e-mailadres', () {
      expect(rulesIn('Contact: marieke@acme.nl'), contains('contact.email'));
      expect(
        rulesIn('Contact: [[marieke@acme.nl]]'),
        isNot(contains('contact.email')),
      );
    });

    test('IBAN', () {
      // Geldig NL-IBAN (mod-97 klopt) en géén voorbeeld-IBAN uit de allowlist.
      const iban = 'NL18RABO0123459876';
      expect(rulesIn('Rekening $iban'), contains('fin.iban'));
      expect(rulesIn('Rekening [[$iban]]'), isNot(contains('fin.iban')));
    });

    test('een BSN met contextwoord', () {
      expect(rulesIn('BSN 728398242'), contains('nl.bsn'));
      expect(rulesIn('BSN [[728398242]]'), isNot(contains('nl.bsn')));
    });
  });

  test('een tweede, ongemarkeerde waarde blijft wél gemeld', () {
    // Dit is de reden dat de onderdrukking op **positie** werkt en niet op
    // waarde. Zou hij op tekst vergelijken, dan zou één markering alle
    // voorkomens van dezelfde waarde laten verdwijnen — een vals-negatieve die
    // niemand ziet, want er staat dan gewoon niets in het paneel.
    expect(
      rulesIn('Van [[marieke@acme.nl]] naar jan@acme.nl'),
      contains('contact.email'),
    );
  });

  test('tekst buiten de markering op dezelfde regel telt gewoon mee', () {
    expect(
      rulesIn('[[marieke@acme.nl]] en rekening NL18RABO0123459876'),
      contains('fin.iban'),
    );
  });

  test('een losse blokhaak is geen markering', () {
    // De regex eist een gesloten paar zonder nesting. Een halve markering mag
    // niet per ongeluk de rest van de regel stilzetten — dan zou een typefout
    // in de markup een gegeven onzichtbaar maken.
    expect(rulesIn('[[marieke@acme.nl'), contains('contact.email'));
    expect(rulesIn('marieke@acme.nl]]'), contains('contact.email'));
  });

  test('een gewone markdown-link blijft gewoon gescand', () {
    // `[tekst](url)` heeft enkele haken en valt dus buiten het patroon.
    expect(
      rulesIn('[mail mij](mailto:marieke@acme.nl)'),
      contains('contact.email'),
    );
  });
}
