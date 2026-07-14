import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// De vals-positieven-regressietest.
//
// Een scanner die bij elk ordernummer "BSN!" roept, wordt binnen een week
// uitgezet — en detecteert daarna niets meer. Vals-positieven zijn in deze
// feature dus duurder dan vals-negatieven, en dat maakt dit de test die
// voorkomt dat een nieuwe regel de hele controle onbruikbaar maakt.
//
// De claim die hier bewaakt wordt: gewone zakelijke tekst levert GEEN zekere
// bevinding op. Een informatieve melding mag; die onderbreekt niemand.
void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scanLines(List<String> lines) => scanner.scan(
    Deck(
      title: 'Deck',
      slides: [Slide.create(SlideType.bullets).copyWith(bullets: lines)],
    ),
  );

  test('gewone zakelijke slides leveren geen zekere bevinding op', () {
    // Alles hieronder is aas: getallen en codes die op een persoonsgegeven
    // lijken maar het niet zijn. Dit is het materiaal waar een naïeve scanner
    // op stukloopt.
    final corpus = <String>[
      'Factuurnummer 100000001, betaald op 3 maart',
      'Ordernummer 202512345 staat klaar voor verzending',
      'Klantnummer 847362910 in het CRM',
      'Artikelcode 123-456-789 uit de catalogus',
      'Versie 1.2.3 is uitgerold naar productie',
      'CVE-2024-12345 is gepatcht in release 4.8.1',
      'Wij voldoen aan ISO 27001 en NEN 7510',
      'Omzet 1.250.000 euro, groei 12% ten opzichte van 2024',
      'De vergadering begint om 14:30 uur, zaal 3',
      'Telefoonnummer volgt nog',
      'Zie hoofdstuk 4, paragraaf 2.1, pagina 118',
      'BSN wordt niet verwerkt in dit proces',
      'Het IBAN van de leverancier staat in het contract',
      'Postcode en huisnummer zijn geanonimiseerd',
      'Referentie 2025-Q3-0042 bij de afdeling Inkoop',
      'Kubernetes 1.29 draait op 12 nodes',
      'Bereikbaar via het algemene nummer 0800 8844',
      'Contact: noreply@example.com voor testberichten',
      'Documentatie op https://example.com/handleiding',
      'Serienummer SN-2024-889231-XT van het apparaat',
      // Secrets-aas: uitleg over sleutels, zonder een sleutel.
      'Zet je API-sleutel in api_key: <your-key>',
      'export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE',
      'Gebruik sk_test_A1b2C3d4E5f6G7h8I9j0K1l2 in de sandbox',
      'const token = null; // nog niet ingevuld',
      'password: changeme',
      'Verbind met postgres://db.intern:5432/prod',
      'Het certificaat begint met -----BEGIN CERTIFICATE-----',
      'De publieke sleutel staat in -----BEGIN PUBLIC KEY-----',
      // EU-aas: getallen in de lengtes van de landnummers, zonder context.
      'Batchnummer 85073003032 uit de productie',
      'Transactie 44051401358 verwerkt',
      'Meldnummer 1800510123457 in het systeem',
      'Bereikbaar op 811218 9875 tijdens kantooruren',
      // Art.9-aas: een slide OVER privacy noemt precies onze trefwoorden.
      'Onder de AVG zijn gezondheidsgegevens bijzondere persoonsgegevens',
      'Denk aan een diagnose, een strafblad of vakbondslidmaatschap',
      'Biometrische gegevens vragen een DPIA',
      'Een veroordeling valt onder artikel 10',
      // Structureel aas: paden en links die niemand aanwijzen.
      'De build draait in /home/runner/work/repo',
      'Zie C:\\Users\\Public\\Documents voor het sjabloon',
      'Documentatie: https://ocideck.nl/docs?page=2&sort=date',
      'Bekijk https://drive.google.com voor cloudopslag',
      'Campagne via https://example.com/?utm_source=nieuwsbrief',
    ];

    final result = scanLines(corpus);

    expect(
      result.certain,
      isEmpty,
      reason:
          'Zekere bevindingen op gewone zakelijke tekst: '
          '${result.certain.map((f) => '${f.ruleId} (${f.maskedSample})').join(', ')}',
    );
  });

  test('onze eigen documentatie kleurt niet rood op haar eigen voorbeelden', () {
    // Een handleiding die de scanner laat afgaan op het voorbeeld-BSN uit die
    // handleiding, ondermijnt het vertrouwen in élke andere melding. De docs
    // zijn dus zelf een corpus.
    //
    // contact.email blijft hier buiten beschouwing: SECURITY.md hoort een echt
    // meldadres te bevatten, en dat is dan ook een echte treffer — geen
    // vals-positieve.
    final docs = Directory('docs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'));
    expect(docs, isNotEmpty, reason: 'geen docs gevonden om te scannen');

    for (final doc in docs) {
      final result = scanner.scan(
        Deck(
          title: 'Docs',
          slides: [
            Slide.create(
              SlideType.freeMarkdown,
            ).copyWith(customMarkdown: doc.readAsStringSync()),
          ],
        ),
      );
      final hits = result.certain
          .where((f) => f.ruleId != 'contact.email')
          .map((f) => f.ruleId)
          .toSet();
      expect(
        hits,
        isEmpty,
        reason: '${doc.path} laat de scanner afgaan op: ${hits.join(', ')}',
      );
    }
  });

  test('een lange lijst willekeurige getallen geeft geen zekere melding', () {
    // Ongeveer één op de elf 9-cijferige getallen doorstaat de 11-proef. Zonder
    // contextpoort zou deze lijst dus ~90 waarschuwingen opleveren. Met de poort
    // zijn het er nul.
    final getallen = <String>[];
    var x = 7;
    for (var i = 0; i < 1000; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      getallen.add('Transactie ${x % 900000000 + 100000000} verwerkt');
    }

    final result = scanLines(getallen);

    expect(result.certain, isEmpty);
    // Maar ze verdwijnen niet stilletjes: ze zijn er wél, als informatieve
    // melding. De contextpoort onderdrukt de ONDERBREKING, niet de detectie.
    expect(result.findings, isNotEmpty);
    expect(
      result.findings.every((f) => f.confidence == PrivacyConfidence.possible),
      isTrue,
    );
  });
}
