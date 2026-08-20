import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/utils/color_contrast.dart';

/// Regressie: de thema-contrastreeks somde alleen kleuren op die op een *dia*
/// voorkomen. De twee kleurparen die alléén op het documentvlak bestaan — de
/// kopkleur van een document en de kop-/voetband om het blad — stonden er niet
/// in. Daardoor kon een stijlprofiel een kop of een band onleesbaar zetten
/// zonder dat de kwaliteitspoort of de stijlinstelling iets zei, terwijl elke
/// dia-kleur wél gecontroleerd werd.
void main() {
  const analyzer = SlideQualityAnalyzer();

  // Eén dia, want de deckbrede thema-toets draait ongeacht wat erop staat.
  const slides = [Slide(id: '_probe', type: SlideType.bullets, title: 'x')];

  List<SlideQualityIssue> analyse(ThemeProfile theme) => analyzer
      .analyzeSlides(slides: slides, theme: theme, font: theme.fontFamily)
      .issues;

  List<SlideQualityIssue> withLabel(
    List<SlideQualityIssue> issues,
    String label,
  ) => issues
      .where(
        (i) =>
            i.kind == SlideQualityIssueKind.themeContrast &&
            i.args['label'] == label,
      )
      .toList();

  // Grijstinten op wit, gekozen op weerszijden van de WCAG-grens voor grote
  // tekst (3.0) en die voor gewone tekst (4.5). Zo is per toets aantoonbaar wélk
  // paar de bindende beperking is, in plaats van bijvangst van een profiel dat
  // toch al zou waarschuwen.
  const paper = '#FFFFFF';
  const belowLarge = '#999999'; // 2,85:1 — zakt door beide drempels.
  const betweenThresholds = '#8C8C8C'; // 3,36:1 — grote tekst mag, gewone niet.

  test('de opzet klopt: de gekozen grijstinten liggen om de drempels heen', () {
    expect(hexContrastRatio(belowLarge, paper)!, lessThan(kWcagAaLargeText));
    expect(
      hexContrastRatio(betweenThresholds, paper)!,
      greaterThan(kWcagAaLargeText),
    );
    expect(
      hexContrastRatio(betweenThresholds, paper)!,
      lessThan(kWcagAaNormalText),
    );
  });

  group('de kopkleur van een document', () {
    test('een te bleke kopkleur op het papier waarschuwt', () {
      final issues = withLabel(
        analyse(
          const ThemeProfile().copyWith(documentHeadingColor: belowLarge),
        ),
        'Thema documentkop',
      );

      expect(issues, hasLength(1));
      expect(issues.single.field, 'documentHeadingColor');
      expect(issues.single.slideIndex, kDeckWideSlideIndex);
      expect(issues.single.args['ratio'], '2.8');
      expect(issues.single.severity, MarkdownValidationSeverity.warning);
    });

    test('een kop haalt de drempel voor grote tekst', () {
      // Een documentkop rendert op displayformaat (een h1 op 27 beeldpunten),
      // dus geldt de WCAG-grens voor grote tekst. Dezelfde kleur die de band
      // hieronder wél afkeurt, mag hier blijven staan.
      final issues = withLabel(
        analyse(
          const ThemeProfile().copyWith(
            documentHeadingColor: betweenThresholds,
          ),
        ),
        'Thema documentkop',
      );

      expect(issues, isEmpty);
    });
  });

  group('de kop- en voetband van een document', () {
    test('te weinig contrast in de band waarschuwt', () {
      final issues = withLabel(
        analyse(
          const ThemeProfile().copyWith(
            documentBandTextColor: betweenThresholds,
          ),
        ),
        'Thema documentband',
      );

      expect(issues, hasLength(1));
      expect(issues.single.field, 'documentBandTextColor');
      expect(issues.single.args['ratio'], '3.4');
      // Bandtekst staat op 12 beeldpunten: gewone tekst, en boven de harde
      // ondergrens (3.0) blijft het een waarschuwing.
      expect(issues.single.severity, MarkdownValidationSeverity.warning);
    });

    test('onder de harde ondergrens is de band een fout', () {
      final issues = withLabel(
        analyse(
          const ThemeProfile().copyWith(documentBandTextColor: belowLarge),
        ),
        'Thema documentband',
      );

      expect(issues.single.severity, MarkdownValidationSeverity.error);
    });

    test('een donkere bandachtergrond onder de geërfde tekstkleur telt ook', () {
      // Alleen de achtergrond gezet: de bandtekst erft `textColor` (#222222) en
      // valt daarmee weg op een bijna even donkere band. Het paar bestaat pas
      // door die achtergrondkeuze, dus zonder deze tak blijft het ongemeten.
      final issues = withLabel(
        analyse(
          const ThemeProfile().copyWith(documentBandBackgroundColor: '#333333'),
        ),
        'Thema documentband',
      );

      expect(issues, hasLength(1));
      // De melding landt op de tekstkleur — hetzelfde anker dat 'Thema
      // bodytekst' kiest, en het veld waar de auteur het herstelt.
      expect(issues.single.field, 'documentBandTextColor');
    });
  });

  group('geërfde documentkleuren melden niets dubbel', () {
    test('een leesbaar standaardprofiel meldt geen documentprobleem', () {
      final issues = analyse(const ThemeProfile());

      expect(withLabel(issues, 'Thema documentkop'), isEmpty);
      expect(withLabel(issues, 'Thema documentband'), isEmpty);
    });

    test('een onleesbare tekstkleur meldt één keer, niet drie keer', () {
      // Zet de auteur de documentkleuren niet, dan valt het documentvlak terug
      // op `textColor` en `slideBackgroundColor` — precies het paar dat 'Thema
      // bodytekst' al meet, en op een stríktere drempel. Een tweede en derde
      // melding over datzelfde paar zou alleen ruis zijn in het paneel.
      final issues = analyse(
        const ThemeProfile().copyWith(textColor: belowLarge),
      );

      expect(withLabel(issues, 'Thema bodytekst'), hasLength(1));
      expect(withLabel(issues, 'Thema documentkop'), isEmpty);
      expect(withLabel(issues, 'Thema documentband'), isEmpty);
    });
  });
}
