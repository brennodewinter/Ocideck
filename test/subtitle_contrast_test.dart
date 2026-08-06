import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/utils/color_contrast.dart';
import 'package:ocideck/utils/title_contrast.dart' show kTitleSubtitleAlpha;

/// Regressie: de ondertitel van een titel- of tussentiteldia staat op verlaagde
/// dekking (kTitleSubtitleAlpha) — een lichtere variant van de titelkleur. De
/// volle titeltekst werd al getoetst, maar die lichtere ondertitel glipte er
/// doorheen: een donkerblauwe achtergrond met een lichterblauwe ondertitel die
/// voor mensen niet te lezen is, zonder enige waarschuwing.
void main() {
  const analyzer = SlideQualityAnalyzer();

  // Lichterblauw op donkerblauw: de volle titeltekst haalt de drempel voor
  // grote tekst (>3:1), maar dezelfde kleur op 0.72 dekking zakt eronder. Zo is
  // de ondertitel aantoonbaar de enige bindende beperking — geen bijvangst van
  // een titel die tóch al zou waarschuwen.
  const darkBlue = '#003366';
  const lightBlue = '#6699CC';

  ThemeProfile theme({String titleText = lightBlue}) =>
      const ThemeProfile().copyWith(
        titleTextColor: titleText,
        titleBackgroundColor: darkBlue,
        sectionBackgroundColor: darkBlue,
      );

  // De ondertiteltoets hergebruikt het bestaande, in alle talen vertaalde label
  // 'Ondertitel' (geen nieuwe l10n-string); de dia-index onderscheidt titel van
  // tussentitel.
  List<SlideQualityIssue> subtitleIssues(List<SlideQualityIssue> issues) =>
      issues
          .where(
            (i) =>
                i.kind == SlideQualityIssueKind.slideContrast &&
                i.args['label'] == 'Ondertitel',
          )
          .toList();

  List<SlideQualityIssue> fullTitleIssues(
    List<SlideQualityIssue> issues,
    String label,
  ) => issues
      .where(
        (i) =>
            i.kind == SlideQualityIssueKind.slideContrast &&
            i.args['label'] == label,
      )
      .toList();

  test('de opzet klopt: vol titelcontrast haalt de drempel, 0.72 niet', () {
    final full = hexContrastRatio(lightBlue, darkBlue)!;
    final subtitle = blendedHexContrastRatio(
      lightBlue,
      darkBlue,
      foregroundAlpha: kTitleSubtitleAlpha,
    )!;
    expect(full, greaterThan(kWcagAaLargeText));
    expect(subtitle, lessThan(kWcagAaLargeText));
  });

  test('tussentitel-ondertitel op een donkere achtergrond waarschuwt', () {
    final result = analyzer.analyzeSlides(
      slides: [
        Slide.create(SlideType.section).copyWith(
          title: 'Deel 2',
          subtitle: 'Een toelichting die niemand kan lezen',
        ),
      ],
      theme: theme(),
      font: 'Arial',
    );
    final subtitle = subtitleIssues(result.issues);
    expect(subtitle, hasLength(1));
    expect(subtitle.single.severity, MarkdownValidationSeverity.warning);
    // De volle titel haalt de drempel, dus daarover geen melding: de ondertitel
    // is de enige bindende beperking.
    expect(fullTitleIssues(result.issues, 'Tussentitel'), isEmpty);
  });

  test('titel-ondertitel op een donkere titelachtergrond waarschuwt', () {
    final result = analyzer.analyzeSlides(
      slides: [
        Slide.create(SlideType.title).copyWith(
          title: 'Welkom',
          subtitle: 'Een ondertitel die wegvalt tegen de achtergrond',
        ),
      ],
      theme: theme(),
      font: 'Arial',
    );
    expect(subtitleIssues(result.issues), hasLength(1));
  });

  test('geen ondertitel, geen ondertitel-melding', () {
    final result = analyzer.analyzeSlides(
      slides: [Slide.create(SlideType.section).copyWith(title: 'Deel 2')],
      theme: theme(),
      font: 'Arial',
    );
    expect(subtitleIssues(result.issues), isEmpty);
  });

  test('een goed leesbare ondertitel waarschuwt niet', () {
    final result = analyzer.analyzeSlides(
      slides: [
        Slide.create(
          SlideType.section,
        ).copyWith(title: 'Deel 2', subtitle: 'Prima leesbaar'),
        Slide.create(
          SlideType.title,
        ).copyWith(title: 'Welkom', subtitle: 'Ook prima'),
      ],
      // Witte tekst op donkerblauw: ruim voldoende, ook op 0.72 dekking.
      theme: theme(titleText: '#FFFFFF'),
      font: 'Arial',
    );
    expect(subtitleIssues(result.issues), isEmpty);
  });

  test('een per-dia titelkleur-override stuurt de ondertiteltoets', () {
    // De render gebruikt de override; de toets moet dat spiegelen. Witte titel
    // in het thema (zou passen), maar een lichterblauwe override op deze dia
    // laat de ondertitel alsnog wegvallen.
    final result = analyzer.analyzeSlides(
      slides: [
        Slide.create(SlideType.section).copyWith(
          title: 'Deel 2',
          subtitle: 'Valt weg door de override',
          titleTextColorOverride: lightBlue,
        ),
      ],
      theme: theme(titleText: '#FFFFFF'),
      font: 'Arial',
    );
    expect(subtitleIssues(result.issues), hasLength(1));
  });
}
