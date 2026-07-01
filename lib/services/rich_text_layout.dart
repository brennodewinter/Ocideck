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
/// When a footer overlay is active the footer band is reserved in layout
/// ([footerSafeInset]); only a minimal cushion is applied here so no empty
/// strip appears under the text column.
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
  final footerCushion = w * 0.004;
  return safeBottom > footerCushion ? safeBottom : footerCushion;
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

  if (measurePage(scale: scale, includeHeader: true, slice: blocks) <= budget) {
    return RichTextLayoutPlan(
      scale: scale,
      pageCount: 1,
      pageMarkdown: [markdown],
    );
  }

  scale = paginationScale;
  final pages = <List<MarkdownBodyBlock>>[];
  var current = <MarkdownBodyBlock>[];
  var pageIndex = 0;

  for (final block in blocks) {
    final trial = [...current, block];
    final includeHeader = !titleOnFirstPageOnly || pageIndex == 0;
    if (current.isNotEmpty &&
        measurePage(scale: scale, includeHeader: includeHeader, slice: trial) >
            budget) {
      pages.add(current);
      current = [block];
      pageIndex++;
    } else {
      current = trial;
    }
  }
  if (current.isNotEmpty) pages.add(current);
  if (pages.isEmpty) pages.add(blocks);

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

  return RichTextLayoutPlan(
    scale: scale,
    pageCount: pages.length,
    pageMarkdown: pages
        .map((p) => p.map((b) => b.markdown).join('\n\n'))
        .toList(),
  );
}

RichTextLayoutPlan planRichTextForSlide({
  required Slide slide,
  required ThemeProfile profile,
  required double w,
  required double availW,
  required double availH,
  required String font,
  bool splitWithImage = false,
  bool footerReservedExternally = false,
}) {
  final pad = splitWithImage ? w * 0.038 : w * 0.07;
  final vPad = splitWithImage ? w * 0.042 : w * 0.05;
  final titleSize = w * 0.042;
  final subtitleSize = w * 0.030;
  final spacing = splitWithImage ? vPad * 0.32 : pad * 0.5;
  final bodySize = splitWithImage ? w * 0.031 : w * 0.026;
  final footer = footerReservedExternally
      ? 0.0
      : footerSafeInset(w: w, slide: slide, profile: profile);

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
    footerInset: footer,
    maxScale: bulletScaleCap(
      w,
      bodySize,
      splitWithImage ? kBulletsMaxScale : kSplitBulletsMaxScale,
    ),
  );
}

bool slideUsesRichText(Slide slide) =>
    slide.listStyle == ListStyle.richText &&
    (slide.type == SlideType.bullets ||
        slide.type == SlideType.bulletsImage ||
        slide.type == SlideType.freeMarkdown);

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
  final topPad = splitWithImage ? w * 0.042 : w * 0.05;
  final bottomPad = bulletsSlideBottomInset(
    w: w,
    slide: slide,
    profile: profile,
    defaultBottomPad: topPad,
  );
  final contentH = w * 9 / 16 - topPad - bottomPad;
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
