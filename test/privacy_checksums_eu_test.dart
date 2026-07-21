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

/// De kale mod-11 van de personas kods, zónder de datum- en eeuwcontrole.
///
/// Zelfde reden als [_haaltDeIsMod11]: een test die alleen "valt af" bewijst
/// niet wélke eis hem tegenhield.
bool _haaltDeLvMod11(String d) {
  const w = [1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += (d.codeUnitAt(i) - 0x30) * w[i];
  }
  return (1101 - sum) % 11 % 10 == d.codeUnitAt(10) - 0x30;
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
    checksum(
      'Letland — personas kods, oud formaat (mod-11)',
      isValidLvPersonasKods,
      '11048112348',
      '11048112347',
    );
    checksum(
      'Letland — personas kods, nieuw formaat (mod-11)',
      isValidLvPersonasKods,
      '32182736453',
      '32182736452',
    );
    checksum(
      'Luxemburg — matricule (Luhn + Verhoeff)',
      isValidLuMatricule,
      '1977063000135',
      '1977063000136',
    );
  });

  group('Cyprus — de TIC en de mod-26-controleletter', () {
    test('de referentiewaarde uit python-stdnum klopt', () {
      // `10259033P` is de doctest-waarde van `stdnum/cy/vat.py`. Hij staat hier
      // als bewijs dat onze omzettabel dezelfde is als die van de
      // referentie-implementatie — een eigen uitgerekende waarde bewijst alleen
      // dat de code met zichzelf overweg kan.
      expect(isValidCyTic('10259033P'), isTrue);
      expect(isValidCyTic('10259033Z'), isFalse);
    });

    test('accepteert de vorm met landcode-scheiding', () {
      expect(isValidCyTic('00123456H'), isTrue);
      expect(isValidCyTic('0012 3456 H'), isTrue);
    });

    test('accepteert ook het TFA-bereik vanaf 60000000', () {
      // Sinds 27 maart 2023 worden codes vanaf 60000000 uitgegeven. Of de
      // controleletter daar met hetzelfde schema wordt berekend zegt geen
      // publieke bron; deze test legt vast wat we aannemen, niet wat we weten.
      expect(isValidCyTic('60001234D'), isTrue);
    });

    test('wijst het niet-uitgegeven 12-bereik af', () {
      // `12345678F` haalt de mod-26 gewoon; het bereik wordt alleen niet
      // uitgegeven. Zonder deze eis zou de meest voor de hand liggende
      // verzonnen cijferreeks van allemaal een treffer zijn.
      expect(isValidCyTic('12345678F'), isFalse);
      expect(isValidCyTic('02345678G'), isTrue);
    });

    test('wijst een reeks zonder letter af', () {
      expect(isValidCyTic('102590331'), isFalse);
    });
  });

  group('Luxemburg — twee controlecijfers, en allebei nodig', () {
    // De valkuil: `C2` is een Verhoeff over de eerste ELF cijfers, niet over de
    // twaalf inclusief `C1`. Wie ze stapelt — wat elke andere
    // twee-controlecijferregeling doet — krijgt een validator die geen enkel
    // echt matricule accepteert.
    test('een verminkt Luhn-cijfer valt af', () {
      expect(isValidLuMatricule('1977063000135'), isTrue);
      expect(isValidLuMatricule('1977063000145'), isFalse);
    });

    test('een verminkt Verhoeff-cijfer valt af', () {
      expect(isValidLuMatricule('1977063000136'), isFalse);
    });

    test('wijst een onmogelijk geboortejaar af', () {
      // Een bedrijfsmatricule begint met het oprichtingsjaar of met vier
      // nullen, en heeft daarna een heel andere opbouw.
      expect(isValidLuMatricule('0000205000135'), isFalse);
    });
  });

  group('Letland — het is niet het Estse schema', () {
    test('de Estse validator keurt een Letse kods af', () {
      // De catalogus verleidt tot hergebruik: elf cijfers, mod-11, buurland.
      // Dat is precies de fout die echte nummers zou afwijzen.
      expect(isValidLvPersonasKods('11048112348'), isTrue);
      expect(isValidBalticPersonalCode('11048112348'), isFalse);
    });

    test('en de Letse validator keurt een Estse code af', () {
      expect(isValidBalticPersonalCode('37205030203'), isTrue);
      expect(isValidLvPersonasKods('37205030203'), isFalse);
    });
  });

  group('Letland — wat er buiten de checksum om afvalt', () {
    test('accepteert beide schrijfwijzen', () {
      expect(isValidLvPersonasKods('280760-13575'), isTrue);
      expect(isValidLvPersonasKods('28076013575'), isTrue);
    });

    test('wijst een rechtspersoon af', () {
      // Eerste cijfer boven de 3; die nummers rekenen met een ander schema en
      // horen sowieso bij een bedrijf en niet bij een mens.
      expect(isValidLvPersonasKods('41048112345'), isFalse);
    });

    test('wijst een onmogelijk eeuwcijfer af', () {
      // Positie 7 kent maar drie waarden: 0, 1 en 2.
      expect(_haaltDeLvMod11('11048192341'), isTrue);
      expect(isValidLvPersonasKods('11048192341'), isFalse);
    });

    test('het nieuwe formaat draagt geen datum en hoeft er dus geen', () {
      // `321827…` zou als dag 32 afvallen; het `32`-prefix is juist het teken
      // dat er geen geboortedatum in zit.
      expect(isValidLvPersonasKods('32182736453'), isTrue);
    });
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
