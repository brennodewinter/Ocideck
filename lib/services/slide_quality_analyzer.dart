import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/asset_origin.dart';
import '../models/chart.dart';
import '../models/deck.dart';
import '../models/image_callout.dart';
import 'menu_blocks.dart';
import '../models/finding_spec.dart';
import '../models/markdown_validation.dart';
import '../models/question.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../models/video_source.dart';
import '../utils/color_contrast.dart';
import '../utils/inline_markdown.dart';
import '../utils/project_path.dart';
import '../utils/title_contrast.dart' show kTitleSubtitleAlpha;
import 'improvement/matrix_slide.dart';
import 'slide_image_refs.dart';
import 'slide_layout_metrics.dart';
import 'split_run.dart';

part 'slide_quality/slide_quality_analyzer_content.dart';
part 'slide_quality/slide_quality_analyzer_density.dart';

/// Waarschuw voor een dia die niets zou tonen.
///
/// Dit is de algemene vorm van #583. Daar zag een scorecard er in de editor
/// ingevuld uit — elk veld droeg zijn placeholder als gewone zwarte tekst —
/// terwijl de dia wit rendeerde, de kwaliteitscontrole "geen problemen" zei
/// en de export een lege pagina schreef. Elk vangnet wees op hetzelfde
/// moment de verkeerde kant op, en de auteur stond ermee voor de zaal.
///
/// De controle gaat daarom niet over dat ene type maar over de vorm: valt er
/// niets te tonen, dan hoort dat gezegd te worden. Een waarschuwing en geen
/// fout — een dia die je nog moet vullen is geen vergissing, en tijdens het
/// schrijven mag de melding meelopen zonder je tegen te houden.
void _checkEmptySlide(Slide slide, int index, List<SlideQualityIssue> issues) {
  if (_hasVisibleContent(slide)) return;
  issues.add(
    SlideQualityIssue(
      slideIndex: index,
      kind: SlideQualityIssueKind.emptySlide,
      category: SlideQualityCategory.content,
      severity: MarkdownValidationSeverity.warning,
      field: 'title',
    ),
  );
}

/// De callout-checker (IMAGE_CALLOUTS.md §2.6). Vier regels, alle per-slide:
///
/// 1. **Invalid geometry** — een target met coördinaten buiten [0,1] of een
///    verkeerd aantal componenten. De codec weigert het te tekenen; de checker
///    meldt het zodat de auteur weet waarom de pijl ontbreekt.
/// 2. **Orphan reference** — een callout-entry in de front matter zonder
///    bijbehorende `(A)`-markering in de tekst, of omgekeerd.
/// 3. **Duplicate reference** — dezelfde letter twee keer op één dia.
/// 4. **Missing anchor** — de dia heeft callouts maar geen anker, dus de front
///    matter kan ze niet aan de dia koppelen.
///
/// De checker rapporteert alleen — hij clamp niet, verwijdert niet, en herschikt
/// niet. De codec behoudt alles byte-voor-byte (§2.5).
void _checkCallouts(Slide slide, int index, List<SlideQualityIssue> issues) {
  if (slide.callouts.isEmpty) return;

  // §2.6 binding regel 4: een dia met callouts moet een anker hebben.
  if (slide.anchor.isEmpty) {
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.calloutMissingAnchor,
        category: SlideQualityCategory.callout,
        severity: MarkdownValidationSeverity.error,
      ),
    );
  }

  // Verzamel alle (A)-markeringen in de tekst van deze dia, met telling: een
  // letter die twee keer voorkomt (geplakte bullet) is een duplicate finding
  // (§2.6), geen geldige referentie.
  final textRefCount = <String, int>{};
  for (final bullet in [...slide.bullets, ...slide.bullets2]) {
    for (final m in _reCalloutReference.allMatches(bullet)) {
      final ref = m.group(1)!;
      textRefCount[ref] = (textRefCount[ref] ?? 0) + 1;
    }
  }
  final textRefs = textRefCount.keys.toSet();

  // §2.6: twee of meer bullets eindigen op (X) → duplicate finding.
  for (final entry in textRefCount.entries) {
    if (entry.value > 1) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutDuplicateReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.error,
          args: {'ref': '(${entry.key})'},
        ),
      );
    }
  }

  // Track welke refs we al gezien hebben voor duplicate detection.
  final seen = <String>{};
  for (final callout in slide.callouts) {
    final ref = callout.reference;

    // Duplicate: dezelfde letter twee keer.
    if (!seen.add(ref)) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutDuplicateReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.error,
          args: {'ref': '($ref)'},
        ),
      );
    }

    // Invalid geometry: een target buiten [0,1] of met verkeerde componenten.
    // §8: een region heeft minimaal 0.02 op beide assen.
    for (final target in callout.targets) {
      final tooSmall =
          target is CalloutRegion && (target.w < 0.02 || target.h < 0.02);
      if (!target.isValid || tooSmall) {
        issues.add(
          SlideQualityIssue(
            slideIndex: index,
            kind: SlideQualityIssueKind.calloutInvalidGeometry,
            category: SlideQualityCategory.callout,
            severity: MarkdownValidationSeverity.error,
            args: {'ref': '($ref)'},
          ),
        );
        break;
      }
    }

    // Orphan: entry in front matter zonder (A) in de tekst.
    if (!textRefs.contains(ref)) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutOrphanReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.warning,
          args: {'ref': '($ref)'},
        ),
      );
    }
  }

  // Orphan: (A) in de tekst zonder entry in de front matter.
  final entryRefs = slide.callouts.map((c) => c.reference).toSet();
  for (final ref in textRefs) {
    if (!entryRefs.contains(ref)) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutOrphanReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.warning,
          args: {'ref': '($ref)'},
        ),
      );
    }
  }
}

