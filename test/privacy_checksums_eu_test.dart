import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/privacy/privacy_checksums_eu.dart';

// De checksums van de Europese persoonsnummers.
//
// Elke geldige waarde hier is UITGEREKEND, niet verzonnen. Dat klinkt
// vanzelfsprekend maar is het niet: eerder in dit project stond er een "geldig"
// BSN in een test dat de 11-proef helemaal niet haalde, en pas de rode suite
// bracht dat aan het licht.
//
// Per land: één geldige waarde, en één die één cijfer verderop zit. Dat tweede
// is de eigenlijke test — een checksum die alles goedkeurt, keurt niets.

/// De kale mod-11 van de kennitala, zónder de datum- en eeuwcontrole.
///
/// Staat hier zodat een testwaarde die de checksum wél haalt maar op de datum
/// afvalt, dat ook kan bewijzen. Zonder dit onderscheid toont zo'n test alleen
/// dát hij afvalt, niet dat het de dátum was die hem tegenhield — en dan zou
/// een kapotte checksum de test net zo goed groen houden.
bool _haaltDeIsMod11(String d) {
  const w = [3, 2, 7, 6, 5, 4, 3, 2, 1, 0];
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += (d.codeUnitAt(i) - 0x30) * w[i];
  }
  return sum % 11 == 0;
}

