import '../utils/lru_cache.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../utils/markdown_paste_cleanup.dart';
import 'markdown_body_blocks.dart';
import 'slide_layout_metrics.dart';

/// Target fill when splitting pages during layout planning.
const kRichTextVerticalFill = 0.98;

class RichTextLayoutPlan {
  final double scale;
  final int pageCount;
  final List<String> pageMarkdown;

  const RichTextLayoutPlan({
    required this.scale,
    required this.pageCount,
    required this.pageMarkdown,
  });

  String markdownForPage(int pageIndex) {
    if (pageMarkdown.isEmpty) return '';
    final i = pageIndex.clamp(0, pageMarkdown.length - 1);
    return pageMarkdown[i];
  }
}

/// Vertical space to keep clear of the slide footer overlay.
double footerSafeInset({
  required double w,
  required Slide slide,
  required ThemeProfile profile,
}) {
  if (!slide.showFooter) return 0;
  if (slide.type.isHeading) {
    return 0;
  }
  final footerText = profile.footerText.trim();
  final showPages = profile.footerShowPageNumbers;
  if (footerText.isEmpty && !showPages) return 0;
  // Match [_FooterOverlay]: bottom offset + one line of footer text.
  return w * 0.02 + w * 0.0145 * 1.35;
}

/// Bottom padding for bullets / rich-text slides.
/// When a footer overlay is active its band ([footerSafeInset]) plus a small
/// cushion is reserved here, so the text column stops above the footer instead
/// of running on behind it; a bottom logo reserve wins when it is larger.
double bulletsSlideBottomInset({
  required double w,
  required Slide slide,
  required ThemeProfile profile,
  required double defaultBottomPad,
  double safeBottom = 0,
}) {
  final footer = footerSafeInset(w: w, slide: slide, profile: profile);
  if (footer <= 0) {
    return safeBottom > defaultBottomPad ? safeBottom : defaultBottomPad;
  }
  final reserved = footer + w * 0.004;
  return safeBottom > reserved ? safeBottom : reserved;
}

double _richTextBudget(double availH, double footerInset) =>
    richTextLayoutBudget(availH, footerInset);

/// Vertical budget for rich-text layout after optional footer clearance.
double richTextLayoutBudget(double availH, double footerInset) =>
    (availH - footerInset).clamp(1.0, availH);

double richTextFitTargetHeight(double budget, double refW) =>
    (budget - refW * kRichTextRenderSlopFraction).clamp(1.0, budget);

double _headerHeight({
  required double scale,
  required double contentW,
  required bool hasTitle,
  required String title,
  required String subtitle,
  required double titleSize,
  required double subtitleSize,
  required double spacing,
  required String font,
  required bool hasBody,
}) {
  var h = 0.0;
  if (hasTitle) {
    h += measureTextHeight(
      title,
      titleSize * scale,
      contentW,
      bold: true,
      lineHeight: kRichTextBodyLineHeight,
      fontFamily: font,
    );
  }
  if (subtitle.isNotEmpty) {
    h += spacing * scale * 0.4;
    h += measureTextHeight(
      subtitle,
      subtitleSize * scale,
      contentW,
      lineHeight: kRichTextBodyLineHeight,
      fontFamily: font,
    );
  }
  if ((hasTitle || subtitle.isNotEmpty) && hasBody) {
    h += spacing * scale;
  }
  return h;
}

/// Verdeel [blocks] over pagina's: elk blok gaat bij de huidige pagina tot de
/// gemeten paginahoogte [packTarget] zou overschrijden, dan begint een nieuwe.
List<List<MarkdownBodyBlock>> _packBlocksIntoPages({
  required List<MarkdownBodyBlock> blocks,
  required double scale,
  required double packTarget,
  required bool titleOnFirstPageOnly,
  required double Function({
    required double scale,
    required bool includeHeader,
    required List<MarkdownBodyBlock> slice,
  })
  measurePage,
}) {
  final pages = <List<MarkdownBodyBlock>>[];
  var current = <MarkdownBodyBlock>[];
  var pageIndex = 0;

  for (final block in blocks) {
    final trial = [...current, block];
    final includeHeader = !titleOnFirstPageOnly || pageIndex == 0;
    if (current.isNotEmpty &&
        measurePage(scale: scale, includeHeader: includeHeader, slice: trial) >
            packTarget) {
      pages.add(current);
      current = [block];
      pageIndex++;
    } else {
      current = trial;
    }
  }
  if (current.isNotEmpty) pages.add(current);
  if (pages.isEmpty) pages.add(blocks);
  return pages;
}