/// Herkent een `(A)`-calloutmarkering in slidetekst. Eén hoofdletter tussen
/// haakjes, optioneel gevolgd door een puntkomma of spatie — niet `(AB)` of
/// `(a)`, en niet een haakje dat toevallig in een afkorting staat.
final _reCalloutReference = RegExp(r'\(([A-Z])\)(?:[;,\s]|$)');

/// Draagt [slide] iets dat de kijker te zien krijgt?
///
/// Alleen wat de auteur zelf invulde telt. Vaste kopregels die de app zelf
/// aanmaakt (de kop van een checklist, van een scope-matrix) staan wél in
/// `tableRows` maar zijn niets van hem — een dia die alleen díé draagt is
/// precies de lege dia waar dit over gaat. Vandaar de vergelijking met een
/// vers aangemaakte dia van hetzelfde type: wat daar ook al in staat, is
/// geen inhoud.
///
/// Dat maakt de regel bovendien zelfonderhoudend. Een nieuw slidetype dat
/// zijn eigen beginstand meebrengt, krijgt de juiste ondergrens zonder dat
/// iemand hier iets toevoegt — en dat is bij [SlideType] geen luxe: de
/// compiler wijst maar een handvol van de plekken aan die zo'n type raakt.
bool _hasVisibleContent(Slide slide) =>
    _contentFingerprint(slide) != _contentFingerprint(_blankOfType(slide.type));

/// Alles wat een kijker van [slide] te zien kan krijgen, achter elkaar.
///
/// Notities, thema-instellingen en de TLP-markering staan er bewust niet in:
/// een dia waarop alleen een sprekersnotitie staat, toont de zaal niets.
String _contentFingerprint(Slide slide) {
  final parts = <String>[
    slide.title,
    slide.subtitle,
    ...slide.bullets,
    ...slide.bullets2,
    slide.columnTitle1,
    slide.columnTitle2,
    slide.quote,
    slide.quoteAuthor,
    slide.imagePath,
    slide.imagePath2,
    slide.imageCaption,
    slide.imageCaption2,
    slide.videoPath,
    slide.audioPath,
    slide.customMarkdown,
    for (final row in slide.tableRows) ...row,
  ];
  return parts.map((p) => p.trim()).join('\u0000');
}

/// Een verse dia van [type], één keer per type aangemaakt.
///
/// [Slide.create] genereert een id en is dus niet gratis; de analyse loopt
/// over elke dia bij elke bewerking.
final Map<SlideType, Slide> _blanks = {};
Slide _blankOfType(SlideType type) => _blanks[type] ??= Slide.create(type);

/// Cached fit-scale per slide, so re-analysing a deck after an edit only
/// re-measures the slide that actually changed. The quality provider re-runs
/// [SlideQualityAnalyzer.analyze] on every deck edit, and a single bullet-slide
/// fit-scale costs several milliseconds of TextPainter layout; for a deck of any
/// size that recomputation dominated the analysis. Editing one slide replaces
/// only that slide's object (see `DeckNotifier.updateSlide`), so the unchanged
/// slides keep their identity and hit this cache. The [Expando] is weak-keyed:
/// entries are collected once a slide is no longer referenced, so the cache
/// never leaks. The key is (slide identity, font); a changed slide is a new
/// object — never a stale hit — and a font change misses via [_FitMemo.font].
final Expando<_FitMemo> _fitScaleCache = Expando<_FitMemo>('slideFitScale');

@visibleForTesting
double memoizedFitScale(Slide slide, String font, double Function() compute) {
  final cached = _fitScaleCache[slide];
  if (cached != null && cached.font == font) return cached.scale;
  final scale = compute();
  _fitScaleCache[slide] = _FitMemo(font, scale);
  return scale;
}

/// Cached per-slide issue list, same weak-keyed identity idea as
/// [_fitScaleCache] but for de volledige per-slide analyse. Die omvat naast de
/// (al gememoiseerde) fit-scale ook `File.existsSync` voor media,
/// `ChartSpec.parse` en regex-scans over bullets — werk dat anders bij elke
/// toetsaanslag voor élke slide opnieuw draait. Een edit vervangt alleen het
/// object van de bewerkte slide, dus ongewijzigde slides hiten deze cache.
/// Kanttekening: of een mediabestand bestaat wordt voor een slide dus pas
/// opnieuw op schijf gecheckt wanneer die slide (of thema/instelling) wijzigt.
final Expando<_SlideIssuesMemo> _slideIssuesCache = Expando<_SlideIssuesMemo>(
  'slideQualityIssues',
);

