import '../models/deck.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../utils/bullet_fixes.dart';
import '../utils/color_contrast.dart';
import 'slide_quality_analyzer.dart';

/// Uitkomst van [fixAllStructuralQualityIssues]: het opgeschoonde deck en
/// hoeveel structurele fixes zijn toegepast. Nul betekent "niets dat zich
/// automatisch en veilig laat oplossen" — dan blijft het deck ongewijzigd.
typedef QualityAutofixResult = ({Deck deck, int applied});

/// De kwaliteitsmeldingen die "Splits slide" wegneemt: te veel bullets, te veel
/// woorden, of een dia die fysiek te klein rendert. Splitsen verdeelt de inhoud
/// over pagina's en houdt alles zichtbaar.
///
/// Bewust niet hierin: gemiddelde bulletlengte en diepe nesting (die lossen niet
/// op door te splitsen — de dia krijgt niet minder bullets per stuk), en
/// meerzins-bullets (die hebben hun eigen fix, [splitSentenceBullets]).
const Set<SlideQualityIssueKind> _splitClearableKinds = {
  SlideQualityIssueKind.textDensityWarning,
  SlideQualityIssueKind.textDensityCritical,
  SlideQualityIssueKind.bulletCountHigh,
  SlideQualityIssueKind.bulletCountCritical,
  SlideQualityIssueKind.bulletWordCountHigh,
  SlideQualityIssueKind.bulletWordCountCritical,
};

/// Of een melding van [kind] tot de structurele fixes hoort die de fix-alles-
/// knop kan wegwerken — zodat de UI de knop alleen aanbiedt als hij iets doet.
/// De uiteindelijke toepasbaarheid hangt óók van de dia af (genoeg bullets om te
/// splitsen); dit is de goedkope voorselectie op de melding zelf.
bool isStructurallyAutofixable(SlideQualityIssueKind kind) =>
    kind == SlideQualityIssueKind.bulletMultiSentence ||
    kind == SlideQualityIssueKind.splitRunDragged ||
    _splitClearableKinds.contains(kind);

/// Werkt alle automatisch én veilig oplosbare kwaliteitsproblemen weg, met
/// steeds de meest veilige oplossing (#915). "Veilig" is hier strikt: alleen
/// omkeerbare, structurele fixes die álle inhoud zichtbaar houden —
///
///  1. meerzins-bullets opknippen in losse bullets (alles blijft op de dia);
///  2. te volle dia's splitsen over pagina's;
///  3. een meegesleepte pagina uit zijn gesplitste reeks losmaken.
///
/// Nooit wordt inhoud van een dia gehaald. Contrastkleuren worden wel veilig
/// gecorrigeerd: iedere kleur verschuift zo weinig mogelijk naar zwart of wit
/// totdat zij voor haar werkelijke visuele rol aan de ingestelde norm voldoet.
/// Wat echt menselijk oordeel vraagt (alt-tekst en privacy) blijft staan.
///
/// De motor draait als een vast punt: analyseer, pas de eerste toepasbare fix
/// toe, en herhaal tot er niets meer verandert. Eén fix per ronde, met een verse
/// analyse ertussen, zodat verschoven indexen na een splitsing altijd kloppen.
QualityAutofixResult fixAllStructuralQualityIssues(
  Deck deck, {
  SlideQualityAnalyzer analyzer = const SlideQualityAnalyzer(),
}) {
  var current = deck;
  var applied = 0;
  // Ruime bovengrens tegen een niet-eindigende lus. In de praktijk stopt de lus
  // uit zichzelf: elke fix verkleint een monotone maat (minder meerzins-bullets,
  // minder te-vol, minder meegesleepte pagina's). De grens is het vangnet: een
  // splitsing maakt hooguit zoveel pagina's als er bullets zijn, plus marge.
  final maxRounds = _totalBullets(deck) * 2 + deck.slides.length * 4 + 50;
  for (var round = 0; round < maxRounds; round++) {
    final next = _applyNextFix(current, analyzer);
    if (next == null) break;
    current = next;
    applied++;
  }
  final contrastFixed = _fixThemeContrast(current, analyzer);
  if (contrastFixed != null) {
    current = contrastFixed;
    applied++;
  }
  return (deck: current, applied: applied);
}

