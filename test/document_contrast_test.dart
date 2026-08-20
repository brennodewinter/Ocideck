import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/utils/color_contrast.dart';

/// Regressie: de thema-contrastreeks somde alleen kleuren op die op een *dia*
/// voorkomen. De drie kleurparen die alléén op het documentvlak bestaan — de
/// kopkleur van een document, de tekst van de kop-/voetband om het blad, en het
/// accent zoals het óp die band landt — stonden er niet in. Daardoor kon een
/// stijlprofiel een kop, een band of een link in die band onleesbaar zetten
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

  group('het accent op de bandachtergrond', () {
    // Het echte geval: een donkere huisstijlband met witte tekst erop, en een
    // link in de kop- of voettekst die het accent krijgt. Beide bestaande
    // toetsen zwijgen hier terecht — accent op papier haalt 10,9:1, bandtekst
    // op de band 16,0:1 — dus dit paar is aantoonbaar de enige beperking.
    const houseAccent = '#003399';
    const darkBand = '#14213D';

    ThemeProfile bandTheme({String accent = houseAccent}) =>
        const ThemeProfile().copyWith(
          accentColor: accent,
          documentBandTextColor: '#FFFFFF',
          documentBandBackgroundColor: darkBand,
        );

    test(
      'de opzet klopt: alleen het accent-op-de-band zakt door de drempel',
      () {
        expect(
          hexContrastRatio(houseAccent, paper)!,
          greaterThan(kWcagAaNormalText),
        );
        expect(
          hexContrastRatio('#FFFFFF', darkBand)!,
          greaterThan(kWcagAaNormalText),
        );
        expect(
          hexContrastRatio(houseAccent, darkBand)!,
          lessThan(kWcagAaLargeText),
        );
      },
    );

    test('een link in de band die wegvalt op zijn eigen band waarschuwt', () {
      final issues = analyse(bandTheme());

      expect(withLabel(issues, 'Thema accent'), isEmpty);
      expect(withLabel(issues, 'Thema documentband'), isEmpty);

      final band = withLabel(issues, 'Thema accent op de documentband');
      expect(band, hasLength(1));
      // De melding landt op de achtergrond en niet op het accent: het accent
      // is een gedeelde kleur die overal elders wél deugt, dus wat aan dít paar
      // te herstellen valt is de band eronder.
      expect(band.single.field, 'documentBandBackgroundColor');
      expect(band.single.args['ratio'], '1.5');
      // Onder de harde ondergrens, en de band is gewone tekst: een fout.
      expect(band.single.severity, MarkdownValidationSeverity.error);
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

    test('een onleesbaar accent meldt niet ook nog op de band', () {
      // Zonder eigen bandachtergrond is de band het papier, en dan is het paar
      // accent-op-de-band letterlijk het paar dat 'Thema accent' al meet — op
      // dezelfde drempel.
      final issues = analyse(
        const ThemeProfile().copyWith(accentColor: belowLarge),
      );

      expect(withLabel(issues, 'Thema accent'), hasLength(1));
      expect(withLabel(issues, 'Thema accent op de documentband'), isEmpty);
    });
  });
}
