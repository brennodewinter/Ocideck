import 'dart:math' as math;

import '../models/slide.dart';
import '../utils/lru_cache.dart';
import 'markdown_body_blocks.dart' as md_body;
import 'text_measurement.dart';

export 'text_measurement.dart' show measureTextHeight, measureTextWidth;

/// Caches a slide preview's fully-resolved layout result (a fit-scale, or a
/// record of scale + column geometry), keyed by the slide's identity and the
/// exact geometry it was laid out at. A preview recomputes this fit through
/// several TextPainter layouts (a few milliseconds) on every rebuild, and
/// editing one slide rebuilds every visible thumbnail in the rail even though
/// their slides never changed — same object identity. The key is
/// (slide, font, width, availW, availH); a changed slide is a new object (never
/// a stale hit) and a resize misses on the geometry. Capped with FIFO eviction
/// so a long session can't grow it without bound (mirrors the image
/// average-colour cache).
///
/// A given slide is rendered by exactly one preview type, so each key always
/// maps to the same value type — the `as T` cast on a hit is sound.
///
/// LRU rather than insertion-order eviction so the on-screen working set (the
/// thumbnails the user is actually looking at, re-read every frame) stays warm
/// even once a long session has cycled more than the cache's capacity of
/// distinct slide/geometry combinations through it.
final LruCache<(Slide, String, double, double, double), Object>
_renderLayoutCache = LruCache(512);

T memoizedRenderLayout<T extends Object>({
  required Slide slide,
  required String font,
  required double width,
  required double availW,
  required double availH,
  required T Function() compute,
}) {
  final key = (slide, font, width, availW, availH);
  final cached = _renderLayoutCache[key];
  if (cached != null) return cached as T;
  final value = compute();
  _renderLayoutCache[key] = value;
  return value;
}

/// Reference slide width (960pt) used for consistent quality metrics across
/// deck sizes — matches the PowerPoint 16:9 canvas the previews emulate.
const double kReferenceSlideWidth = 960.0;

const double kBulletsMaxScale = 3.2;
const double kSplitBulletsMaxScale = 4.35;

/// Hard ceiling for rendered bullet text as a fraction of slide width.
const double kBulletMaxFontFraction = 0.0335;

const double kBulletLineHeight = 1.16;

/// Line height for rich-text body paragraphs (preview + measurement).
const double kRichTextBodyLineHeight = 1.2;

/// Fraction of slide width kept below measured height (TextPainter slop).
const double kRichTextRenderSlopFraction = 0.008;

/// Text-density warning when auto-fit shrinks below this scale factor.
const double kTextDensityWarningScale = 0.70;

/// Matches the minimum scale passed to [bulletsFitScale] in previews.
const double kTextDensityCriticalScale = 0.20;

/// The largest auto-fit scale that keeps bullets at or under
/// [kBulletMaxFontFraction], given the layout's own [layoutMax] growth bound.
double bulletScaleCap(double w, double bulletSize, double layoutMax) =>
    math.min(layoutMax, kBulletMaxFontFraction * w / bulletSize);

String bulletListMarker(List<String> items, int index, ListStyle style) {
  int levelOf(String item) {
    var level = 0;
    while (level < item.length && item[level] == '\t') {
      level++;
    }
    return level;
  }

  final level = levelOf(items[index]);
  if (style == ListStyle.bullets) return _bulletMarkerForLevel(level);
  if (style == ListStyle.checklist) {
    return checklistItemChecked(items[index]) ? '☑' : '☐';
  }
  if (style == ListStyle.richText) return '•';
  var number = 0;
  for (var i = 0; i <= index; i++) {
    final itemLevel = levelOf(items[i]);
    if (itemLevel == level) number++;
    if (itemLevel < level) number = 0;
  }
  return '$number.';
}

String _bulletMarkerForLevel(int level) {
  const markers = ['•', '◦', '▪', '▫', '–'];
  return markers[level.clamp(0, markers.length - 1)];
}

