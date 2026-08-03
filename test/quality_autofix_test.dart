import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/quality_autofix.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';

// De fix-alles-motor (#915): werkt structurele, veilige kwaliteitsproblemen weg
// zonder ooit inhoud van een dia te halen. De tests bewaken de belofte —
// splitsen bij te vol, zinnen opknippen, meegesleepte pagina's losmaken — én de
// grens: wat menselijk oordeel vraagt blijft staan, en de motor eindigt altijd.
void main() {
  const analyzer = SlideQualityAnalyzer();

  Deck deckOf(List<Slide> slides) => Deck(title: 'T', slides: slides);

  bool hasFixableIssue(Deck deck) => analyzer
      .analyze(deck)
      .issues
      .any((i) => isStructurallyAutofixable(i.kind));

  group('fixAllStructuralQualityIssues', () {
    test('splitst een dia met veel te veel bullets tot alles past', () {
      final deck = deckOf([
        Slide.create(
          SlideType.bullets,
        ).copyWith(bullets: [for (var i = 0; i < 20; i++) 'Punt ${i + 1}']),
      ]);
      expect(hasFixableIssue(deck), isTrue);

      final result = fixAllStructuralQualityIssues(deck);

      expect(result.applied, greaterThan(0));
      expect(result.deck.slides.length, greaterThan(1));
      // Geen enkele bullet is verdwenen: de som over de pagina's is nog twintig.
      final total = result.deck.slides.fold<int>(
        0,
        (sum, s) => sum + s.bullets.length,
      );
      expect(total, 20);
      // En er is geen automatisch op te lossen probleem meer over.
      expect(hasFixableIssue(result.deck), isFalse);
    });

    test('knipt meerzins-bullets op zonder de dia te splitsen', () {
      final deck = deckOf([
        Slide.create(SlideType.bullets).copyWith(
          bullets: [
            'Eerste zin. Tweede zin.',
            'Derde zin. Vierde zin.',
            'Los een.',
            'Los twee.',
          ],
        ),
      ]);
      expect(hasFixableIssue(deck), isTrue);

      final result = fixAllStructuralQualityIssues(deck);

      expect(result.applied, greaterThan(0));
      // In plaats van splitsen blijven de zinnen als losse bullets op één dia.
      expect(result.deck.slides.length, 1);
      expect(result.deck.slides.first.bullets, [
        'Eerste zin.',
        'Tweede zin.',
        'Derde zin.',
        'Vierde zin.',
        'Los een.',
        'Los twee.',
      ]);
      // De hele oorspronkelijke regel staat mét streepje in de notities (#913).
      expect(
        result.deck.slides.first.notes.contains('- Eerste zin. Tweede zin.'),
        isTrue,
      );
      expect(hasFixableIssue(result.deck), isFalse);
    });

    test('laat een probleem dat een keuze vraagt staan (applied 0)', () {
      // Een lege dia is een inhoudsmelding, geen structureel op te lossen
      // probleem: de motor raakt het deck niet aan.
      final deck = deckOf([Slide.create(SlideType.bullets)]);
      expect(hasFixableIssue(deck), isFalse);

      final result = fixAllStructuralQualityIssues(deck);

      expect(result.applied, 0);
      expect(identical(result.deck, deck), isTrue);
    });

    test('is idempotent: een tweede keer draaien doet niets meer', () {
      final deck = deckOf([
        Slide.create(
          SlideType.bullets,
        ).copyWith(bullets: [for (var i = 0; i < 20; i++) 'Punt ${i + 1}']),
      ]);
      final once = fixAllStructuralQualityIssues(deck);
      final twice = fixAllStructuralQualityIssues(once.deck);
      expect(twice.applied, 0);
      expect(twice.deck.slides.length, once.deck.slides.length);
    });

    test('safeFixForSlide splitst een te volle losse dia', () {
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: [for (var i = 0; i < 20; i++) 'Punt ${i + 1}']);
      final pages = safeFixForSlide(slide, const ThemeProfile());
      expect(pages, isNotNull);
      expect(pages!.length, greaterThan(1));
      final total = pages.fold<int>(0, (sum, s) => sum + s.bullets.length);
      expect(total, 20);
    });

    test('safeFixForSlide knipt zinnen op één dia zonder te splitsen', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        bullets: [
          'Eerste zin. Tweede zin.',
          'Derde zin. Vierde zin.',
          'Los een.',
          'Los twee.',
        ],
      );
      final pages = safeFixForSlide(slide, const ThemeProfile());
      expect(pages, isNotNull);
      expect(pages!.length, 1);
      expect(pages.first.bullets.length, 6);
    });

    test('safeFixForSlide geeft null als er niets te doen is', () {
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: ['Eén korte bullet', 'Nog een korte']);
      expect(safeFixForSlide(slide, const ThemeProfile()), isNull);
    });

    test('splitst niet bij ≤ 8 bullets ondanks te veel woorden', () {
      // Vijf bullets met veel woorden: de woordtelling geeft een melding, maar
      // splitsen lost niets op — er zijn ≤ 8 bullets, dus de motor laat de
      // melding staan zodat de gebruiker "Uitleg naar notities" kan kiezen.
      final deck = deckOf([
        Slide.create(SlideType.bullets).copyWith(
          bullets: [
            'Een tamelijk lange bullet met flink wat woorden erin nummer een',
            'Een tamelijk lange bullet met flink wat woorden erin nummer twee',
            'Een tamelijk lange bullet met flink wat woorden erin nummer drie',
            'Een tamelijk lange bullet met flink wat woorden erin nummer vier',
            'Een tamelijk lange bullet met flink wat woorden erin nummer vijf',
          ],
        ),
      ]);

      final result = fixAllStructuralQualityIssues(deck);

      // De motor past geen splitsing toe: één dia blijft één dia.
      expect(result.deck.slides.length, 1);
      expect(result.applied, 0);
    });

    test('safeFixForSlide geeft null bij ≤ 8 bullets met te veel woorden', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        bullets: [
          'Een tamelijk lange bullet met flink wat woorden erin nummer een',
          'Een tamelijk lange bullet met flink wat woorden erin nummer twee',
          'Een tamelijk lange bullet met flink wat woorden erin nummer drie',
          'Een tamelijk lange bullet met flink wat woorden erin nummer vier',
          'Een tamelijk lange bullet met flink wat woorden erin nummer vijf',
        ],
      );
      expect(safeFixForSlide(slide, const ThemeProfile()), isNull);
    });

    // #1159 — dichtheids-overloop door lánge bullets (aantal ≤ drempel). De
    // dia rendert te klein maar heeft te weinig bullets voor de aantal-gate;
    // toch vergroot splitsen de font, dus de motor moet hem splitsen.
    List<String> longBullets(int n) => [
      for (var i = 0; i < n; i++)
        'Wij hebben in het afgelopen kwartaal besloten om de gehele '
            'onderliggende infrastructuur te migreren naar een nieuwe omgeving '
            'omdat dat op termijn goedkoper en beter onderhoudbaar is, punt '
            '${i + 1}',
    ];

    test('splitst een te-klein-renderende dia met weinig lange bullets', () {
      // Zes lange bullets: onder de aantal-drempel (8), maar de dia rendert te
      // klein. Vroeger deed de motor niets; nu splitst hij zodat de font groeit.
      final deck = deckOf([
        Slide.create(SlideType.bullets).copyWith(bullets: longBullets(6)),
      ]);
      // De melding is een dichtheidsmelding (te klein), niet enkel woordtelling.
      expect(
        analyzer
            .analyze(deck)
            .issues
            .any(
              (i) =>
                  i.kind == SlideQualityIssueKind.textDensityWarning ||
                  i.kind == SlideQualityIssueKind.textDensityCritical,
            ),
        isTrue,
        reason: 'de dia hoort te klein te renderen',
      );

      final result = fixAllStructuralQualityIssues(deck);

      expect(result.applied, greaterThan(0));
      expect(result.deck.slides.length, greaterThan(1));
      // Geen bullet verdwenen: de som over de pagina's is nog zes.
      final total = result.deck.slides.fold<int>(
        0,
        (sum, s) => sum + s.bullets.length,
      );
      expect(total, 6);
    });

    test(
      'safeFixForSlide splitst een te-klein-renderende lange-bullet-dia',
      () {
        final slide = Slide.create(
          SlideType.bullets,
        ).copyWith(bullets: longBullets(6));
        final pages = safeFixForSlide(slide, const ThemeProfile());
        expect(pages, isNotNull);
        expect(pages!.length, greaterThan(1));
        final total = pages.fold<int>(0, (sum, s) => sum + s.bullets.length);
        expect(total, 6);
      },
    );

    test('splitst geen dia met te weinig bullets voor twee pagina\'s', () {
      // Vier lange bullets rendert misschien krap, maar splitsen zou pagina's
      // van twee bullets opleveren — geen volwaardige pagina's. De motor laat
      // de melding staan (dan kan de gebruiker "Uitleg naar notities" kiezen).
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: longBullets(4));
      expect(safeFixForSlide(slide, const ThemeProfile()), isNull);
    });

    test('maakt een meegesleepte pagina uit zijn reeks los', () {
      // Twee pagina's in één gesplitste reeks: een korte en een propvolle. De
      // gedeelde tekstgrootte sleept de korte mee omlaag (splitRunDragged); de
      // veilige fix is de volle pagina losmaken.
      final deck = deckOf([
        Slide.create(SlideType.bullets).copyWith(bullets: ['Kort punt']),
        Slide.create(SlideType.bullets).copyWith(
          continuesSplit: true,
          bullets: [
            for (var i = 0; i < 16; i++)
              'Een tamelijk lange bullet met flink wat woorden erin nummer '
                  '${i + 1}',
          ],
        ),
      ]);

      final result = fixAllStructuralQualityIssues(deck);

      expect(result.applied, greaterThan(0));
      expect(hasFixableIssue(result.deck), isFalse);
    });
  });
}
