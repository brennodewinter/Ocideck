import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/slide.dart';
import '../widgets/slides/inline_markdown.dart';

/// Reference slide width (960pt) used for consistent quality metrics across
/// deck sizes — matches the PowerPoint 16:9 canvas the previews emulate.
const double kReferenceSlideWidth = 960.0;

const double kBulletsMaxScale = 3.2;
const double kSplitBulletsMaxScale = 4.35;

/// Hard ceiling for rendered bullet text as a fraction of slide width.
const double kBulletMaxFontFraction = 0.0335;

const double kBulletLineHeight = 1.16;

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

double measureTextHeight(
  String text,
  double fontSize,
  double maxWidth, {
  double? lineHeight,
  bool bold = false,
  String? fontFamily,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: stripInlineMarkdown(text),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: lineHeight,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);
  return painter.height;
}

double measureTextWidth(
  String text,
  double fontSize, {
  bool bold = false,
  String? fontFamily,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: stripInlineMarkdown(text),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
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