double bulletLevelScale(int level) {
  if (level <= 0) return 1.0;
  if (level == 1) return 0.86;
  if (level == 2) return 0.80;
  return 0.76;
}

/// Largest scale in [minScale, maxScale] for which the bullet block fits
/// [availH] at the full column width.
double bulletsFitScale({
  required double availW,
  required double availH,
  required bool hasTitle,
  required String title,
  required List<String> bullets,
  required double titleSize,
  required double bulletSize,
  required double spacing,
  required double bulletGap,
  required String font,
  String subtitle = '',
  double subtitleSize = 0,
  double minScale = kTextDensityCriticalScale,
  double maxScale = 1.0,
  ListStyle listStyle = ListStyle.bullets,
}) {
  if (availW <= 0 || !availH.isFinite || availH <= 0) return 1.0;
  final budget = availH * 0.98;
  double measure(double scale) => bulletsBlockHeight(
    scale: scale,
    availW: availW,
    listStyle: listStyle,
    hasTitle: hasTitle,
    title: title,
    bullets: bullets,
    titleSize: titleSize,
    bulletSize: bulletSize,
    spacing: spacing,
    bulletGap: bulletGap,
    font: font,
    subtitle: subtitle,
    subtitleSize: subtitleSize,
  );

  if (measure(maxScale) <= budget) return maxScale;

  double lo, hi;
  if (maxScale > 1.0 && measure(1.0) <= budget) {
    lo = 1.0;
    hi = maxScale;
  } else {
    lo = minScale;
    hi = maxScale > 1.0 ? 1.0 : maxScale;
  }
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (measure(mid) <= budget) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

double bulletsBlockHeight({
  required double scale,
  required double availW,
  required bool hasTitle,
  required String title,
  required List<String> bullets,
  required double titleSize,
  required double bulletSize,
  required double spacing,
  required double bulletGap,
  required String font,
  String subtitle = '',
  double subtitleSize = 0,
  ListStyle listStyle = ListStyle.bullets,
}) {
  var height = 0.0;
  if (hasTitle) {
    height += measureTextHeight(
      title,
      titleSize * scale,
      availW,
      bold: true,
      fontFamily: font,
    );
  }
  if (subtitle.isNotEmpty) {
    height += spacing * scale * 0.4;
    height += measureTextHeight(
      subtitle,
      subtitleSize * scale,
      availW,
      bold: true,
      fontFamily: font,
    );
  }
  if ((hasTitle || subtitle.isNotEmpty) && bullets.isNotEmpty) {
    height += spacing * scale;
  }
  for (var i = 0; i < bullets.length; i++) {
    final b = bullets[i];
    final level = bulletLevel(b);
    final text = listStyle == ListStyle.checklist
        ? checklistItemText(b)
        : b.substring(level);
    final fontSize = bulletSize * bulletLevelScale(level) * scale;
    final indent = level * bulletSize * 1.05 * scale;
    final marker = '${bulletListMarker(bullets, i, listStyle)} ';
    final markerW = measureTextWidth(
      marker,
      fontSize,
      bold: true,
      fontFamily: font,
    );
    final wrapW = (availW - indent - markerW).clamp(1.0, availW);
    final textH = measureTextHeight(
      text,
      fontSize,
      wrapW,
      lineHeight: kBulletLineHeight,
      fontFamily: font,
    );
    final markerH = measureTextHeight(
      marker,
      fontSize,
      double.infinity,
      fontFamily: font,
    );
    height += bulletGap * scale * 2 + (textH > markerH ? textH : markerH);
  }
  return height;
}

/// Table cell font size fraction used in [table_preview.dart].
double tableCellFontSize(
  double w, {
  required int rowCount,
  required int colCount,
}) {
  final density = (rowCount + colCount).clamp(2, 24);
  return (w * 0.025 * (10 / (density + 6))).clamp(w * 0.010, w * 0.021);
}

/// Minimum table cell font fraction (lower clamp bound in previews).
double tableCellFontMinimum(double w) => w * 0.010;

/// Per-column flex weights: each column's longest cell length (trimmed),
/// clamped so a single paragraph-length outlier can't starve its neighbours.
/// Shared by the table preview's column sizing and the fit measurement below so
/// both reason about the same geometry.
List<double> tableColumnFlexWeights(List<List<String>> rows, int colCount) {
  return <double>[
    for (var c = 0; c < colCount; c++)
      rows
          .map((r) => c < r.length ? r[c].trim().length : 0)
          .fold<int>(1, (longest, len) => len > longest ? len : longest)
          .clamp(1, 80)
          .toDouble(),
  ];
}

/// Rendered height of the table body at [cellSize], laid out at [tableWidth]
/// with columns proportioned by [tableColumnFlexWeights]. The per-cell padding
/// mirrors table_preview.dart (h: cellSize*0.55, v: cellSize*0.36, line height
/// 1.25) so the measured height matches what is drawn.
double tableBlockHeight({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double cellSize,
  required String font,
}) {
  if (rows.isEmpty || colCount <= 0) return 0;
  final weights = tableColumnFlexWeights(rows, colCount);
  final sum = weights.fold<double>(0, (a, b) => a + b);
  final colW = <double>[for (final wgt in weights) tableWidth * wgt / sum];
  final hPad = cellSize * 0.55;
  final vPad = cellSize * 0.36;
  var height = 0.0;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final header = i == 0;
    var rowH = 0.0;
    for (var c = 0; c < colCount; c++) {
      final text = c < row.length ? row[c] : '';
      final innerW = math.max(1.0, colW[c] - hPad * 2);
      final h = measureTextHeight(
        text.isEmpty ? ' ' : text,
        cellSize,
        innerW,
        lineHeight: 1.25,
        bold: header,
        fontFamily: font,
      );
      if (h > rowH) rowH = h;
    }
    height += rowH + vPad * 2;
  }
  return height;
}

