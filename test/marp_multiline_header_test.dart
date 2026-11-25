import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/services/split_run.dart';

/// De meerregelige Marp-koptekst (#3165): blokscalaren in de front matter
/// lezen, en een gemeten kopband die overal — preview, paginering, run-schaal
/// en kwaliteitscontrole — dezelfde ruimte boven de inhoud vrijhoudt.
void main() {
  final markdown = MarkdownService();

  group('blokscalar in de front matter', () {
    test('`header: |` leest de ingesprongen regels als meerregelige kop', () {
      const source = '''
---
marp: true
header: |
  Eerste regel
  Tweede regel
footer: Deckvoet
---

# Kop
''';
      final deck = markdown.parseDeck(source)!;
      expect(deck.marpStyle.header, 'Eerste regel\nTweede regel');
      // Het blok sluit bij de volgende sleutel op kolom 0.
      expect(deck.marpStyle.footer, 'Deckvoet');
    });

    test('`header: |-` en `header: >` lezen eveneens mee', () {
      const stripped = '''
---
header: |-
  Een
  Twee
---
''';
      const folded = '''
---
header: >
  Eerste regel
  Tweede regel

  Nieuwe alinea
---
''';
      expect(markdown.parseDeck(stripped)!.marpStyle.header, 'Een\nTwee');
      // Gevouwen: doorlopende regels worden een spatie, een lege regel een
      // regeleinde.
      expect(
        markdown.parseDeck(folded)!.marpStyle.header,
        'Eerste regel Tweede regel\nNieuwe alinea',
      );
    });

    test('een ingesprongen "sleutel" in het blok is koptekst, geen veld', () {
      const source = '''
---
header: |
  regel
  theme: donker
---
''';
      final deck = markdown.parseDeck(source)!;
      expect(deck.marpStyle.header, 'regel\ntheme: donker');
      expect(deck.theme, isNot('donker'));
    });

    test('een meerregelige kop overleeft opslaan en herlezen', () {
      const source = '''
---
header: |
  Eerste regel
  Tweede regel
---
''';
      final deck = markdown.parseDeck(source)!;
      final saved = markdown.generateDeck(deck);
      expect(
        RegExp(r'^header:', multiLine: true).allMatches(saved),
        hasLength(1),
      );
      expect(
        markdown.parseDeck(saved)!.marpStyle.header,
        deck.marpStyle.header,
      );
    });
  });

  group('kopband-reserve', () {
    const w = kReferenceSlideWidth;
    const profile = ThemeProfile();
    final slide = Slide.create(SlideType.bullets);

    test('headerSafeInset meet de echte kop: meer regels is meer band', () {
      final one = headerSafeInset(w, 'Regel', profile);
      final three = headerSafeInset(w, 'A\nB\nC', profile);
      expect(one, greaterThan(0));
      expect(three, greaterThan(one));
      // De meetkant boven de vaste offset groeit met het aantal regels.
      expect(three - w * 0.02, closeTo((one - w * 0.02) * 3, 1.0));
      expect(headerSafeInset(w, '', profile), 0);
      expect(headerSafeInset(w, '   ', profile), 0);
    });

    test('richTextBodyAvailH trekt de kopband van het body-budget af', () {
      const header = 'Een\nTwee';
      final without = richTextBodyAvailH(
        w,
        slide,
        profile,
        splitWithImage: false,
      );
      final headed = richTextBodyAvailH(
        w,
        slide,
        profile,
        splitWithImage: false,
        header: header,
      );
      expect(
        without - headed,
        closeTo(headerSafeInset(w, header, profile), 0.001),
      );
    });

    test('splitRunMemberScale krimpt met de kopband mee', () {
      // Een dia die het vlak vult: pas dan maakt de kopband het verschil —
      // bij ruime dia's zit de schaal sowieso aan het plafond.
      final slideWithBullets = slide.copyWith(
        bullets: List.generate(
          14,
          (i) => 'Bullet $i met een redelijk lange regel tekst erachter',
        ),
      );
      final plain = splitRunMemberScale(
        slideWithBullets,
        profile,
        profile.fontFamily,
      );
      final headed = splitRunMemberScale(
        slideWithBullets,
        profile,
        profile.fontFamily,
        deckHeader: 'Een\nTwee',
      );
      expect(headed, lessThan(plain));
      // Een dia mag de deckkop expliciet uitschakelen — dan reserveert hij
      // niets, ook niet wanneer het deck een kop heeft.
      final off = slideWithBullets.copyWith(
        marpStyle: const MarpStyle(header: ''),
      );
      expect(
        splitRunMemberScale(
          off,
          profile,
          profile.fontFamily,
          deckHeader: 'Een\nTwee',
        ),
        plain,
      );
    });
  });

  group('kwaliteitsmelding', () {
    const analyzer = SlideQualityAnalyzer();
    const profile = ThemeProfile();
    final slide = Slide.create(SlideType.bullets);

    bool hasHeaderIssue(Slide s, String deckHeader) => analyzer
        .analyzeSlides(
          slides: [s],
          theme: profile,
          font: profile.fontFamily,
          deckHeader: deckHeader,
        )
        .issues
        .any((i) => i.kind == SlideQualityIssueKind.marpHeaderTooTall);

    test('een kop boven een derde van de diahoogte meldt', () {
      final tall = List.filled(
        14,
        'Een kopregel met flink wat woorden erin',
      ).join('\n');
      expect(hasHeaderIssue(slide, tall), isTrue);
      expect(hasHeaderIssue(slide, 'Korte kop'), isFalse);
      // Ook de dia-eigen kop (`<!-- _header: -->`) meetelt.
      final own = slide.copyWith(marpStyle: MarpStyle(header: tall));
      expect(hasHeaderIssue(own, ''), isTrue);
      // En expliciet uitschakelen zwijgt, hoe hoog de deckkop ook is.
      final off = slide.copyWith(marpStyle: const MarpStyle(header: ''));
      expect(hasHeaderIssue(off, tall), isFalse);
    });
  });
}