/// Maximum combined quote + author length before a density warning.
const int kQuoteDensityCharThreshold = 750;

/// Readability guardrails for bullet-heavy slides. The existing fit-scale check
/// catches physical overflow; these thresholds catch slides that still fit but
/// are likely too dense for an audience to read comfortably.
const int kSingleColumnBulletWarningCount = 8;
const int kSingleColumnBulletCriticalCount = 14;

/// Checklists mogen meer regels dragen voor een waarschuwing verschijnt: een
/// af te vinken takenlijst kan een legitiem zakelijk doel dienen waar acht
/// regels te beperkend voor is.
const int kChecklistBulletWarningCount = 12;
const int kTwoColumnBulletWarningCount = 14;
const int kTwoColumnBulletCriticalCount = 22;
const int kSingleColumnWordWarningCount = 90;
const int kSingleColumnWordCriticalCount = 150;
const int kTwoColumnWordWarningCount = 120;
const int kTwoColumnWordCriticalCount = 220;
const int kAverageBulletWordInfoCount = 15;
const int kAverageBulletWordWarningCount = 25;
const int kLongMultiSentenceBulletWordCount = 24;
const int kBulletDisplayLevelWarning = 3;

/// Maximum combined title + subtitle length before a density warning.
const int kTitleDensityCharThreshold = 120;

/// Footer text opacity in slide previews — keep in sync with overlays.dart.
const double kFooterTextAlpha = 0.7;

/// Analyses deck slides for accessibility and readability quality issues.
class SlideQualityAnalyzer {
  /// Minimum acceptable contrast ratio for normal-size text. Defaults to the
  /// WCAG AA threshold ([kWcagAaNormalText] = 4.5); the user can relax it via
  /// settings (e.g. 3.5) when they accept slightly lower contrast. Large text
  /// still uses the lower of this and the WCAG large-text threshold (3.0), and
  /// the hard-error floor stays at [kWcagCriticalBodyText].
  final double minContrastRatio;

  const SlideQualityAnalyzer({this.minContrastRatio = kWcagAaNormalText});

  SlideQualityResult analyze(Deck deck) => analyzeSlides(
    slides: deck.slides,
    theme: deck.themeProfile,
    font: deck.themeProfile.fontFamily,
    projectPath: deck.projectPath,
  );

  SlideQualityResult analyzeSlides({
    required List<Slide> slides,
    required ThemeProfile theme,
    required String font,
    String? projectPath,
  }) {
    final issues = <SlideQualityIssue>[];
    _checkThemeContrast(theme, issues, minContrastRatio: minContrastRatio);
    _checkFooterContrast(theme, issues);
    _checkChecklistContrast(theme, slides, issues);
    for (var i = 0; i < slides.length; i++) {
      final slide = slides[i];
      if (slide.skipped) continue;
      issues.addAll(_memoizedSlideIssues(slide, i, theme, font, projectPath));
    }
    // Bewust buiten de per-slide memo: of een slide klein rendert hangt af van
    // zijn buren, en die cache is op slide-identiteit gesleuteld. Binnen de memo
    // zou een melding blijven staan nadat de buurslide veranderde.
    _checkSplitRuns(slides, theme, font, issues);
    // Ook deckbreed, en om dezelfde reden buiten de per-dia memo: of een sprong
    // ergens uitkomt hangt af van de ándere dia's.
    _checkDanglingJumps(slides, issues);
    return SlideQualityResult(issues);
  }

  List<SlideQualityIssue> _memoizedSlideIssues(
    Slide slide,
    int index,
    ThemeProfile theme,
    String font,
    String? projectPath,
  ) {
    final memo = _slideIssuesCache[slide];
    if (memo != null &&
        identical(memo.theme, theme) &&
        memo.font == font &&
        memo.projectPath == projectPath &&
        memo.minContrastRatio == minContrastRatio) {
      if (memo.index == index) return memo.issues;
      // Slide is verschoven (invoegen/verwijderen elders): alleen de index in
      // de issues herschrijven, de analyse zelf blijft geldig.
      final reindexed = [
        for (final issue in memo.issues)
          SlideQualityIssue(
            slideIndex: index,
            kind: issue.kind,
            category: issue.category,
            severity: issue.severity,
            field: issue.field,
            args: issue.args,
          ),
      ];
      _slideIssuesCache[slide] = memo.withIndex(index, reindexed);
      return reindexed;
    }
    final issues = <SlideQualityIssue>[];
    _checkMediaDescriptions(slide, index, issues);
    _checkSlideContrast(slide, index, theme, issues);
    _checkTextDensity(slide, index, font, issues);
    _checkMissingMedia(slide, index, projectPath, issues);
    // Hangen alleen van de slide-inhoud af, dus veilig per slide te cachen.
    _checkQuestionAnswerable(slide, index, issues);
    _checkFindingSections(slide, index, issues);
    _checkEmptySlide(slide, index, issues);
    _checkCallouts(slide, index, issues);
    _slideIssuesCache[slide] = _SlideIssuesMemo(
      theme: theme,
      font: font,
      projectPath: projectPath,
      minContrastRatio: minContrastRatio,
      index: index,
      issues: issues,
    );
    return issues;
  }