/// Largest cell font in [minCellSize, baseCellSize] whose table body fits
/// [availH] at [tableWidth]. A text-heavy table shrinks its font so it fills
/// the slide's full width, instead of being scaled down — and thereby narrowed
/// — uniformly by the preview's FittedBox.
double tableFitCellSize({
  required List<List<String>> rows,
  required int colCount,
  required double tableWidth,
  required double availH,
  required double baseCellSize,
  required double minCellSize,
  required String font,
  double fillRatio = 0.98,
}) {
  if (rows.isEmpty || colCount <= 0 || availH <= 0) return baseCellSize;
  double measure(double size) => tableBlockHeight(
    rows: rows,
    colCount: colCount,
    tableWidth: tableWidth,
    cellSize: size,
    font: font,
  );
  var size = baseCellSize;
  // Shrinking the font also narrows each cell's text, so a row's height drops
  // a little faster than linearly; the height-ratio step converges in a few
  // passes. One measure() per iteration (mirrors tightenVerticalFitScale).
  while (size > minCellSize + 0.05) {
    final h = measure(size);
    if (h <= availH * fillRatio) break;
    final next = (size * availH / h * fillRatio).clamp(minCellSize, size);
    if ((size - next).abs() < 0.05) {
      size = next;
      break;
    }
    size = next;
  }
  return size.clamp(minCellSize, baseCellSize);
}