/// Of [fixAllStructuralQualityIssues] op dit deck werkelijk íets zou wegwerken —
/// de motor-accurate poort voor de "los automatisch op wat kan"-knop (#1280).
///
/// [isStructurallyAutofixable] toetst alleen de *soort* melding en is daarmee
/// ruimer dan de motor: een woord-melding op een dia met te weinig bullets om te
/// splitsen telt daar als "fixbaar", terwijl [_applyNextFix] er niets mee kan.
/// Die divergentie liet de knop verschijnen om vervolgens niets te doen. Deze
/// helper spiegelt de echte motorpoort, zodat geldt: knop zichtbaar ⇔ er wordt
/// ook echt een fix toegepast. Goedkoop: één analyse, geen deck-mutatie.
bool hasApplicableStructuralFix(
  Deck deck, {
  SlideQualityAnalyzer analyzer = const SlideQualityAnalyzer(),
}) =>
    _applyNextFix(deck, analyzer) != null ||
    _fixThemeContrast(deck, analyzer) != null;

Deck? _fixThemeContrast(Deck deck, SlideQualityAnalyzer analyzer) {
  var theme = deck.themeProfile;
  var changed = false;
  // Re-analyse after each field: textColor, for example, can clear both body
  // and footer findings. This also keeps this routine aligned with custom user
  // thresholds instead of duplicating the analyzer's decision logic.
  for (var pass = 0; pass < 16; pass++) {
    final issue = analyzer
        .analyze(deck.copyWith(themeProfile: theme))
        .issues
        .where((i) => i.category == SlideQualityCategory.contrast)
        .where((i) => i.isDeckWide && i.field != null)
        .firstOrNull;
    if (issue == null) break;
    final threshold =
        double.tryParse(issue.args['threshold'] ?? '') ??
        analyzer.minContrastRatio;
    final field = issue.field!;
    String corrected(
      String foreground,
      String background, {
      double alpha = 1,
    }) => nearestContrastingHex(
      foreground,
      background,
      minRatio: threshold,
      foregroundAlpha: alpha,
    );
    final before = theme;
    switch (field) {
      case 'textColor':
        theme = theme.copyWith(
          textColor: corrected(
            theme.textColor,
            theme.slideBackgroundColor,
            alpha: issue.kind == SlideQualityIssueKind.footerContrast
                ? kFooterTextAlpha
                : 1,
          ),
        );
      case 'accentColor':
        theme = theme.copyWith(
          accentColor: corrected(theme.accentColor, theme.slideBackgroundColor),
        );
      case 'titleTextColor':
        theme = theme.copyWith(
          titleTextColor: corrected(
            theme.titleTextColor,
            theme.titleBackgroundColor,
          ),
        );
      case 'tableTextColor':
        theme = theme.copyWith(
          tableTextColor: corrected(
            theme.tableTextColor,
            theme.slideBackgroundColor,
          ),
        );
      case 'tableHeaderTextColor':
        theme = theme.copyWith(
          tableHeaderTextColor: corrected(
            theme.tableHeaderTextColor,
            theme.tableHeaderBackgroundColor,
          ),
        );
      case 'codeTextColor':
        theme = theme.copyWith(
          codeTextColor: corrected(
            theme.codeTextColor,
            theme.codeBackgroundColor,
          ),
        );
      case 'checklistCheckedColor':
        theme = theme.copyWith(
          checklistCheckedColor: corrected(
            theme.checklistCheckedColor,
            theme.slideBackgroundColor,
          ),
        );
      case 'checklistUncheckedColor':
        theme = theme.copyWith(
          checklistUncheckedColor: corrected(
            theme.checklistUncheckedColor,
            theme.slideBackgroundColor,
          ),
        );
      default:
        return changed ? deck.copyWith(themeProfile: theme) : null;
    }
    if (theme == before) break;
    changed = true;
  }
  return changed ? deck.copyWith(themeProfile: theme) : null;
}