  void _checkFooterContrast(
    ThemeProfile theme,
    List<SlideQualityIssue> issues,
  ) {
    if (theme.footerText.trim().isEmpty && !theme.footerShowPageNumbers) return;

    final ratio = blendedHexContrastRatio(
      theme.textColor,
      theme.slideBackgroundColor,
      foregroundAlpha: kFooterTextAlpha,
    );
    if (ratio == null) return;
    final aaThreshold = minContrastRatio;
    if (ratio >= aaThreshold) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: kDeckWideSlideIndex,
        kind: SlideQualityIssueKind.footerContrast,
        category: SlideQualityCategory.contrast,
        severity: MarkdownValidationSeverity.warning,
        field: 'textColor',
        args: {
          'label': 'Footer-tekst',
          'ratio': ratio.toStringAsFixed(1),
          'threshold': aaThreshold.toStringAsFixed(1),
          'largeText': 'false',
        },
      ),
    );
  }

  void _checkChecklistContrast(
    ThemeProfile theme,
    List<Slide> slides,
    List<SlideQualityIssue> issues,
  ) {
    final usesChecklist = slides.any(
      (slide) =>
          !slide.skipped &&
          (slide.type == SlideType.bullets ||
              slide.type == SlideType.twoBullets ||
              slide.type == SlideType.bulletsImage) &&
          slide.listStyle == ListStyle.checklist,
    );
    if (!usesChecklist) return;
    void addPair({
      required String label,
      required String foreground,
      required String field,
    }) {
      final ratio = hexContrastRatio(foreground, theme.slideBackgroundColor);
      if (ratio == null) return;
      // Checkbox outlines/checkmarks are non-text UI graphics. WCAG 1.4.11
      // requires 3:1 here; treating them as body copy (4.5:1) produced noisy
      // warnings for intentionally subtle, but perfectly visible controls.
      final aaThreshold = math.min(kWcagAaLargeText, minContrastRatio);
      if (ratio >= aaThreshold) return;

      issues.add(
        SlideQualityIssue(
          slideIndex: kDeckWideSlideIndex,
          kind: SlideQualityIssueKind.checklistContrast,
          category: SlideQualityCategory.contrast,
          severity: MarkdownValidationSeverity.warning,
          field: field,
          args: {
            'label': label,
            'ratio': ratio.toStringAsFixed(1),
            'threshold': aaThreshold.toStringAsFixed(1),
            'largeText': 'false',
          },
        ),
      );
    }

    addPair(
      label: 'Checklist (niet aangevinkt)',
      foreground: theme.checklistUncheckedColor,
      field: 'checklistUncheckedColor',
    );
    addPair(
      label: 'Checklist (aangevinkt)',
      foreground: theme.checklistCheckedColor,
      field: 'checklistCheckedColor',
    );
  }

  void _checkSlideContrast(
    Slide slide,
    int index,
    ThemeProfile theme,
    List<SlideQualityIssue> issues,
  ) {
    switch (slide.type) {
      case SlideType.section:
        _addSlidePairIssue(
          issues: issues,
          slideIndex: index,
          label: 'Tussentitel',
          foreground: theme.titleTextColor,
          background: theme.sectionBackgroundColor,
          minContrastRatio: minContrastRatio,
        );
        _addSubtitleContrastIssue(
          issues: issues,
          slideIndex: index,
          label: 'Ondertitel',
          slide: slide,
          theme: theme,
          background: theme.sectionBackgroundColor,
          minContrastRatio: minContrastRatio,
        );
      // De titeldia zelf toetst de titeltekst tegen de titelachtergrond
      // dekbreed ([_checkThemeContrast]); hier komt alleen de ondertitel bij,
      // die met verlaagde dekking ([kTitleSubtitleAlpha]) een lichtere — en dus
      // zwakker contrasterende — variant van dezelfde kleur is en anders
      // ongetoetst blijft (#1279-vervolg).
      case SlideType.title:
        _addSubtitleContrastIssue(
          issues: issues,
          slideIndex: index,
          label: 'Ondertitel',
          slide: slide,
          theme: theme,
          background: theme.titleBackgroundColor,
          minContrastRatio: minContrastRatio,
        );
      // Bewust uitgeschreven in plaats van een `default:`. Een `default` zet de
      // exhaustiviteitswaarschuwing van de analyzer uit, en dan valt slidetype
      // #25 hier stil: geen contrastcontrole, en niemand die het merkt. Nu
      // weigert de compiler een nieuw type tot iemand beslist heeft of het een
      // eigen voor-/achtergrondpaar heeft dat gekeurd moet worden.
      case SlideType.bullets ||
          SlideType.menu ||
          SlideType.twoBullets ||
          SlideType.bulletsImage ||
          SlideType.twoImages ||
          SlideType.image ||
          SlideType.video ||
          SlideType.quote ||
          SlideType.table ||
          SlideType.freeMarkdown ||
          SlideType.code ||
          SlideType.chart ||
          SlideType.cockpit ||
          SlideType.question ||
          SlideType.timeline ||
          SlideType.scorecard ||
          SlideType.assets ||
          SlideType.discoveries ||
          SlideType.finding ||
          SlideType.findingsSummary ||
          SlideType.checklist ||
          SlideType.scopeMatrix ||
          SlideType.controlStatus ||
          SlideType.signOff ||
          SlideType.matrix ||
          SlideType.canvas ||
          SlideType.tree ||
          SlideType.flow ||
          SlideType.phaseGate ||
          SlideType.gantt:
        break;
    }
  }

  void _checkMediaDescriptions(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    switch (slide.type) {
      case SlideType.chart:
        _checkChartAltText(slide, index, issues);
      case SlideType.image:
      case SlideType.twoImages:
      case SlideType.bulletsImage:
        _checkMediaAltText(
          slide: slide,
          index: index,
          issues: issues,
          hasMedia:
              slide.imagePath.trim().isNotEmpty ||
              slide.imagePath2.trim().isNotEmpty,
          label: 'Afbeelding',
        );
      // Video is bewust géén alt-tekst-nudge: een videoslide zonder titel is
      // een legitieme keuze (de clip spreekt voor zich), en de tip dook op bij
      // élke video omdat de video-editor alleen een titelveld heeft — er is
      // geen bijschrift- of alt-tekstveld om hem mee te stillen.
      case SlideType.video:
      case SlideType.title:
      case SlideType.quote:
      case SlideType.bullets:
      // Menublok-afbeeldingen zitten per blok in de bullet-tekst, niet in
      // [Slide.imagePath]; alt-tekst per blok is een latere verfijning.
      case SlideType.menu:
      case SlideType.twoBullets:
      case SlideType.section:
      case SlideType.table:
      case SlideType.freeMarkdown:
      case SlideType.code:
      case SlideType.cockpit:
      case SlideType.question:
      case SlideType.timeline:
      case SlideType.scorecard:
      case SlideType.assets:
      case SlideType.discoveries:
      case SlideType.finding:
      case SlideType.findingsSummary:
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.controlStatus:
      case SlideType.signOff:
      // Een matrix draagt geen media; zijn cellen zijn de inhoud zelf.
      case SlideType.matrix:
      case SlideType.canvas:
      case SlideType.tree:
      case SlideType.flow:
      case SlideType.phaseGate:
      case SlideType.gantt:
        break;
    }
  }

  void _checkMediaAltText({
    required Slide slide,
    required int index,
    required List<SlideQualityIssue> issues,
    required bool hasMedia,
    required String label,
  }) {
    if (!hasMedia) return;
    // Per-usage alt-text (AI_ASSIST §6.1) or the visible caption clears the
    // nudge just as a title/notes/subtitle does — all of them give a screen
    // reader something to announce (see [imageSemanticsLabel]).
    final hasDescription =
        slide.title.trim().isNotEmpty ||
        slide.notes.trim().isNotEmpty ||
        slide.subtitle.trim().isNotEmpty ||
        slide.imageAltText.trim().isNotEmpty ||
        slide.imageAltText2.trim().isNotEmpty ||
        slide.imageCaption.trim().isNotEmpty ||
        slide.imageCaption2.trim().isNotEmpty;
    if (hasDescription) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.mediaMissingDescription,
        category: SlideQualityCategory.altText,
        severity: MarkdownValidationSeverity.informational,
        field: 'title',
        args: {'label': label},
      ),
    );
  }

  void _checkMissingMedia(
    Slide slide,
    int index,
    String? projectPath,
    List<SlideQualityIssue> issues,
  ) {
    // Bewust géén poort meer op projectPath. Een deck dat nog niet is
    // opgeslagen heeft er geen, en juist daar is de kans op een kapotte
    // verwijzing het grootst — dat was precies het geval waarin deze controle
    // zweeg. Zonder projectmap blijft resolveSlideAssetPath alleen absolute
    // paden oplossen; relatieve hebben dan nog geen betekenis en worden
    // overgeslagen.
    if (kIsWeb) return;

    void missingFile({
      required String path,
      required String field,
      required String label,
    }) {
      if (path.trim().isEmpty) return;
      // Een online bron heeft geen bestand op schijf dat kán ontbreken. Zonder
      // deze poort plakt resolveSlideAssetPath de URL als relatief pad achter de
      // projectmap ("<project>/https:/youtu.be/…"), vindt daar niets, en meldt
      // een YouTube/Vimeo/mp4-link als "bestand niet gevonden".
      if (VideoSource.looksLikeUrl(path)) return;

      SlideQualityIssue issue(SlideQualityIssueKind kind) => SlideQualityIssue(
        slideIndex: index,
        kind: kind,
        category: SlideQualityCategory.altText,
        severity: MarkdownValidationSeverity.warning,
        field: field,
        args: {'label': label, 'path': path},
      );

      final origin = classifyAssetPath(path, projectPath);
      final hasProject = projectPath != null && projectPath.trim().isNotEmpty;

      // Deck van schijf, pad daarbuiten: containment verbiedt ons hier op de
      // schijf te kijken, en dat hoeft ook niet. Dát het buiten de presentatie
      // ligt is op zichzelf het probleem — bestaat het toevallig wel, dan nog
      // ziet de ontvanger niets.
      if (origin == AssetOrigin.external && hasProject) {
        issues.add(issue(SlideQualityIssueKind.externalMediaFile));
        return;
      }

      final resolved = _resolveAssetPath(path, projectPath);
      if (resolved == null) return;
      if (!File(resolved).existsSync()) {
        // Ontbreken gaat vóór "ligt buiten de presentatie": opslaan maakt geen
        // kopie van een bestand dat er niet meer is.
        issues.add(issue(SlideQualityIssueKind.missingMediaFile));
        return;
      }
      if (origin == AssetOrigin.external) {
        issues.add(issue(SlideQualityIssueKind.externalMediaFile));
      }
    }

    // Een afbeelding in de vrije tekst kan net zo goed ontbreken of buiten de
    // presentatie liggen als eentje in een afbeeldingsveld, dus hij verdient
    // dezelfde melding. Buiten de switch, want elke slidesoort kan vrije tekst
    // dragen. Het veld is `customMarkdown` — dát wijst de plek aan waar de
    // gebruiker moet zijn; het pad in de melding zegt wélke afbeelding.
    for (final path in inlineImagePaths(slide.customMarkdown)) {
      missingFile(path: path, field: 'customMarkdown', label: 'Afbeelding');
    }

    switch (slide.type) {
      case SlideType.image:
      case SlideType.bulletsImage:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Afbeelding',
        );
      case SlideType.twoImages:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Eerste afbeelding',
        );
        missingFile(
          path: slide.imagePath2,
          field: 'imagePath2',
          label: 'Tweede afbeelding',
        );
      case SlideType.title:
      case SlideType.section:
      case SlideType.quote:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Achtergrondafbeelding',
        );
        if (slide.titleColumnLayout != TitleColumnLayout.none) {
          missingFile(
            path: slide.imagePath2,
            field: 'imagePath2',
            label: 'Rechter kolomafbeelding',
          );
        }
      case SlideType.video:
        missingFile(path: slide.videoPath, field: 'videoPath', label: 'Video');
      case SlideType.question:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Afbeelding',
        );
        // Bij een beeldparen-vraag zíjn de antwoorden afbeeldingen. Ontbreekt
        // er een, dan staat er tijdens het presenteren een lege tegel waar een
        // antwoord hoort — en dat merk je pas in de zaal.
        final spec = QuestionSpec.parse(slide.customMarkdown);
        if (spec.kind == QuestionKind.imagePair) {
          for (var i = 0; i < spec.answers.length; i++) {
            missingFile(
              path: spec.answers[i].image,
              field: 'customMarkdown',
              label: 'Afbeelding ${i + 1}',
            );
          }
        }
      case SlideType.bullets:
      // Menublok-afbeeldingen leven in de bullet-tekst, niet in [Slide.imagePath];
      // een ontbrekend-bestand-controle per blok is een latere verfijning.
      case SlideType.menu:
      case SlideType.twoBullets:
      case SlideType.table:
      case SlideType.freeMarkdown:
      case SlideType.code:
      case SlideType.chart:
      case SlideType.cockpit:
      case SlideType.timeline:
      case SlideType.scorecard:
      case SlideType.assets:
      case SlideType.discoveries:
      case SlideType.finding:
      case SlideType.findingsSummary:
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.controlStatus:
      case SlideType.signOff:
      case SlideType.matrix:
      case SlideType.canvas:
      case SlideType.tree:
      case SlideType.flow:
      case SlideType.phaseGate:
      case SlideType.gantt:
        break;
    }
  }
}