RichTextLayoutPlan planRichTextLayout({
  required String markdown,
  required double availW,
  required double availH,
  required double refW,
  required bool hasTitle,
  required String title,
  required String subtitle,
  required double titleSize,
  required double subtitleSize,
  required double spacing,
  required double bodySize,
  required String font,
  required double footerInset,
  double maxScale = kSplitBulletsMaxScale,
  double minScale = kTextDensityCriticalScale,
  bool titleOnFirstPageOnly = true,
}) {
  final blocks = parseMarkdownBodyBlocks(markdown);
  final hasBody = blocks.any((b) => b.markdown.trim().isNotEmpty);
  final budget = _richTextBudget(availH, footerInset);
  // Pagina's indelen tegen dezelfde render-marge als de fit-zoekers: een
  // pagina die tot op de laatste pixel van het budget vol zit heeft geen
  // ruimte voor meet-/renderafronding, en de onderste regel wordt dan half
  // afgeknipt op de logo-/footergrens.
  final packTarget = richTextFitTargetHeight(budget, refW);

  double measureBody(double scale, List<MarkdownBodyBlock> slice) =>
      measureMarkdownBlocksHeight(
        blocks: slice,
        scale: scale,
        contentW: availW,
        refW: refW,
        bodySize: bodySize,
        font: font,
      );

  double measurePage({
    required double scale,
    required bool includeHeader,
    required List<MarkdownBodyBlock> slice,
  }) {
    var h = 0.0;
    if (includeHeader) {
      h += _headerHeight(
        scale: scale,
        contentW: availW,
        hasTitle: hasTitle,
        title: title,
        subtitle: subtitle,
        titleSize: titleSize,
        subtitleSize: subtitleSize,
        spacing: spacing,
        font: font,
        hasBody: slice.any((b) => b.markdown.trim().isNotEmpty),
      );
    }
    h += measureBody(scale, slice);
    return h;
  }

  if (!hasBody && !hasTitle && subtitle.isEmpty) {
    return const RichTextLayoutPlan(scale: 1, pageCount: 1, pageMarkdown: ['']);
  }

  // Prefer multiple pages at a readable size over squeezing everything onto
  // one page at a tiny scale.
  const paginationScale = kTextDensityWarningScale;

  var scale = richTextFitScale(
    availH: budget,
    contentW: availW,
    refW: refW,
    hasTitle: hasTitle,
    title: title,
    subtitle: subtitle,
    titleSize: titleSize,
    subtitleSize: subtitleSize,
    spacing: spacing,
    markdown: markdown,
    bodySize: bodySize,
    font: font,
    minScale: paginationScale,
    maxScale: maxScale,
  );
  scale = tightenVerticalFitScale(
    scale: scale,
    availH: budget,
    measure: (s) => measurePage(scale: s, includeHeader: true, slice: blocks),
    minScale: paginationScale,
    fillRatio: kRichTextVerticalFill,
  );

  if (measurePage(scale: scale, includeHeader: true, slice: blocks) <=
      packTarget) {
    return RichTextLayoutPlan(
      scale: scale,
      pageCount: 1,
      pageMarkdown: [markdown],
    );
  }

  scale = paginationScale;
  final pages = _packBlocksIntoPages(
    blocks: blocks,
    scale: scale,
    packTarget: packTarget,
    titleOnFirstPageOnly: titleOnFirstPageOnly,
    measurePage: measurePage,
  );

  double tallestPageHeight(double s) {
    var maxH = 0.0;
    for (var i = 0; i < pages.length; i++) {
      final includeHeader = !titleOnFirstPageOnly || i == 0;
      final h = measurePage(
        scale: s,
        includeHeader: includeHeader,
        slice: pages[i],
      );
      if (h > maxH) maxH = h;
    }
    return maxH;
  }

  // Grow each page toward the largest scale that still fits [budget].
  scale = maxVerticalFitScale(
    availH: budget,
    refW: refW,
    measure: tallestPageHeight,
    minScale: paginationScale,
    maxScale: maxScale,
  );

  // Lege regels zijn zelf blokken, dus '\n' reconstrueert de oorspronkelijke
  // regelstructuur; '\n\n' zou per alinea-overgang twee extra witregels
  // toevoegen die de paginameting nooit heeft gezien (en de onderste regel
  // voorbij de logo-/footergrens duwen).
  return RichTextLayoutPlan(
    scale: scale,
    pageCount: pages.length,
    pageMarkdown: pages
        .map((p) => p.map((b) => b.markdown).join('\n'))
        .toList(),
  );
}