void main() {
  /// Draait de checksum op een geldige waarde en op dezelfde waarde met een
  /// verminkt laatste cijfer.
  void checksum(
    String land,
    bool Function(String) valid,
    String geldig,
    String verminkt,
  ) {
    test(land, () {
      expect(valid(geldig), isTrue, reason: '$geldig hoort geldig te zijn');
      expect(valid(verminkt), isFalse, reason: '$verminkt hoort af te vallen');
      expect(valid(''), isFalse);
      expect(valid('rommel'), isFalse);
    });
  }

  group('checksum-gevalideerd', () {
    checksum(
      'België — rijksregisternummer (mod-97)',
      isValidBeRijksregister,
      '85073003031',
      '85073003032',
    );
    checksum(
      'Duitsland — Steuer-ID (ISO 7064 + cijferherhalingsregel)',
      isValidDeSteuerId,
      '49729806357',
      '49729806358',
    );
    checksum(
      'Frankrijk — NIR (mod-97)',
      isValidFrNir,
      '1 85 05 73 083 215 16',
      '1 85 05 73 083 215 17',
    );
    checksum(
      'Spanje — DNI (mod-23)',
      isValidEsDniNie,
      '12345678Z',
      '12345678A',
    );
    checksum(
      'Spanje — NIE (mod-23)',
      isValidEsDniNie,
      'Y1234567X',
      'Y1234567A',
    );
    checksum('Portugal — NIF (mod-11)', isValidPtNif, '501428178', '501428179');
    checksum(
      'Polen — PESEL (mod-10)',
      isValidPlPesel,
      '44051401359',
      '44051401358',
    );
    checksum(
      'Italië — codice fiscale (mod-26)',
      isValidItCodiceFiscale,
      'RSSMRA85T10A562S',
      'RSSMRA85T10A562A',
    );
    checksum(
      'Kroatië — OIB (ISO 7064)',
      isValidHrOib,
      '69828986577',
      '69828986576',
    );
    checksum(
      'Bulgarije — EGN (mod-11)',
      isValidBgEgn,
      '7531256005',
      '7531256004',
    );
    checksum(
      'Roemenië — CNP (mod-11)',
      isValidRoCnp,
      '1800510123458',
      '1800510123457',
    );
    checksum(
      'Zweden — personnummer (Luhn)',
      isValidSePersonnummer,
      '811218-9876',
      '811218-9875',
    );
    checksum(
      'Finland — henkilötunnus (mod-31)',
      isValidFiHetu,
      '131052-308T',
      '131052-308U',
    );
    checksum(
      'Estland/Litouwen — persoonscode (mod-11)',
      isValidBalticPersonalCode,
      '37205030203',
      '37205030204',
    );
    checksum(
      'VK — NHS-nummer (mod-11)',
      isValidUkNhs,
      '943 476 7016',
      '943 476 7015',
    );
    checksum(
      'IJsland — kennitala (mod-11)',
      isValidIsKennitala,
      '2902007170',
      '2902007180',
    );
  });

  group('IJsland — de kennitala buiten de checksum om', () {
    test('accepteert beide schrijfwijzen', () {
      expect(isValidIsKennitala('120788-3539'), isTrue);
      expect(isValidIsKennitala('1207883539'), isTrue);
    });

    test('wijst een bedrijfskennitala af', () {
      // Rechtspersonen krijgen 40 opgeteld bij de dag. `4105903010` haalt de
      // mod-11 wél, en zonder de dagcontrole zou elke IJslandse leverancier op
      // een factuurslide als persoonsgegeven binnenkomen.
      expect(_haaltDeIsMod11('4105903010'), isTrue);
      expect(isValidIsKennitala('4105903010'), isFalse);
    });

    test('wijst een onmogelijk eeuwcijfer af', () {
      // Alleen `9` (1900-1999) en `0` (vanaf 2000) worden uitgegeven.
      expect(isValidIsKennitala('2902007175'), isFalse);
    });

    test('wijst een onmogelijke maand af', () {
      // Haalt de mod-11 gewoon — maand 13 bestaat alleen niet.
      expect(_haaltDeIsMod11('0113882059'), isTrue);
      expect(isValidIsKennitala('0113882059'), isFalse);
    });

    test('wijst een onmogelijke dag af', () {
      expect(_haaltDeIsMod11('3207882189'), isTrue);
      expect(isValidIsKennitala('3207882189'), isFalse);
    });
  });

  group('Duitsland: de cijferherhalingsregel doet echt werk', () {
    test('wijst een nummer af waarin geen enkel cijfer herhaalt', () {
      // Een Steuer-ID heeft in de eerste tien cijfers precies één cijfer dat
      // twee of drie keer voorkomt. Zonder die regel zou de checksum alléén een
      // flinke hap vals-positieven doorlaten.
      expect(isValidDeSteuerId('12345678903'), isFalse);
    });

    test('wijst een nummer af dat met een nul begint', () {
      expect(isValidDeSteuerId('01234567890'), isFalse);
    });
  });

  group('de ingebouwde geboortedatum doet het echte filterwerk', () {
    test('Bulgaars EGN wijst een onmogelijke maand af', () {
      // 4294198070 is een 32-bits ARGB-kleurwaarde die de mod-11 gewoon haalt.
      // Hij stond in een JSON-voorbeeld in onze eigen documentatie en liet de
      // scanner afgaan. Mod-11 over tien cijfers laat ~1 op de 10 willekeurige
      // reeksen door — dezelfde val als de 11-proef. De datumcontrole vangt het:
      // maand 94 bestaat niet.
      expect(isValidBgEgn('4294198070'), isFalse);
    });

    test('Pools PESEL wijst een onmogelijke dag af', () {
      expect(isValidPlPesel('44059901359'), isFalse);
    });

    test('Roemeens CNP wijst een onmogelijke maand af', () {
      expect(isValidRoCnp('1809910123458'), isFalse);
    });
  });

  group('VK — NINO heeft géén checksum, dus een strak formaat', () {
    test('accepteert een geldig formaat', () {
      expect(isValidUkNino('AB123456C'), isTrue);
      expect(isValidUkNino('AB 12 34 56 A'), isTrue);
    });

    test('wijst de uitgesloten prefixen af', () {
      // BG, GB, NK, KN, TN, NT en ZZ worden nooit uitgegeven.
      for (final prefix in ['BG', 'GB', 'NK', 'KN', 'TN', 'NT', 'ZZ']) {
        expect(isValidUkNino('${prefix}123456A'), isFalse, reason: prefix);
      }
    });

    test('wijst de verboden letters af', () {
      expect(isValidUkNino('DA123456A'), isFalse);
      expect(isValidUkNino('AO123456A'), isFalse);
    });

    test('wijst een verkeerd achtervoegsel af', () {
      expect(isValidUkNino('AB123456E'), isFalse);
    });
  });
}