/// Layout metrics for a standard bullets slide at [kReferenceSlideWidth].
double bulletsSlideFitScale({
  required Slide slide,
  required String font,
  bool includeChecklistProgress = true,
}) {
  final w = kReferenceSlideWidth;
  final pad = w * 0.07;
  final vPad = w * 0.05;
  final titleSize = w * 0.042;
  final subtitleSize = w * 0.030;
  final bulletSize = w * 0.026;
  final spacing = pad * 0.5;
  final bulletGap = w * 0.006;
  final bullets = slide.bullets.where((b) => b.trimLeft().isNotEmpty).toList();
  final showProgress =
      includeChecklistProgress &&
      slide.listStyle == ListStyle.checklist &&
      slide.showChecklistProgress &&
      bullets.isNotEmpty;

  final slideHeight = w * 9 / 16;
  final availW = (w - pad * 2).clamp(w * 0.12, w);
  final progressGap = w * 0.025;
  final progressW = w * 0.34;
  final textAvailW = showProgress
      ? (availW - progressGap - progressW).clamp(w * 0.12, availW)
      : availW;
  final availH = slideHeight - vPad * 2;

  return bulletsFitScale(
    availW: textAvailW,
    availH: availH,
    hasTitle: slide.title.isNotEmpty,
    title: slide.title,
    bullets: bullets,
    titleSize: titleSize,
    bulletSize: bulletSize,
    spacing: spacing,
    bulletGap: bulletGap,
    font: font,
    subtitle: slide.subtitle,
    subtitleSize: subtitleSize,
    maxScale: bulletScaleCap(w, bulletSize, kSplitBulletsMaxScale),
    listStyle: slide.listStyle,
  );
}

/// Layout metrics for a two-column bullets slide.
double twoBulletsSlideFitScale({required Slide slide, required String font}) {
  final w = kReferenceSlideWidth;
  final pad = w * 0.07;
  final vPad = w * 0.05;
  final leftBullets = slide.bullets
      .where((b) => b.trimLeft().isNotEmpty)
      .toList();
  final rightBullets = slide.bullets2
      .where((b) => b.trimLeft().isNotEmpty)
      .toList();
  final dense = math.max(leftBullets.length, rightBullets.length) > 12;
  final titleSize = w * (dense ? 0.034 : 0.04);
  final bulletSize = w * 0.024;
  final spacing = pad * (dense ? 0.28 : 0.38);
  final bulletGap = w * (dense ? 0.0036 : 0.0055);
  final columnGap = w * 0.055;
  final col1Title = slide.columnTitle1.trim();
  final col2Title = slide.columnTitle2.trim();
  final hasColumnTitles = col1Title.isNotEmpty || col2Title.isNotEmpty;
  final headingSize = w * (dense ? 0.023 : 0.03);
  final headingGap = w * (dense ? 0.007 : 0.012);

  final slideHeight = w * 9 / 16;
  final contentW = (w - pad * 2).clamp(w * 0.12, w);
  final columnW = ((contentW - columnGap) / 2).clamp(w * 0.12, w);
  var availH = slideHeight - vPad * 2;
  if (slide.title.isNotEmpty) {
    availH -= measureTextHeight(
      slide.title,
      titleSize,
      contentW,
      bold: true,
      fontFamily: font,
    );
    availH -= spacing;
  }
  double headingHeight(String t) => t.isEmpty
      ? 0
      : measureTextHeight(
          t,
          headingSize,
          columnW,
          bold: true,
          fontFamily: font,
        );
  final maxHeadingH = math.max(
    headingHeight(col1Title),
    headingHeight(col2Title),
  );
  if (hasColumnTitles) availH -= maxHeadingH + headingGap;

  final leftScale = bulletsFitScale(
    availW: columnW,
    availH: availH,
    hasTitle: false,
    title: '',
    bullets: leftBullets,
    titleSize: titleSize,
    bulletSize: bulletSize,
    spacing: spacing,
    bulletGap: bulletGap,
    font: font,
    maxScale: bulletScaleCap(w, bulletSize, kBulletsMaxScale),
    listStyle: slide.listStyle,
  );
  final rightScale = bulletsFitScale(
    availW: columnW,
    availH: availH,
    hasTitle: false,
    title: '',
    bullets: rightBullets,
    titleSize: titleSize,
    bulletSize: bulletSize,
    spacing: spacing,
    bulletGap: bulletGap,
    font: font,
    maxScale: bulletScaleCap(w, bulletSize, kBulletsMaxScale),
    listStyle: slide.listStyle,
  );
  return math.min(leftScale, rightScale);
}

