import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Property-style guard against the *class* of silent round-trip data-loss bugs
/// (C1–C4): any author text in a field whose serialisation is a lossless
/// contract must survive serialize→parse unchanged, however nasty the
/// characters. Each adversarial string mixes the delimiters and markup that
/// each encoder has to escape: the split-image caption separator (" | "), the
/// HTML-comment close ("-->"), the table newline encoding ("<br>"), the escape
/// char ("\\"), and HTML metacharacters.
///
/// This would have caught C1–C4; add a new string here the moment a new
/// escaping bug is found, not a one-off test.
Slide _roundTrip(Slide slide) {
  final service = MarkdownService();
  final markdown = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
  final deck = service.parseDeck(markdown);
  expect(deck, isNotNull, reason: 'parseDeck returned null for:\n$markdown');
  expect(deck!.slides, hasLength(1), reason: 'one slide expected:\n$markdown');
  return deck.slides.single;
}

/// Nasty single-line payloads — safe for any inline field (no bare newline and
/// no slide separator that the format legitimately splits on).
const _inlineNasty = <String>[
  'pipe | midden',
  'twee | pipes | hier',
  'comment --> sluit vroeg',
  'meerdere --> en --> tokens',
  'literal <br> tag',
  r'backslash \ en \| en \<br> door elkaar',
  'quotes " en \' en & en < en >',
  'unicode café 🐾 ☃ en emoji',
  'alles | --> <br> \\ " < > & tegelijk',
];

/// Multi-line payloads — only for fields that legitimately carry newlines
/// (table cells, speaker notes).
const _multilineNasty = <String>[
  'regel1\nregel2',
  'a --> b\nc --> d',
  'cel met <br> tekst\nen een echte regel',
  'pipe | en\nnieuwe | regel',
];

void main() {
  group('round-trip fuzz: lossless fields survive adversarial text', () {
    for (final nasty in _inlineNasty) {
      test('split-image captions keep "$nasty"', () {
        final out = _roundTrip(
          Slide.create(SlideType.twoImages).copyWith(
            imagePath: 'images/a.png',
            imagePath2: 'images/b.png',
            imageCaption: nasty,
            imageCaption2: 'tweede $nasty',
          ),
        );
        expect(out.imageCaption, nasty);
        expect(out.imageCaption2, 'tweede $nasty');
      });

      test('single image caption keeps "$nasty"', () {
        final out = _roundTrip(
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: 'images/a.png', imageCaption: nasty),
        );
        expect(out.imageCaption, nasty);
      });

      test('bullets keep "$nasty"', () {
        final out = _roundTrip(
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Kop', bullets: [nasty, 'tweede $nasty']),
        );
        expect(out.bullets, [nasty, 'tweede $nasty']);
      });
    }

    for (final nasty in [..._inlineNasty, ..._multilineNasty]) {
      test('speaker notes keep "${nasty.replaceAll('\n', r'\n')}"', () {
        final out = _roundTrip(
          Slide.create(SlideType.section).copyWith(title: 'Deel', notes: nasty),
        );
        expect(out.notes, nasty);
      });

      test('table cells keep "${nasty.replaceAll('\n', r'\n')}"', () {
        final out = _roundTrip(
          Slide.create(SlideType.table).copyWith(
            tableRows: [
              ['Kop A', 'Kop B'],
              [nasty, 'cel $nasty'],
            ],
          ),
        );
        expect(out.tableRows[1][0], nasty);
        expect(out.tableRows[1][1], 'cel $nasty');
      });
    }
  });
}