int _totalBullets(Deck deck) => deck.slides.fold<int>(
  0,
  (sum, s) => sum + s.bullets.length + s.bullets2.length,
);

/// De veilige structurele fix voor één losse dia — de live-fix tijdens
/// presenteren (#914). Geeft de nieuwe pagina('s) terug die deze ene dia
/// vervangen, of `null` als er niets veiligs te doen valt:
///
///  * één dia terug → in-place opknippen (meerzins-bullets → losse bullets), de
///    dia blijft één dia;
///  * meer dan één dia → splitsen over pagina's.
///
/// Gebruikt dezelfde volgorde en drempels als [fixAllStructuralQualityIssues],
/// zodat "fixen" tijdens presenteren precies zo werkt als in de editor. [slide]
/// wordt op zichzelf beoordeeld ([theme] bepaalt de inpassing); een reeks-effect
/// als meegesleepte tekstgrootte hoort niet bij het oplossen van één dia.
List<Slide>? safeFixForSlide(
  Slide slide,
  ThemeProfile theme, {
  String? projectPath,
  SlideQualityAnalyzer analyzer = const SlideQualityAnalyzer(),
}) {
  final issues = analyzer
      .analyzeSlides(
        slides: [slide],
        theme: theme,
        font: theme.fontFamily,
        projectPath: projectPath,
      )
      .forSlide(0);
  // 1. Meerzins-bullets → opknippen (blijft op de dia).
  if (issues.any((i) => i.kind == SlideQualityIssueKind.bulletMultiSentence) &&
      canSplitSentenceBullets(slide)) {
    return [splitSentenceBullets(slide)];
  }
  // 2. Te vol → splitsen; null wanneer de dia niet te splitsen valt. De gate
  //    zit in [_shouldSplitFor]: boven de bulletdrempel altijd, en eronder
  //    alleen wanneer de dia te klein rendert door lánge bullets — dan
  //    vergroot splitsen de tekst nog steeds. Anders blijft de melding staan
  //    zodat de gebruiker "Uitleg naar notities" kan kiezen.
  if (issues.any(
    (i) =>
        _splitClearableKinds.contains(i.kind) && _shouldSplitFor(slide, i.kind),
  )) {
    return splitBulletSlidePages(slide);
  }
  return null;
}

/// Past de eerste toepasbare structurele fix toe en geeft het nieuwe deck terug,
/// of `null` als er niets meer te doen is. De volgorde is de "juiste volgorde"
/// uit #915: eerst opknippen wat op de dia kan blijven, dan splitsen, en als
/// laatste een reeks losmaken.
Deck? _applyNextFix(Deck deck, SlideQualityAnalyzer analyzer) {
  final result = analyzer.analyze(deck);

  // 1. Meerzins-bullets: opknippen in losse bullets. Alleen wanneer het
  //    resultaat binnen de leesbaarheidsdrempel blijft (canSplitSentenceBullets);
  //    anders is de dia te vol en neemt stap 2 het over.
  for (final issue in result.issues) {
    if (issue.kind != SlideQualityIssueKind.bulletMultiSentence) continue;
    final slide = _slideAt(deck, issue.slideIndex);
    if (slide == null || !canSplitSentenceBullets(slide)) continue;
    return _replaceSlide(deck, issue.slideIndex, [splitSentenceBullets(slide)]);
  }

  // 2. Te volle dia's: splitsen over pagina's. Boven de drempel altijd; eronder
  //    alleen wanneer de dia te klein rendert door lange bullets (zie
  //    [_shouldSplitFor]) — dan verdeelt splitsen de inhoud over pagina's die
  //    elk groter renderen. Bij een aantal-melding onder de drempel blijft de
  //    melding staan zodat de gebruiker "Uitleg naar notities" kan kiezen.
  for (final issue in result.issues) {
    if (!_splitClearableKinds.contains(issue.kind)) continue;
    final slide = _slideAt(deck, issue.slideIndex);
    if (slide == null) continue;
    if (!_shouldSplitFor(slide, issue.kind)) continue;
    final pages = splitBulletSlidePages(slide);
    if (pages == null) continue;
    return _replaceSlide(deck, issue.slideIndex, pages);
  }

  // 3. Meegesleepte pagina: losmaken uit de reeks. Als laatste, want een
  //    splitsing in stap 2 heft de meeste sleep-meldingen al op.
  for (final issue in result.issues) {
    if (issue.kind != SlideQualityIssueKind.splitRunDragged) continue;
    final offender = int.tryParse(issue.args['offender'] ?? '');
    if (offender == null) continue;
    final detached = _detachRun(deck, offender);
    if (detached != null) return detached;
  }

  return null;
}