/// Gemeten plannen, op de dia en de geometrie waarvoor ze gemaakt zijn.
///
/// `planRichTextLayout` meet het hele document telkens opnieuw: de
/// pas-schaal bisecteert, het inpakken meet een groeiende reeks blokken, en de
/// verticale pas-schaal meet elk blok van elke pagina per iteratie. Alles komt
/// uit op een verse `TextPainter`. Gemeten liep dat op tot ~5.700 metingen en
/// ~114 ms voor één opbouw van een dia met vijfentwintig alinea's — en de
/// preview bouwt op bij elke aanslag, twee keer zelfs (paginatelling en inhoud
/// vragen hetzelfde plan op een andere referentiebreedte).
///
/// De vier andere previews gebruikten `memoizedRenderLayout` al; de rijke tekst
/// was de duurste van de vijf en als enige niet aangesloten. Sleutel op de dia
/// (onveranderlijk, dus identiteit is een geldige wijzigingsstempel) plus alles
/// wat de uitkomst verder bepaalt.
final LruCache<
  (Slide, ThemeProfile, String, double, double, double, bool),
  RichTextLayoutPlan
>
_richTextPlanCache = LruCache(256);

RichTextLayoutPlan planRichTextForSlide({
  required Slide slide,
  required ThemeProfile profile,
  required double w,
  required double availW,
  required double availH,
  required String font,
  bool splitWithImage = false,
}) {
  final key = (slide, profile, font, w, availW, availH, splitWithImage);
  final cached = _richTextPlanCache[key];
  if (cached != null) return cached;
  final plan = _planRichTextForSlide(
    slide: slide,
    profile: profile,
    w: w,
    availW: availW,
    availH: availH,
    font: font,
    splitWithImage: splitWithImage,
  );
  _richTextPlanCache[key] = plan;
  return plan;
}

RichTextLayoutPlan _planRichTextForSlide({
  required Slide slide,
  required ThemeProfile profile,
  required double w,
  required double availW,
  required double availH,
  required String font,
  bool splitWithImage = false,
}) {
  final pad = splitWithImage ? w * 0.038 : w * 0.07;
  final vPad = splitWithImage ? w * 0.042 : w * 0.05;
  final titleSize = w * 0.042;
  final subtitleSize = w * 0.030;
  final spacing = splitWithImage ? vPad * 0.32 : pad * 0.5;
  // Free-markdown houdt zijn eigen, iets kleinere bodymaat (w*0,024) en kapt
  // op 1,0: een korte dia blijft op natuurlijke grootte staan i.p.v. te
  // worden opgerekt om de slide te vullen, en alleen een body die echt
  // overloopt pagineert (#1409). Bullets mogen wél meegroeien.
  final isFreeMarkdown = slide.type == SlideType.freeMarkdown;
  final bodySize = isFreeMarkdown
      ? w * 0.024
      : (splitWithImage ? w * 0.031 : w * 0.026);
  // [availH] komt bij elke aanroeper uit [bulletsSlideBottomInset]-geometrie,
  // die de footerband al reserveert — hier niet nogmaals aftrekken.

  return planRichTextLayout(
    markdown: normalizeRichTextMarkdown(slide.customMarkdown),
    availW: availW,
    availH: availH,
    refW: w,
    hasTitle: slide.title.isNotEmpty,
    title: slide.title,
    subtitle: slide.subtitle,
    titleSize: titleSize,
    subtitleSize: subtitleSize,
    spacing: spacing,
    bodySize: bodySize,
    font: font,
    footerInset: 0,
    maxScale: isFreeMarkdown
        ? 1.0
        : bulletScaleCap(
            w,
            bodySize,
            splitWithImage ? kBulletsMaxScale : kSplitBulletsMaxScale,
          ),
  );
}

