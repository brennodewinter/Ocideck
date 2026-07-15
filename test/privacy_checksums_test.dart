import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/privacy/privacy_checksums.dart';

void main() {
  group('11-proef (BSN)', () {
    test('accepteert geldige nummers', () {
      // Officiële testnummers van de Rijksoverheid; ze doorstaan de proef.
      for (final bsn in ['999999990', '999999011', '123456782']) {
        expect(passesElevenProof(bsn), isTrue, reason: bsn);
      }
    });

    test('wijst nummers af die de proef niet halen', () {
      for (final niet in ['123456789', '999999991', '111111111']) {
        expect(passesElevenProof(niet), isFalse, reason: niet);
      }
    });

    test('wijst een verkeerde lengte af', () {
      expect(passesElevenProof('12345678'), isFalse);
      expect(passesElevenProof('1234567890'), isFalse);
      expect(passesElevenProof(''), isFalse);
    });

    test('wijst niet-cijfers af', () {
      expect(passesElevenProof('12345678X'), isFalse);
      expect(passesElevenProof('1234 5678'), isFalse);
    });

    test('het laatste cijfer telt negatief mee', () {
      // Zou het laatste cijfer positief meetellen, dan zou dit slagen. Dit is
      // precies het detail dat de 11-proef van een gewone gewogen modulo
      // onderscheidt, en dus het waard om vast te leggen.
      expect(passesElevenProof('123456788'), isFalse);
    });

    test('ongeveer één op de elf willekeurige getallen slaagt', () {
      // Dit is GEEN eigenschap die we willen, maar een die we moeten kennen: ze
      // is de hele reden dat een BSN-treffer zonder contextwoord niet meer dan
      // informatief mag zijn. Zie OCIWACHT §5.2. Zakt dit getal ooit
      // drastisch, dan is de proef stuk; stijgt het, dan is de aanname in de
      // scanner niet meer waar.
      var geslaagd = 0;
      const totaal = 100000;
      // Deterministische pseudo-reeks: geen Random(), zodat de test niet flakey
      // wordt en het cijfer reproduceerbaar blijft.
      var x = 1;
      for (var i = 0; i < totaal; i++) {
        x = (x * 1103515245 + 12345) & 0x7fffffff;
        final digits = (x % 900000000 + 100000000).toString();
        if (passesElevenProof(digits)) geslaagd++;
      }
      final ratio = geslaagd / totaal;
      expect(ratio, greaterThan(0.07));
      expect(ratio, lessThan(0.11));
    });
  });

  group('Luhn', () {
    test('accepteert bekende geldige nummers', () {
      for (final pan in [
        '4111111111111111', // Visa-testkaart
        '5555555555554444', // Mastercard-testkaart
        '378282246310005', // Amex-testkaart
        '490154203237518', // IMEI
      ]) {
        expect(passesLuhn(pan), isTrue, reason: pan);
      }
    });

    test('wijst een verminkt nummer af', () {
      expect(passesLuhn('4111111111111112'), isFalse);
      expect(passesLuhn('1234567890123456'), isFalse);
    });

    test('wijst niet-cijfers en te korte invoer af', () {
      expect(passesLuhn('4111-1111'), isFalse);
      expect(passesLuhn('4'), isFalse);
      expect(passesLuhn(''), isFalse);
    });
  });

  group('IBAN', () {
    test('accepteert geldige IBANs uit meerdere landen', () {
      for (final iban in [
        'NL91ABNA0417164300',
        'DE89370400440532013000',
        'GB82WEST12345698765432',
        'FR1420041010050500013M02606',
        'BE68539007547034',
        'CH9300762011623852957',
      ]) {
        expect(isValidIban(iban), isTrue, reason: iban);
      }
    });

    test('accepteert spaties en streepjes', () {
      expect(isValidIban('NL91 ABNA 0417 1643 00'), isTrue);
      expect(isValidIban('nl91-abna-0417-1643-00'), isTrue);
    });

    test('wijst een verminkt controlegetal af', () {
      expect(isValidIban('NL92ABNA0417164300'), isFalse);
      expect(isValidIban('DE89370400440532013001'), isFalse);
    });

    test('wijst de verkeerde lengte voor het land af', () {
      // Mod-97 alleen is niet genoeg: de lengtetabel is een even sterke filter.
      expect(isValidIban('NL91ABNA04171643000'), isFalse);
      expect(isValidIban('NL91ABNA041716430'), isFalse);
    });

    test('wijst een onbekende landcode af', () {
      expect(isValidIban('ZZ91ABNA0417164300'), isFalse);
    });

    test('wijst rommel af zonder te crashen', () {
      expect(isValidIban(''), isFalse);
      expect(isValidIban('NL91ABNA04171643@@'), isFalse);
      expect(isValidIban('een gewone zin zonder iban'), isFalse);
    });
  });
}