// Route through the shared containment guard so a crafted deck can't turn the
// "missing media" check into a file-existence oracle (existsSync) for paths
// outside the project via absolute or `../` references. Top-level (not a method)
// so it stays out of the SlideQualityAnalyzer class-size ratchet; same library,
// so the analyzer and its density extension still call it directly.
String? _resolveAssetPath(String path, String? projectPath) =>
    resolveSlideAssetPath(path, projectPath);

class _BulletText {
  final String text;
  final int level;

  const _BulletText({required this.text, required this.level});
}

/// A memoised fit-scale together with the font it was measured for, so a font
/// change invalidates the cached value without touching the [Expando] key.
class _FitMemo {
  final String font;
  final double scale;

  const _FitMemo(this.font, this.scale);
}

/// Gememoiseerde split-run-schaal per slide. Een aparte cache naast
/// [_fitScaleCache] omdat dit een ándere meting van dezelfde slide is: deze
/// reserveert de logostrook, net als de live layout. Eén cache delen zou de twee
/// waarden door elkaar halen, want slide en lettertype zijn voor beide gelijk.
/// Het thema hoort daarom wél bij de sleutel — het bepaalt de logostrook.
final Expando<_RunScaleMemo> _runScaleCache = Expando<_RunScaleMemo>(
  'splitRunMemberScale',
);

