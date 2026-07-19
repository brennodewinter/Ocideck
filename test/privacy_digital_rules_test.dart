// Digitale identificatoren (OCIWACHT §3-E).
//
// De patronen in deze familie zijn triviaal en de uitsluitingen zijn alles. Een
// versienummer is vier getallen met punten; een tijdstip is twee getallen met
// een dubbele punt; een git-hash is hex; een UUID is net zo vaak een primaire
// sleutel als een advertentie-ID. Deze test bestaat dus vooral uit negatieven,
// en dat is niet uit voorzichtigheid maar omdat dáár de regel staat of valt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanText(String text) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [
        Slide.create(SlideType.bullets).copyWith(bullets: [text]),
      ],
    ),
  );

  Set<String> rulesIn(String text) => scanText(text).firedRules;

  PrivacyConfidence? confidenceOf(String text, String ruleId) {
    final matches = scanText(text).findings.where((f) => f.ruleId == ruleId);
    return matches.isEmpty ? null : matches.first.confidence;
  }

  group('digital.ipv4', () {
    test('vindt een publiek adres', () {
      expect(rulesIn('Verbinding vanaf 8.8.4.4'), contains('digital.ipv4'));
      expect(
        rulesIn('Bron 51.15.230.11 geblokkeerd'),
        contains('digital.ipv4'),
      );
    });

    test('de RFC 5737-documentatiereeksen tellen niet', () {
      // Elke handleiding ter wereld gebruikt deze. Een scanner die erop afgaat,
      // gaat af op de voorbeelden in zijn eigen documentatie.
      expect(rulesIn('Bijvoorbeeld 192.0.2.1'), isEmpty);
      expect(rulesIn('of 198.51.100.42'), isEmpty);
      expect(rulesIn('of 203.0.113.7'), isEmpty);
    });

    test('loopback, broadcast en link-local tellen niet', () {
      expect(rulesIn('Draait op 127.0.0.1'), isEmpty);
      expect(rulesIn('Luistert op 0.0.0.0'), isEmpty);
      expect(rulesIn('Masker 255.255.255.255'), isEmpty);
      expect(rulesIn('Kreeg 169.254.13.9 toegewezen'), isEmpty);
    });

    test('een versienummer is geen adres', () {
      expect(rulesIn('Versie 10.0.19041.1 is uitgerold'), isEmpty);
      expect(rulesIn('Draait v1.2.3.4 in productie'), isEmpty);
      expect(rulesIn('Build 4.8.1.2 getest'), isEmpty);
    });

    test('een octet boven 255 is geen adres', () {
      expect(rulesIn('Artikel 1.2.3.999 uit de norm'), isEmpty);
      expect(rulesIn('Zie 300.1.1.1'), isEmpty);
    });

    test('een privéadres meldt wel, maar onderbreekt niet', () {
      // Interne infrastructuur is geen persoonsgegeven. De melding hoort er te
      // zijn — een intern adresplan in een publieke slide blijft een lek — maar
      // ze mag niemand onderbreken.
      expect(
        confidenceOf('Gateway 192.168.1.1', 'digital.ipv4'),
        PrivacyConfidence.possible,
      );
      expect(
        confidenceOf('Node 10.4.2.9 in het cluster', 'digital.ipv4'),
        PrivacyConfidence.possible,
      );
      expect(
        confidenceOf('Host 172.16.0.5', 'digital.ipv4'),
        PrivacyConfidence.possible,
      );
    });
  });

  group('digital.ipv6', () {
    test('vindt een publiek adres', () {
      expect(
        rulesIn('Bereikbaar op 2a02:a45f:12:1::5'),
        contains('digital.ipv6'),
      );
    });

    test('het RFC 3849-documentatiebereik telt niet', () {
      expect(rulesIn('Bijvoorbeeld 2001:db8::1'), isEmpty);
      expect(rulesIn('of 2001:0db8:85a3::8a2e:370:7334'), isEmpty);
    });

    test('loopback en link-local tellen niet', () {
      expect(rulesIn('Luistert op ::1'), isEmpty);
      expect(rulesIn('Kreeg fe80::1c2d toegewezen'), isEmpty);
    });

    test('een tijdstip is geen adres', () {
      expect(rulesIn('De vergadering begint om 14:30 uur'), isEmpty);
      expect(rulesIn('Duur 01:02:03 gemeten'), isEmpty);
    });
  });

  group('digital.mac', () {
    test('vindt een MAC-adres in beide notaties', () {
      expect(rulesIn('Adapter 3C:22:FB:8A:11:04'), contains('digital.mac'));
      expect(rulesIn('Adapter 3c-22-fb-8a-11-04'), contains('digital.mac'));
    });

    test('alles nul en alles f wijzen geen apparaat aan', () {
      expect(rulesIn('Leeg: 00:00:00:00:00:00'), isEmpty);
      expect(rulesIn('Broadcast ff:ff:ff:ff:ff:ff'), isEmpty);
    });

    test('een git-hash is geen MAC', () {
      expect(rulesIn('Commit d1705c52aa3f houdt stand'), isEmpty);
    });
  });

  group('digital.imei en digital.iccid', () {
    test('een IMEI met geldige Luhn is zeker', () {
      // 490154203237518 is de standaard IMEI-testwaarde met kloppende Luhn.
      expect(
        confidenceOf('IMEI 490154203237518', 'digital.imei'),
        PrivacyConfidence.certain,
      );
    });

    test('vijftien cijfers zonder Luhn zijn geen IMEI', () {
      expect(rulesIn('Meldnummer 490154203237519'), isEmpty);
      expect(rulesIn('Transactie 123456789012345'), isEmpty);
    });

    test('een Amex-kaartnummer is geen IMEI', () {
      // Vijftien cijfers met een geldige Luhn — precies een IMEI, op het
      // IIN-bereik na. Amex is het enige kaartmerk met vijftien cijfers, dus
      // 34/37 uitsluiten ruimt de hele botsing op. Het testnummer hieronder
      // stáát in OCIWACHT.md, en de corpustest ging er dan ook op af.
      expect(rulesIn('Testkaart 378282246310005'), isEmpty);

      // Sinds `fin.pan` bestaat vuurt de andere helft van die botsing wél, en
      // dat is precies de bedoeling: één van de twee regels pakt het nummer op,
      // nooit allebei. Vóór `fin.pan` viel dit nummer tussen wal en schip.
      final amex = rulesIn('Kaart 343434343434343');
      expect(amex, isNot(contains('digital.imei')));
      expect(amex, contains('fin.pan'));
    });

    test('een ICCID begint met 89 en draagt een Luhn', () {
      expect(
        confidenceOf('SIM 8931440000000000006', 'digital.iccid'),
        PrivacyConfidence.certain,
      );
    });
  });

  group('digital.imsi', () {
    test('vuurt alleen met een contextwoord', () {
      // Zonder context is dit niet van een transactienummer te onderscheiden.
      expect(rulesIn('Reeks 204080123456789'), isEmpty);
      expect(rulesIn('IMSI 204080123456789'), contains('digital.imsi'));
    });
  });

  group('digital.handle', () {
    test('vindt een profiel-URL', () {
      expect(
        rulesIn('Zie https://linkedin.com/in/mariekedevries'),
        contains('digital.handle'),
      );
      expect(
        rulesIn('Volg https://mastodon.social/@iemand'),
        contains('digital.handle'),
      );
    });

    test('vindt een kale handle', () {
      expect(rulesIn('Bereikbaar via @mariekedv'), contains('digital.handle'));
    });

    test('een annotatie in code is geen handle', () {
      expect(rulesIn('@override\nvoid build() {}'), isEmpty);
      expect(rulesIn('@param naam de naam'), isEmpty);
      expect(rulesIn('@Deprecated gebruik iets anders'), isEmpty);
    });

    test('de @ van een e-mailadres hoort bij het adres', () {
      // Precies één bevinding: het e-mailadres. Geen losse handle erbij.
      final rules = rulesIn('Mail naar marieke@acme.nl');
      expect(rules, contains('contact.email'));
      expect(rules, isNot(contains('digital.handle')));
    });
  });

  group('digital.deviceid', () {
    test('een UUID met advertentiecontext is een device-ID', () {
      expect(
        rulesIn('IDFA 6D92078A-8246-4BA4-AE5B-76104861E7DC'),
        contains('digital.deviceid'),
      );
    });

    test('een kale UUID is te generiek om iets te betekenen', () {
      // Net zo goed een primaire sleutel, een bestandsnaam of een sessie-id.
      expect(rulesIn('Record 6D92078A-8246-4BA4-AE5B-76104861E7DC'), isEmpty);
    });
  });
}