/// Total height of a rich-text bullets slide body at [scale].
double measureRichTextHeight({
  required double scale,
  required double contentW,
  required double refW,
  required bool hasTitle,
  required String title,
  required String subtitle,
  required double titleSize,
  required double subtitleSize,
  required double spacing,
  required String markdown,
  required double bodySize,
  required String font,
}) {
  var h = 0.0;
  if (hasTitle) {
    h += measureTextHeight(
      title,
      titleSize * scale,
      contentW,
      bold: true,
      fontFamily: font,
    );
  }
  if (subtitle.isNotEmpty) {
    h += spacing * scale * 0.4;
    h += measureTextHeight(
      subtitle,
      subtitleSize * scale,
      contentW,
      fontFamily: font,
    );
  }
  if ((hasTitle || subtitle.isNotEmpty) && markdown.trim().isNotEmpty) {
    h += spacing * scale;
  }
  h += md_body.markdownBodyHeight(
    markdown: markdown,
    contentW: contentW,
    refW: refW,
    bodySize: bodySize,
    font: font,
    scale: scale,
  );
  return h;
}

/// Nudge [scale] down until [measure] reports a height that fits [availH].
double tightenVerticalFitScale({
  required double scale,
  required double availH,
  required double Function(double scale) measure,
  double minScale = kTextDensityCriticalScale,
  double fillRatio = 0.96,
}) {
  var s = scale;
  // One measure() per iteration: `measure` is the expensive per-bullet
  // TextPainter pass, and the old `while (measure(s) ...) { final h = measure(s)`
  // form ran it twice each loop for the same scale.
  while (s > minScale + 0.005) {
    final h = measure(s);
    if (h <= availH * fillRatio) break;
    final next = (s * availH / h * fillRatio).clamp(minScale, s);
    if ((next - s).abs() < 0.001) break;
    s = next;
  }
  return s;
}

/// Nudge [scale] up until [measure] fills [availH] or [maxScale] is reached.
double growVerticalFitScale({
  required double scale,
  required double availH,
  required double Function(double scale) measure,
  required double maxScale,
  double fillRatio = 0.96,
}) {
  var s = scale;
  // One measure() per iteration (see tightenVerticalFitScale).
  while (s < maxScale - 0.005) {
    final h = measure(s);
    if (h >= availH * fillRatio || h <= 0) break;
    final next = (s * availH / h * fillRatio).clamp(s, maxScale);
    if ((next - s).abs() < 0.001) break;
    s = next;
  }
  return s;
}