class _RunScaleMemo {
  final String font;
  final ThemeProfile theme;
  final double scale;

  const _RunScaleMemo(this.font, this.theme, this.scale);
}

/// Gememoiseerde per-slide issues plus alles waarvan de analyse afhangt, zodat
/// een gewijzigd thema, lettertype, projectpad of contrastdrempel de cache
/// laat missen. [theme] wordt op identiteit vergeleken (immutable model).
class _SlideIssuesMemo {
  final ThemeProfile theme;
  final String font;
  final String? projectPath;
  final double minContrastRatio;
  final int index;
  final List<SlideQualityIssue> issues;

  const _SlideIssuesMemo({
    required this.theme,
    required this.font,
    required this.projectPath,
    required this.minContrastRatio,
    required this.index,
    required this.issues,
  });

  _SlideIssuesMemo withIndex(int newIndex, List<SlideQualityIssue> reindexed) =>
      _SlideIssuesMemo(
        theme: theme,
        font: font,
        projectPath: projectPath,
        minContrastRatio: minContrastRatio,
        index: newIndex,
        issues: reindexed,
      );
}

/// Toetst elk voor-/achtergrondpaar dat een *thema* vastlegt, los van de
/// dia's die het deck draagt: een profiel met onleesbare kleuren is onleesbaar
/// nog voor er iets op staat. Top-level zodat de reeks niet tegen het
/// klasseplafond van [SlideQualityAnalyzer] telt — zie [_addSlidePairIssue].
void _checkThemeContrast(
  ThemeProfile theme,
  List<SlideQualityIssue> issues, {
  required double minContrastRatio,
}) {
  void addPairIssue({
    required String label,
    required String foreground,
    required String background,
    required bool largeText,
    String? field,
  }) {
    final ratio = hexContrastRatio(foreground, background);
    if (ratio == null) return;
    final aaThreshold = largeText
        ? math.min(kWcagAaLargeText, minContrastRatio)
        : minContrastRatio;
    if (ratio >= aaThreshold) return;

    final severity = !largeText && ratio < kWcagCriticalBodyText
        ? MarkdownValidationSeverity.error
        : MarkdownValidationSeverity.warning;

    issues.add(
      SlideQualityIssue(
        slideIndex: kDeckWideSlideIndex,
        kind: SlideQualityIssueKind.themeContrast,
        category: SlideQualityCategory.contrast,
        severity: severity,
        field: field,
        args: {
          'label': label,
          'ratio': ratio.toStringAsFixed(1),
          'threshold': aaThreshold.toStringAsFixed(1),
          'largeText': largeText.toString(),
        },
      ),
    );
  }

  addPairIssue(
    label: 'Thema bodytekst',
    foreground: theme.textColor,
    background: theme.slideBackgroundColor,
    largeText: false,
    field: 'textColor',
  );
  addPairIssue(
    label: 'Thema titel',
    foreground: theme.titleTextColor,
    background: theme.titleBackgroundColor,
    largeText: true,
    field: 'titleTextColor',
  );
  addPairIssue(
    label: 'Thema tabeltekst',
    foreground: theme.tableTextColor,
    background: theme.slideBackgroundColor,
    largeText: false,
    field: 'tableTextColor',
  );
  addPairIssue(
    label: 'Thema tabelkop',
    foreground: theme.tableHeaderTextColor,
    background: theme.tableHeaderBackgroundColor,
    largeText: true,
    field: 'tableHeaderTextColor',
  );
  addPairIssue(
    label: 'Thema code',
    foreground: theme.codeTextColor,
    background: theme.codeBackgroundColor,
    // Code op een slide staat op displayformaat (grote tekst), net als de
    // titel en de tabelkop hierboven: dus de WCAG-drempel voor grote tekst
    // (3.0). Code die zó dicht is dat het klein zou renderen, wordt al apart
    // gevangen door de density-check (kind codeDensityHigh).
    largeText: true,
    field: 'codeTextColor',
  );
  addPairIssue(
    label: 'Thema accent',
    foreground: theme.accentColor,
    background: theme.slideBackgroundColor,
    largeText: false,
    field: 'accentColor',
  );
  // Hieronder de drie paren die alléén op het documentvlak bestaan: de koppen
  // van een document, de tekst van de kop- en voetband om het blad, en het
  // accent zoals het óp die band landt. Zonder deze toetsen kon een stijl ze
  // onleesbaar zetten terwijl elke dia-kleur wél gemeten werd — en dan zwijgt
  // zowel het kwaliteitspaneel als de stijlinstelling.
  //
  // Alle drie kijken alleen naar een kleur die de auteur zélf zette. Laat hij
  // ze leeg, dan valt het documentvlak terug op `textColor`, `accentColor` en
  // `slideBackgroundColor` — precies de paren die 'Thema bodytekst' en 'Thema
  // accent' hierboven al meten, en op een even strenge of stríktere drempel.
  // Een tweede melding over datzelfde paar zou alleen ruis zijn in het paneel.
  if (theme.documentHeadingColor != null) {
    addPairIssue(
      label: 'Thema documentkop',
      foreground: theme.effectiveDocumentHeadingColor,
      background: theme.slideBackgroundColor,
      // Een documentkop staat op displayformaat: een h1 rendert op 27
      // beeldpunten, ruim boven de WCAG-grens voor grote tekst. Diepere
      // niveaus zakken naar de body-maat, maar dit ene veld is de kleur die
      // álle niveaus delen — een strengere drempel zou een leesbare h1
      // afkeuren om een h5 die je zelden ziet.
      largeText: true,
      field: 'documentHeadingColor',
    );
  }
  if (theme.documentBandTextColor != null ||
      theme.documentBandBackgroundColor != null) {
    addPairIssue(
      label: 'Thema documentband',
      foreground: theme.effectiveDocumentBandTextColor,
      background: theme.effectiveDocumentBandBackgroundColor,
      // De band zet kop-, voettekst en paginanummer op 12 beeldpunten (9 in
      // de compacte weergave): gewone tekst, dus de volle drempel.
      largeText: false,
      // Ook wanneer alleen de achtergrond is gezet landt de melding op de
      // tekstkleur — hetzelfde anker dat 'Thema bodytekst' kiest, en het veld
      // waar de auteur de leesbaarheid herstelt.
      field: 'documentBandTextColor',
    );
  }
  if (theme.documentBandBackgroundColor != null) {
    addPairIssue(
      // Het accent landt óók op de band, en niet als versiering: een link in de
      // kop- of voettekst krijgt hem als tekstkleur — in de app
      // (`document_page_chrome.dart`) en in de HTML-export (`.document a`)
      // allebei. Twee kleuren die op het papier prima staan kunnen op een
      // eigen bandachtergrond samenvallen, en dan is juist de link onleesbaar.
      label: 'Thema accent op de documentband',
      foreground: theme.accentColor,
      background: theme.effectiveDocumentBandBackgroundColor,
      // Een link in de band is bandtekst: dezelfde twaalf beeldpunten, dus
      // dezelfde volle drempel.
      largeText: false,
      // Anders dan de twee paren hierboven landt deze melding op de
      // achtergrond. Het accent is een gedeelde kleur die overal elders wél
      // deugt — wat aan dít paar te herstellen valt, is de band eronder.
      field: 'documentBandBackgroundColor',
    );
  }
}

