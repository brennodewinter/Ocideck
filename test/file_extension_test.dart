import 'package:ocideck/utils/file_extension.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('withExtension', () {
    test('voegt extensie toe wanneer die ontbreekt', () {
      expect(withExtension('deck', '.md'), 'deck.md');
    });

    test('voegt niets toe wanneer extensie al staat (kleine letters)', () {
      expect(withExtension('deck.md', '.md'), 'deck.md');
    });

    test('hoofdletterongevoelig: .MD wordt herkend', () {
      expect(withExtension('Deck.MD', '.md'), 'Deck.MD');
      expect(withExtension('Presentatie.MD', '.md'), 'Presentatie.MD');
    });

    test('extensie zonder leidende punt werkt ook', () {
      expect(withExtension('verzoek', 'tsq'), 'verzoek.tsq');
      expect(withExtension('verzoek.tsq', 'tsq'), 'verzoek.tsq');
      expect(withExtension('verzoek.TSQ', 'tsq'), 'verzoek.TSQ');
    });

    test('punt in mapnaam maar niet in bestandsnaam', () {
      expect(withExtension('my.folder/deck', '.md'), 'my.folder/deck.md');
    });

    test('andere extensie wordt niet als match gezien', () {
      expect(withExtension('deck.txt', '.md'), 'deck.txt.md');
    });

    test('stijlprofiel-extensie met variabele hoofdletters', () {
      expect(
        withExtension('profiel.OCIDECKSTYLE', '.ocideckstyle'),
        'profiel.OCIDECKSTYLE',
      );
    });
  });
}