/// Of "Splits slide" [slide] moet aanpakken voor een melding van [kind].
///
/// Boven de leesbaarheidsdrempel: altijd — de dia draagt simpelweg te veel
/// bullets, en verdelen is de enige remedie. Eronder splitsen we alleen wanneer
/// de dia te klein *rendert* ([SlideQualityIssueKind.textDensityWarning] of
/// `…Critical`) én er genoeg bullets zijn voor twee volwaardige pagina's: dan
/// komt de overloop uit de lengte van de bullets, niet uit hun aantal, en
/// verdeelt splitsen ze over pagina's die elk groter renderen (#1159). Zo wordt
/// de font ook vergroot bij weinig-maar-lange bullets.
///
/// Een zuivere aantal- of woord-melding (te veel bullets, te veel woorden in één
/// bullet) onder de drempel splitsen we níet — dat levert flinters van één of
/// twee bullets op zonder de melding op te lossen.
bool _shouldSplitFor(Slide slide, SlideQualityIssueKind kind) {
  if (visibleContentBulletCount(slide) > _splitThreshold(slide)) return true;
  final rendersTooSmall =
      kind == SlideQualityIssueKind.textDensityWarning ||
      kind == SlideQualityIssueKind.textDensityCritical;
  return rendersTooSmall && hasBulletsForFontEnlargingSplit(slide);
}

/// De paginadrempel waarboven splitsen zinvol is: het aantal bullets dat op
/// één pagina past volgens de leesbaarheidsnorm. Alleen boven deze grens
/// verdeelt "Splits slide" de inhoud; bij ≤ drempel blijft de melding staan
/// en kiest de gebruiker "Uitleg naar notities".
int _splitThreshold(Slide slide) => slide.type == SlideType.twoBullets
    ? kTwoColumnBulletWarningCount
    : (slide.listStyle == ListStyle.checklist
          ? kChecklistBulletWarningCount
          : kSingleColumnBulletWarningCount);

Slide? _slideAt(Deck deck, int index) =>
    index >= 0 && index < deck.slides.length ? deck.slides[index] : null;

Deck _replaceSlide(Deck deck, int index, List<Slide> pages) {
  final slides = List<Slide>.from(deck.slides)
    ..removeAt(index)
    ..insertAll(index, pages);
  return deck.copyWith(slides: slides);
}

/// Breekt de gesplitste reeks vóór en ná de dia op [offender], zodat die op
/// zichzelf komt te staan en de rest van de reeks weer op eigen grootte rendert.
/// Alleen de vlaggen gaan om; `null` als er niets te breken viel. Spiegelt
/// [DeckNotifier.detachSplitPage] zodat de knop en de motor hetzelfde doen.
Deck? _detachRun(Deck deck, int offender) {
  if (offender < 0 || offender >= deck.slides.length) return null;
  final slides = List<Slide>.from(deck.slides);
  var changed = false;
  if (slides[offender].continuesSplit) {
    slides[offender] = slides[offender].copyWith(continuesSplit: false);
    changed = true;
  }
  final next = offender + 1;
  if (next < slides.length && slides[next].continuesSplit) {
    slides[next] = slides[next].copyWith(continuesSplit: false);
    changed = true;
  }
  if (!changed) return null;
  return deck.copyWith(slides: slides);
}