/// Toetst een voorgrond/achtergrond-paar op contrast en meldt het als het onder
/// de (voor grote tekst versoepelde) drempel zakt. Top-level zodat de emitter
/// niet tegen het klasseplafond van [SlideQualityAnalyzer] telt.
void _addSlidePairIssue({
  required List<SlideQualityIssue> issues,
  required int slideIndex,
  required String label,
  required String foreground,
  required String background,
  required double minContrastRatio,
}) {
  final ratio = hexContrastRatio(foreground, background);
  if (ratio == null) return;
  final aaThreshold = math.min(kWcagAaLargeText, minContrastRatio);
  if (ratio >= aaThreshold) return;

  issues.add(
    SlideQualityIssue(
      slideIndex: slideIndex,
      kind: SlideQualityIssueKind.slideContrast,
      category: SlideQualityCategory.contrast,
      severity: MarkdownValidationSeverity.warning,
      args: {
        'label': label,
        'ratio': ratio.toStringAsFixed(1),
        'threshold': aaThreshold.toStringAsFixed(1),
      },
    ),
  );
}

/// De ondertitel van een titel- of tussentiteldia staat op verlaagde dekking
/// ([kTitleSubtitleAlpha]) — een lichtere versie van de titelkleur, en dus met
/// stelliger het zwakste contrast van de twee. De volle titeltekst wordt al
/// getoetst (dekbreed voor de titeldia, per dia voor de tussentitel); zonder
/// deze toets glipt juist die lichtere ondertekst erdoor: donkerblauwe
/// achtergrond met een lichterblauwe ondertitel die voor mensen niet te lezen
/// is. De kleur volgt de render: een `titleTextColorOverride` wint van het
/// thema. Alleen als er een ondertitel staat. Top-level zodat de emitter niet
/// tegen het klasseplafond van [SlideQualityAnalyzer] telt.
void _addSubtitleContrastIssue({
  required List<SlideQualityIssue> issues,
  required int slideIndex,
  required String label,
  required Slide slide,
  required ThemeProfile theme,
  required String background,
  required double minContrastRatio,
}) {
  if (slide.subtitle.trim().isEmpty) return;
  final foreground = slide.titleTextColorOverride.isNotEmpty
      ? slide.titleTextColorOverride
      : theme.titleTextColor;
  final ratio = blendedHexContrastRatio(
    foreground,
    background,
    foregroundAlpha: kTitleSubtitleAlpha,
  );
  if (ratio == null) return;
  final aaThreshold = math.min(kWcagAaLargeText, minContrastRatio);
  if (ratio >= aaThreshold) return;

  issues.add(
    SlideQualityIssue(
      slideIndex: slideIndex,
      kind: SlideQualityIssueKind.slideContrast,
      category: SlideQualityCategory.contrast,
      severity: MarkdownValidationSeverity.warning,
      args: {
        'label': label,
        'ratio': ratio.toStringAsFixed(1),
        'threshold': aaThreshold.toStringAsFixed(1),
      },
    ),
  );
}
