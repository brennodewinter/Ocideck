// De maattokens `w:`/`h:` in de haakjes van een documentafbeelding: splitsen
// uit de alt, en terugschrijven in bestaande markdown zonder de rest aan te
// raken (FILE_FORMAT §afbeeldingen).

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_size_tokens.dart';

void main() {
  group('splitImageSizeTokens', () {
    test('geen tokens: alles is alt', () {
      final r = splitImageSizeTokens('Een kat op een dak');
      expect(r.alt, 'Een kat op een dak');
      expect(r.size.width, isNull);
      expect(r.size.widthFraction, isNull);
      expect(r.size.height, isNull);
    });

    test('w:50% is een deel van de breedte, geen px', () {
      final r = splitImageSizeTokens('w:50% Kat');
      expect(r.alt, 'Kat');
      expect(r.size.widthFraction, 0.5);
      expect(r.size.width, isNull);
    });

    test('w:200 en w:200px zijn beide een vaste breedte', () {
      for (final token in ['w:200', 'w:200px', 'width:200']) {
        final r = splitImageSizeTokens('$token Kat');
        expect(r.size.width, 200, reason: token);
        expect(r.alt, 'Kat');
      }
    });

    test('h:120 begrenst de hoogte', () {
      final r = splitImageSizeTokens('h:120 Handtekening');
      expect(r.size.height, 120);
      expect(r.alt, 'Handtekening');
    });

    test('leeg en onbekend blijft ongemoeid', () {
      expect(splitImageSizeTokens('').alt, '');
      final r = splitImageSizeTokens('w:dubieus plaatje');
      expect(r.size.width, isNull);
      expect(r.alt, 'w:dubieus plaatje');
    });
  });

  group('markdownImageWithSize', () {
    test('zet de maat vóór de alt en houdt de bron letterlijk', () {
      expect(
        markdownImageWithSize('![Een grafiek](plaatje.png "titel")', (
          width: null,
          widthFraction: 0.5,
          height: null,
        )),
        '![w:50% Een grafiek](plaatje.png "titel")',
      );
    });

    test('vervangt een bestaande maat, hij stapelt niet op', () {
      expect(
        markdownImageWithSize('![w:25% h:80 Grafiek](p.png)', (
          width: 300,
          widthFraction: null,
          height: null,
        )),
        '![w:300px Grafiek](p.png)',
      );
    });

    test('een lege maat haalt de tokens weg', () {
      expect(
        markdownImageWithSize('![w:50% Grafiek](p.png)', (
          width: null,
          widthFraction: null,
          height: null,
        )),
        '![Grafiek](p.png)',
      );
    });

    test('tekst zonder afbeelding komt ongemoeid terug', () {
      const line = 'geen afbeelding';
      expect(
        markdownImageWithSize(line, (
          width: 100,
          widthFraction: null,
          height: null,
        )),
        line,
      );
    });
  });
}
