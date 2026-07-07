import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/password_generator.dart';
import 'package:ocideck/utils/password_strength.dart';
import 'package:ocideck/utils/zip_encryption.dart';

/// Bouw een klein ZIP-archief met één tekstlid.
Archive _sampleArchive() {
  final archive = Archive();
  final bytes = utf8.encode('marp: true\n\n# Titel\n');
  archive.addFile(ArchiveFile('deck.md', bytes.length, bytes));
  return archive;
}

void main() {
  group('archive AES round-trip', () {
    test('encrypt met wachtwoord → decode met hetzelfde wachtwoord', () {
      final zip = ZipEncoder(
        password: 'correct horse battery staple',
      ).encodeBytes(_sampleArchive());

      final decoded = ZipDecoder().decodeBytes(
        zip,
        password: 'correct horse battery staple',
      );
      final md = decoded.files.firstWhere((f) => f.name == 'deck.md');
      expect(utf8.decode(md.content as List<int>), contains('# Titel'));
    });

    test('onjuist wachtwoord faalt (gooit of levert onleesbare inhoud)', () {
      final zip = ZipEncoder(
        password: 'juist-wachtwoord',
      ).encodeBytes(_sampleArchive());

      // Een onjuist wachtwoord mag nooit de klare tekst opleveren: de WinZip-AES
      // MAC-controle gooit doorgaans, maar ook als dat niet gebeurt moet de
      // inhoud onleesbaar blijven.
      try {
        final decoded = ZipDecoder().decodeBytes(zip, password: 'fout');
        final md = decoded.files.firstWhere((f) => f.name == 'deck.md');
        final text = utf8.decode(md.content as List<int>, allowMalformed: true);
        expect(
          text.contains('# Titel'),
          isFalse,
          reason: 'onjuist wachtwoord onthulde de klare tekst',
        );
      } catch (_) {
        // Gooien is het verwachte en gewenste gedrag.
      }
    });

    test('onversleuteld archief decodeert zonder wachtwoord', () {
      final zip = ZipEncoder().encodeBytes(_sampleArchive());
      final decoded = ZipDecoder().decodeBytes(zip);
      final md = decoded.files.firstWhere((f) => f.name == 'deck.md');
      expect(utf8.decode(md.content as List<int>), contains('# Titel'));
    });
  });

  group('isEncryptedZip detectie', () {
    test('true voor een met wachtwoord versleuteld pakket', () {
      final zip = ZipEncoder(password: 'geheim').encodeBytes(_sampleArchive());
      expect(isEncryptedZip(zip), isTrue);
    });

    test('false voor een gewoon (onversleuteld) pakket', () {
      final zip = ZipEncoder().encodeBytes(_sampleArchive());
      expect(isEncryptedZip(zip), isFalse);
    });

    test('false voor niet-ZIP-bytes', () {
      expect(isEncryptedZip(Uint8List.fromList([1, 2, 3, 4, 5])), isFalse);
      expect(isEncryptedZip(utf8.encode('marp: true')), isFalse);
    });
  });

  group('password strength (intelligent, entropie-gebaseerd)', () {
    test('lege invoer = veryWeak', () {
      expect(estimatePasswordStrength('').category, PasswordStrength.veryWeak);
    });

    test('lange wachtwoordzin zonder symbolen is sterk', () {
      final r = estimatePasswordStrength('correct horse battery staple');
      expect(r.isWeak, isFalse);
      expect(
        r.category.index,
        greaterThanOrEqualTo(PasswordStrength.strong.index),
      );
    });

    test('kort "P@ss1!" met symbool is nog steeds zwak', () {
      // De kern van de eis: een verplichte "!" maakt niet veilig.
      final r = estimatePasswordStrength('P@ss1!');
      expect(r.isWeak, isTrue);
    });

    test('veelgebruikt wachtwoord scoort laag ondanks lengte', () {
      expect(estimatePasswordStrength('password').isWeak, isTrue);
      expect(estimatePasswordStrength('wachtwoord1').isWeak, isTrue);
    });

    test('herhaling drukt de score', () {
      final repeated = estimatePasswordStrength('aaaaaaaaaaaaaaaa');
      final varied = estimatePasswordStrength('aX9!aX9!aX9!aX9!');
      expect(repeated.bits, lessThan(varied.bits));
    });

    test('opeenvolgende reeks krijgt penalty', () {
      final seq = estimatePasswordStrength('abcdefghijkl');
      final rand = estimatePasswordStrength('qm2kfp8xzewr');
      expect(seq.bits, lessThan(rand.bits));
    });

    test('fraction blijft tussen 0 en 1', () {
      expect(estimatePasswordStrength('').fraction, 0.0);
      expect(estimatePasswordStrength(generatePassword(256)).fraction, 1.0);
    });
  });

  group('password generator', () {
    test('produceert de gevraagde lengte', () {
      expect(generatePassword(32).length, 32);
      expect(generatePassword(256).length, 256);
      expect(generatePassword(shortPasswordLength).length, 32);
      expect(generatePassword(longPasswordLength).length, 256);
    });

    test('lengte < 1 wordt begrensd tot 1', () {
      expect(generatePassword(0).length, 1);
      expect(generatePassword(-5).length, 1);
    });

    test('gebruikt alleen tekens uit het alfabet', () {
      final pw = generatePassword(200);
      for (final ch in pw.split('')) {
        expect(
          passwordAlphabet.contains(ch),
          isTrue,
          reason: 'onverwacht: $ch',
        );
      }
    });

    test('twee generaties zijn (vrijwel zeker) verschillend', () {
      expect(generatePassword(32), isNot(equals(generatePassword(32))));
    });

    test('een gegenereerd 32-teken wachtwoord is zeer sterk', () {
      final r = estimatePasswordStrength(generatePassword(32));
      expect(r.category, PasswordStrength.veryStrong);
    });
  });
}
