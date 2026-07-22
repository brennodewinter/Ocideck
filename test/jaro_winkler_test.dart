import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/jaro_winkler.dart';

/// De maat waarmee een getypt antwoord op een vraagslide met het juiste
/// antwoord vergeleken wordt. De auteur stelt een drempel in en vertrouwt erop
/// dat een tikfout er doorheen komt en een ander woord niet — dus die twee
/// kanten horen vastgelegd, niet alleen de rekenregel.
void main() {
  group('jaro', () {
    test('identieke teksten geven 1 en niets gemeen geeft 0', () {
      expect(jaro('kluis', 'kluis'), 1);
      expect(jaro('abc', 'xyz'), 0);
    });

    test('een lege tekst levert geen overeenkomst op', () {
      expect(jaro('', 'kluis'), 0);
      expect(jaro('kluis', ''), 0);
      expect(jaro('', ''), 1); // twee lege teksten zijn wél gelijk
    });

    test('de bekende waarden uit de literatuur kloppen', () {
      // Winklers eigen voorbeelden; wijkt de implementatie af, dan is het hier
      // te zien in plaats van pas bij een vreemd beoordeeld antwoord.
      expect(jaro('MARTHA', 'MARHTA'), closeTo(0.944, 0.001));
      expect(jaro('DIXON', 'DICKSONX'), closeTo(0.767, 0.001));
      expect(jaroWinkler('MARTHA', 'MARHTA'), closeTo(0.961, 0.001));
      expect(jaroWinkler('DIXON', 'DICKSONX'), closeTo(0.813, 0.001));
    });
  });

  group('jaroWinkler', () {
    test('een gelijk begin telt zwaarder dan een gelijk einde', () {
      // Zelfde aantal afwijkende tekens, maar vooraan versus achteraan.
      final samePrefix = jaroWinkler('wachtwoord', 'wachtwoorx');
      final sameSuffix = jaroWinkler('wachtwoord', 'xachtwoord');
      expect(samePrefix, greaterThan(sameSuffix));
    });

    test('de voorvoegselbonus geldt alleen bij genoeg gelijkenis', () {
      // 'kat' en 'kluisdeur' beginnen gelijk maar lijken verder niet op elkaar:
      // zonder de ondergrens zou dat begin ze alsnog omhoog tillen.
      expect(jaroWinkler('kat', 'kluisdeur'), lessThan(0.7));
    });
  });

  group('normalizeAnswerText', () {
    test('hoofdletters, randspaties en dubbele spaties tellen niet mee', () {
      expect(normalizeAnswerText('  De   Kluis '), 'de kluis');
    });

    test('leestekens blijven staan', () {
      expect(normalizeAnswerText('Kluis!'), 'kluis!');
    });
  });

  group('bestAnswerSimilarity', () {
    test('kiest het best passende van de goed gerekende antwoorden', () {
      final score = bestAnswerSimilarity('kluis', ['bureaulade', 'kluis']);
      expect(score, 1);
    });

    test('een tikfout blijft boven de standaarddrempel', () {
      // 0,85 is de standaard in QuestionSpec; één verwisselde letter hoort daar
      // ruim boven te blijven, anders is de standaard onbruikbaar streng.
      expect(
        bestAnswerSimilarity('wachtwoodr', ['wachtwoord']),
        greaterThan(0.85),
      );
    });

    test('een ander woord blijft eronder', () {
      expect(
        bestAnswerSimilarity('gebruikersnaam', ['wachtwoord']),
        lessThan(0.85),
      );
    });

    test('een leeg antwoord of een lege lijst levert 0', () {
      expect(bestAnswerSimilarity('   ', ['kluis']), 0);
      expect(bestAnswerSimilarity('kluis', const []), 0);
      expect(bestAnswerSimilarity('kluis', ['  ']), 0);
    });
  });
}