bool slideUsesRichText(Slide slide) =>
    slide.type == SlideType.freeMarkdown ||
    (slide.listStyle == ListStyle.richText &&
        (slide.type == SlideType.bullets ||
            slide.type == SlideType.bulletsImage));

// Logo placement insets from the slide edge, as a fraction of the logo's own
// size — the single source of truth shared by the logo overlay (which positions
// it) and the safe-inset reserve below (which keeps text off it).
const double kLogoHorizontalInsetFraction = 0.28;
const double kLogoTopInsetFraction = 0.42;
const double kLogoBottomInsetFraction = 0.12;

/// Vertical space a shown logo reserves from its slide edge.
///
/// When [corner] is false (text slides: bullets, freeMarkdown), the reserve is
/// the logo's edge inset plus a small gap — the content extends to just above
/// the logo's bottom edge, gaining the logo's own height back compared to the
/// old full-height strip. The logo sits below the text, not overlapping.
///
/// When [corner] is true (panel slides: cockpit, chart, table, ...), the reserve
/// is 0: the panel extends to full height and the logo sits on top in the
/// corner (#1932). For opaque panels the logo covers only the corner; for a
/// circular gauge (cockpit) that corner is empty anyway.
double logoSafeReserve(double w, ThemeProfile profile, {bool corner = false}) {
  if (profile.logoPath?.isEmpty ?? true) return 0;
  if (corner) return 0;
  final size = w * (profile.logoSize / 1280);
  final edgeInset = profile.logoPosition.startsWith('top')
      ? kLogoTopInsetFraction
      : kLogoBottomInsetFraction;
  // #1932: reduced from size*(1+edgeInset) to size*edgeInset — the content
  // now clears the logo's edge inset + gap, not the full logo height.
  return size * edgeInset + w * 0.014;
}

/// Waar de logostrook aan de boven- en onderkant ruimte opeist, als `(boven,
/// onder)` — één van beide is altijd nul, want een logo staat maar op één rand.
///
/// De enige plek waar die regel staat. De previews gieten het resultaat in
/// `EdgeInsets` om tekst weg te duwen; de split-run-meting telt boven en onder
/// bij elkaar op om te weten hoeveel hoogte er overblijft. Zouden die twee elk
/// hun eigen versie hebben, dan kan de kwaliteitscontrole een grootte melden die
/// niet is wat je op het scherm ziet.
///
/// [splitText] voor de smalle tekstkolom van een split-slide: die staat naast
/// het beeld, dus een logo rechts zit hem niet in de weg en reserveert niets.
(double, double) logoSafeReserveEdges(
  double w,
  ThemeProfile profile, {
  bool splitText = false,
  bool corner = false,
}) {
  if (profile.logoPath?.isEmpty ?? true) return (0, 0);
  if (splitText && profile.logoPosition.endsWith('right')) return (0, 0);
  final reserved = logoSafeReserve(w, profile, corner: corner);
  return profile.logoPosition.startsWith('top') ? (reserved, 0) : (0, reserved);
}