/// Largest [scale] in [minScale, maxScale] where [measure](scale) fits [availH].
double maxVerticalFitScale({
  required double availH,
  required double refW,
  required double Function(double scale) measure,
  required double minScale,
  required double maxScale,
  double slopFraction = kRichTextRenderSlopFraction,
}) {
  if (availH <= 0) return 1.0;
  final target = (availH - refW * slopFraction).clamp(1.0, availH);

  if (measure(maxScale) <= target) return maxScale;
  if (measure(minScale) > target) return minScale;

  double lo;
  double hi;
  if (maxScale > 1.0 && measure(1.0) <= target) {
    lo = 1.0;
    hi = maxScale;
  } else {
    lo = minScale;
    hi = maxScale > 1.0 ? 1.0 : maxScale;
  }
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (measure(mid) <= target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Largest scale in [minScale, maxScale] for which a rich-text bullets body
/// fits [availH] at the full [contentW].
double richTextFitScale({
  required double availH,
  required double contentW,
  required double refW,
  required bool hasTitle,
  required String title,
  required String subtitle,
  required double titleSize,
  required double subtitleSize,
  required double spacing,
  required String markdown,
  required double bodySize,
  required String font,
  double minScale = kTextDensityCriticalScale,
  double maxScale = kSplitBulletsMaxScale,
}) {
  if (availH <= 0 || contentW <= 0) return 1.0;
  final target = (availH - refW * kRichTextRenderSlopFraction).clamp(
    1.0,
    availH,
  );

  double measure(double scale) => measureRichTextHeight(
    scale: scale,
    contentW: contentW,
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
  );

  if (measure(maxScale) <= target) return maxScale;

  double lo, hi;
  if (maxScale > 1.0 && measure(1.0) <= target) {
    lo = 1.0;
    hi = maxScale;
  } else {
    lo = minScale;
    hi = maxScale > 1.0 ? 1.0 : maxScale;
  }
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (measure(mid) <= target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Het aantal bullets dat — op natuurlijke grootte (schaal ≥ 1.0) — op één
/// slide past, per kolom. Gebruikt om een te volle bulletslide in tweeën te
/// splitsen: de [left]/[right] bullets blijven op slide 1, de rest verhuist.
///
/// Een waarde gelijk aan de lijstlengte betekent dat alles al past (geen fysieke
/// overloop). Voor enkelkoloms slides is [right] altijd 0 en niet van toepassing.
({int left, int right}) bulletFitCounts({
  required Slide slide,
  required String font,
}) {
  // [scaleFor] is niet-stijgend in n (meer bullets ⇒ kleinere fit-schaal), dus
  // we zoeken binair naar de grootste n waarbij de tekst nog op ware grootte past.
  int largestFitting(int total, double Function(int n) scaleFor) {
    if (total <= 1) return total;
    if (scaleFor(total) >= 1.0) return total; // alles past al
    var lo = 1, hi = total;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (scaleFor(mid) >= 1.0) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  switch (slide.type) {
    case SlideType.bullets:
      final n = slide.bullets.length;
      return (
        left: largestFitting(
          n,
          (k) => bulletsSlideFitScale(
            slide: slide.copyWith(bullets: slide.bullets.sublist(0, k)),
            font: font,
          ),
        ),
        right: 0,
      );
    case SlideType.bulletsImage:
      final n = slide.bullets.length;
      return (
        left: largestFitting(
          n,
          (k) => bulletsImageSlideFitScale(
            slide: slide.copyWith(bullets: slide.bullets.sublist(0, k)),
            font: font,
          ),
        ),
        right: 0,
      );
    case SlideType.twoBullets:
      // Elke kolom apart meten: met de andere kolom leeg valt de gecombineerde
      // fit-schaal samen met die van de gemeten kolom.
      return (
        left: largestFitting(
          slide.bullets.length,
          (k) => twoBulletsSlideFitScale(
            slide: slide.copyWith(
              bullets: slide.bullets.sublist(0, k),
              bullets2: const [],
            ),
            font: font,
          ),
        ),
        right: largestFitting(
          slide.bullets2.length,
          (k) => twoBulletsSlideFitScale(
            slide: slide.copyWith(
              bullets: const [],
              bullets2: slide.bullets2.sublist(0, k),
            ),
            font: font,
          ),
        ),
      );
    default:
      return (left: slide.bullets.length, right: slide.bullets2.length);
  }
}

/// Layout metrics for a bullets + image slide.
double bulletsImageSlideFitScale({required Slide slide, required String font}) {
  final w = kReferenceSlideWidth;
  final leftPad = w * 0.038;
  final verticalPad = w * 0.042;
  final gap = leftPad;
  final imgFraction = (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40)
      .clamp(0.1, 0.70);
  final imgWidth = w * imgFraction;
  final bulletSize = w * 0.031;
  final titleSize = w * 0.042;
  final spacing = verticalPad * 0.32;
  final bulletGap = w * 0.005;
  final bullets = slide.bullets.where((b) => b.trimLeft().isNotEmpty).toList();

  final slideHeight = w * 9 / 16;
  final availW = (w - imgWidth - gap - leftPad).clamp(w * 0.12, w);
  final availH = slideHeight - verticalPad * 2;

  return bulletsFitScale(
    availW: availW,
    availH: availH,
    hasTitle: slide.title.isNotEmpty,
    title: slide.title,
    bullets: bullets,
    titleSize: titleSize,
    bulletSize: bulletSize,
    spacing: spacing,
    bulletGap: bulletGap,
    font: font,
    maxScale: bulletScaleCap(w, bulletSize, kBulletsMaxScale),
    listStyle: slide.listStyle,
  );
}