/// The rich-text/bullets body height for [slide] at 16:9 width [w], after the
/// top/bottom padding the preview applies — including the logo-safe reserve and
/// footer clearance. Shared by the rendered pagination and the presenter's
/// page-count/navigation math so they never disagree on how many pages a slide
/// has (a disagreement would, e.g., render a "1 / 2" badge that navigation can't
/// page past).
double richTextBodyAvailH(
  double w,
  Slide slide,
  ThemeProfile profile, {
  required bool splitWithImage,
}) {
  final vPad = splitWithImage ? w * 0.042 : w * 0.05;
  final reserve = slide.showLogo ? logoSafeReserve(w, profile) : 0.0;
  // A split (text+image) layout puts the text column beside a right-hand image,
  // so a right-side logo sits over the image and needs no text reserve (mirrors
  // the preview's split-layout safe insets).
  final effReserve = (splitWithImage && profile.logoPosition.endsWith('right'))
      ? 0.0
      : reserve;
  final isTop = profile.logoPosition.startsWith('top');
  final topPad = vPad + (isTop ? effReserve : 0.0);
  final bottomPad = bulletsSlideBottomInset(
    w: w,
    slide: slide,
    profile: profile,
    defaultBottomPad: vPad,
    safeBottom: isTop ? 0.0 : effReserve,
  );
  return (w * 9 / 16 - topPad - bottomPad).clamp(1.0, w * 9 / 16);
}

/// Page count for a rich-text slide at reference slide dimensions.
int richTextPageCountForSlide({
  required Slide slide,
  required ThemeProfile profile,
  bool splitWithImage = false,
}) {
  if (!slideUsesRichText(slide)) return 1;
  const w = kReferenceSlideWidth;
  final hPad = splitWithImage ? w * 0.038 : w * 0.07;
  final imgFraction = splitWithImage
      ? ((slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40).clamp(
          0.1,
          0.70,
        ))
      : 0.0;
  final contentW = splitWithImage
      ? (w - imgFraction * w - hPad * 2).clamp(w * 0.12, w)
      : w - hPad * 2;
  final contentH = richTextBodyAvailH(
    w,
    slide,
    profile,
    splitWithImage: splitWithImage,
  );
  return planRichTextForSlide(
    slide: slide,
    profile: profile,
    w: w,
    availW: contentW,
    availH: contentH,
    font: profile.fontFamily,
    splitWithImage: splitWithImage,
  ).pageCount;
}

/// Expand a deck's slides for surfaces that *enumerate* slides instead of
/// paging through them: every page of a paginated rich-text body becomes its
/// own full-size slide, tagged with [Slide.renderPage].
///
/// The counterpart of `expandFindingsForRender`, and needed for the same
/// reason. The editor preview and the presenter both let you step through the
/// pages of one slide, so they see the whole body and pass a page index. The
/// export does not: it rasterised each slide once and page 2 and beyond were
/// simply never drawn. The deck itself is untouched — this only changes what a
/// render enumerates.
///
/// Counting happens at [kReferenceSlideWidth], the same geometry the rasteriser
/// lays out at, so the export splits exactly where the preview does.
List<Slide> expandRichTextForRender(List<Slide> slides, ThemeProfile profile) {
  final out = <Slide>[];
  for (final slide in slides) {
    // Alleen de typen die een pagina ook echt tonen. Sinds #1409 pagineert
    // free-markdown mee via dezelfde rich-text-machine, dus het hoort hier in
    // de uitklap thuis — anders rasteriseert de export alleen pagina 1.
    if (slide.type != SlideType.bullets &&
        slide.type != SlideType.bulletsImage &&
        slide.type != SlideType.freeMarkdown) {
      out.add(slide);
      continue;
    }
    final pages = richTextPageCountForSlide(
      slide: slide,
      profile: profile,
      splitWithImage: slide.type.splitWithImage,
    );
    if (pages <= 1) {
      out.add(slide);
      continue;
    }
    for (var page = 0; page < pages; page++) {
      // Every copy keeps the whole body and the same id — the id is how a live
      // edit during a presentation finds its way back to the deck slide, and
      // splitting the markdown here would break the shared font scale.
      out.add(page == 0 ? slide : slide.copyWith(renderPage: page));
    }
  }
  return out;
}
