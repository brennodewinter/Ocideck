// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

class _BulletsPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _BulletsPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07;
    // Slightly tighter top/bottom margin than the side margin so short
    // checklists can grow into more of the slide height instead of leaving a
    // wide empty band below the text.
    final vPad = w * 0.05;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final titleSize = w * 0.042;
    final subtitleSize = w * 0.030;
    final bulletSize = w * 0.026;
    final spacing = pad * 0.5;
    final bulletGap = w * 0.006;
    final bullets = slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final hasTitle = slide.title.isNotEmpty;
    final subtitle = slide.subtitle;
    final hasSubtitle = subtitle.isNotEmpty;
    final showProgress =
        slide.listStyle == ListStyle.checklist &&
        slide.showChecklistProgress &&
        bullets.isNotEmpty;

    final slideHeight = w * 9 / 16;
    final availW = (w - pad * 2).clamp(w * 0.12, w);
    // The progress chart only needs a modest, fixed slot; give all remaining
    // width to the bullets so the text can grow as large (and readable) as
    // possible, especially on slides with many checklist items.
    final progressGap = w * 0.025;
    final progressW = w * 0.34;
    final textAvailW = showProgress
        ? (availW - progressGap - progressW).clamp(w * 0.12, availW)
        : availW;
    final availH = slideHeight - (vPad + safe.top) - (vPad + safe.bottom);
    // Grow (or, when needed, shrink) the text so it uses the full vertical
    // space instead of leaving a large empty area below a few short bullets.
    final scale = _bulletsFitScale(
      availW: textAvailW,
      availH: availH,
      hasTitle: hasTitle,
      title: slide.title,
      bullets: bullets,
      titleSize: titleSize,
      bulletSize: bulletSize,
      spacing: spacing,
      bulletGap: bulletGap,
      font: font,
      subtitle: subtitle,
      subtitleSize: subtitleSize,
      maxScale: _bulletScaleCap(w, bulletSize, _kSplitBulletsMaxScale),
      listStyle: slide.listStyle,
    );

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                vPad + safe.top,
                pad,
                vPad + safe.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasTitle)
                    _md(
                      context,
                      slide.title,
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: titleSize * scale,
                          fontWeight: FontWeight.bold,
                          color: _hexColor(profile.textColor),
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
                  if (hasSubtitle) ...[
                    SizedBox(height: spacing * scale * 0.4),
                    _md(
                      context,
                      subtitle,
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: subtitleSize * scale,
                          fontWeight: FontWeight.w600,
                          color: _hexColor(profile.accentColor),
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
                  ],
                  if ((hasTitle || hasSubtitle) && bullets.isNotEmpty)
                    SizedBox(height: spacing * scale),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _BulletListColumn(
                          bullets: bullets,
                          listStyle: slide.listStyle,
                          font: font,
                          profile: profile,
                          bulletSize: bulletSize,
                          bulletGap: bulletGap,
                          scale: scale,
                          column: 0,
                        ),
                      ),
                      if (showProgress) ...[
                        SizedBox(width: progressGap),
                        SizedBox(
                          width: progressW,
                          child: Center(
                            child: _ChecklistProgress(
                              bullets: bullets,
                              w: w,
                              font: font,
                              profile: profile,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoBulletsPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _TwoBulletsPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  /// One bullet column with an optional heading above it. When any column has a
  /// heading, an equal-height slot is reserved in both so the bullet lists line
  /// up.
  Widget _bulletColumn(
    BuildContext context, {
    required String title,
    required List<String> bullets,
    required double columnW,
    required double headingSize,
    required double headingSlotH,
    required double headingGap,
    required double bulletSize,
    required double bulletGap,
    required double scale,
    required int column,
  }) {
    return SizedBox(
      width: columnW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (headingSlotH > 0) ...[
            SizedBox(
              width: double.infinity,
              height: headingSlotH,
              child: title.isEmpty
                  ? null
                  : _md(
                      context,
                      title,
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: headingSize,
                          fontWeight: FontWeight.bold,
                          color: _hexColor(profile.accentColor),
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
            ),
            SizedBox(height: headingGap),
          ],
          _BulletListColumn(
            bullets: bullets,
            listStyle: slide.listStyle,
            font: font,
            profile: profile,
            bulletSize: bulletSize,
            bulletGap: bulletGap,
            scale: scale,
            column: column,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.065;
    // Tighter top/bottom margin than the side margin so dense columns (e.g. a
    // 19-item list) can use more of the slide height and stay readable.
    final vPad = w * 0.045;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final leftBullets = slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final rightBullets = slide.bullets2
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final hasTitle = slide.title.isNotEmpty;

    // On dense slides (a long column drives the shared text size down) spend
    // less of the height on the title, headings and inter-item gaps so the
    // list items themselves can render larger and stay readable.
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
    var availH = slideHeight - (vPad + safe.top) - (vPad + safe.bottom);
    if (hasTitle) {
      availH -= _measureTextHeight(
        slide.title,
        titleSize,
        contentW,
        bold: true,
        fontFamily: font,
      );
      availH -= spacing;
    }
    // Reserve room for the (optional) column headings so the bullets still fit.
    double headingHeight(String t) => t.isEmpty
        ? 0
        : _measureTextHeight(
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
    final leftScale = _bulletsFitScale(
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
      maxScale: _bulletScaleCap(w, bulletSize, _kBulletsMaxScale),
      listStyle: slide.listStyle,
    );
    final rightScale = _bulletsFitScale(
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
      maxScale: _bulletScaleCap(w, bulletSize, _kBulletsMaxScale),
      listStyle: slide.listStyle,
    );
    // Treat both columns as one composition: the busiest column determines
    // the shared text size, so left and right never look typographically
    // unrelated.
    final columnScale = math.min(leftScale, rightScale);

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: SizedBox.expand(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            pad,
            vPad + safe.top,
            pad,
            vPad + safe.bottom,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: contentW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasTitle)
                    _md(
                      context,
                      slide.title,
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: _hexColor(profile.textColor),
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
                  if (hasTitle) SizedBox(height: spacing),
                  if (slide.listStyle == ListStyle.checklist &&
                      slide.showChecklistProgress &&
                      (leftBullets.isNotEmpty || rightBullets.isNotEmpty)) ...[
                    Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: contentW * 0.5,
                        child: _ChecklistProgress(
                          bullets: [...leftBullets, ...rightBullets],
                          w: w,
                          font: font,
                          profile: profile,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bulletColumn(
                        context,
                        title: col1Title,
                        bullets: leftBullets,
                        columnW: columnW,
                        headingSize: headingSize,
                        headingSlotH: hasColumnTitles ? maxHeadingH : 0,
                        headingGap: headingGap,
                        bulletSize: bulletSize,
                        bulletGap: bulletGap,
                        scale: columnScale,
                        column: 0,
                      ),
                      SizedBox(width: columnGap),
                      _bulletColumn(
                        context,
                        title: col2Title,
                        bullets: rightBullets,
                        columnW: columnW,
                        headingSize: headingSize,
                        headingSlotH: hasColumnTitles ? maxHeadingH : 0,
                        headingGap: headingGap,
                        bulletSize: bulletSize,
                        bulletGap: bulletGap,
                        scale: columnScale,
                        column: 1,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulletsImagePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  const _BulletsImagePreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final leftPad = w * 0.038;
    final verticalPad = w * 0.042;
    // Keep the gap between the text column and the image equal to the slide's
    // left margin so the layout stays symmetric.
    final gap = leftPad;
    final safe = slide.showLogo
        ? _splitTextLogoSafeInsets(w, profile)
        : EdgeInsets.zero;
    final imgFraction = (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40)
        .clamp(0.1, 0.70);
    final imgWidth = w * imgFraction;
    final bulletSize = w * 0.031;
    final titleSize = w * 0.042;
    final spacing = verticalPad * 0.32;
    final bulletGap = w * 0.005;
    final bullets = slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final hasTitle = slide.title.isNotEmpty;

    // The slide is always rendered 16:9, so the available area for the text
    // column is fully determined by the width. Computing it directly (instead
    // of via a LayoutBuilder) keeps the widget tree identical to the image
    // side and avoids any layout-timing surprises.
    final slideHeight = w * 9 / 16;
    final availW = (w - imgWidth - gap - leftPad).clamp(w * 0.12, w);
    final availH =
        slideHeight - (verticalPad + safe.top) - (verticalPad + safe.bottom);
    // Pick the largest font scale (capped at the design size) whose content
    // still fits the available height at the full column width. This keeps the
    // text as large as possible and lets it span the full width toward the
    // image, instead of uniformly shrinking and leaving a wide gap.
    final scale = _bulletsFitScale(
      availW: availW,
      availH: availH,
      hasTitle: hasTitle,
      title: slide.title,
      bullets: bullets,
      titleSize: titleSize,
      bulletSize: bulletSize,
      spacing: spacing,
      bulletGap: bulletGap,
      font: font,
      maxScale: _bulletScaleCap(w, bulletSize, _kBulletsMaxScale),
      listStyle: slide.listStyle,
    );

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: imgWidth,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _resolvedImage(context, slide.imagePath, projectPath),
                _captionOverlay(context, slide.imageCaption, w),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: imgWidth + gap,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                leftPad,
                verticalPad + safe.top,
                0,
                verticalPad + safe.bottom,
              ),
              // FittedBox stays as a safety net for measurement rounding; with
              // an accurate scale it renders at scale 1 (full width).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: availW,
                  child: _contentColumn(
                    context: context,
                    scale: scale,
                    bullets: bullets,
                    hasTitle: hasTitle,
                    titleSize: titleSize,
                    bulletSize: bulletSize,
                    spacing: spacing,
                    bulletGap: bulletGap,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentColumn({
    required BuildContext context,
    required double scale,
    required List<String> bullets,
    required bool hasTitle,
    required double titleSize,
    required double bulletSize,
    required double spacing,
    required double bulletGap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle)
          _md(
            context,
            slide.title,
            _applyFont(
              font,
              TextStyle(
                fontSize: titleSize * scale,
                fontWeight: FontWeight.bold,
                color: _hexColor(profile.textColor),
              ),
            ),
            linkColor: _hexColor(profile.accentColor),
          ),
        if (hasTitle && bullets.isNotEmpty) SizedBox(height: spacing * scale),
        if (slide.listStyle == ListStyle.checklist &&
            slide.showChecklistProgress &&
            bullets.isNotEmpty) ...[
          _ChecklistProgress(
            bullets: bullets,
            w: w,
            font: font,
            profile: profile,
          ),
          SizedBox(height: spacing * scale),
        ],
        ...bullets.asMap().entries.map((entry) {
          final b = entry.value;
          int level = 0;
          while (level < b.length && b[level] == '\t') {
            level++;
          }
          final text = slide.listStyle == ListStyle.checklist
              ? checklistItemText(b)
              : b.substring(level);
          final checked =
              slide.listStyle == ListStyle.checklist && checklistItemChecked(b);
          final fontSize = bulletSize * _bulletLevelScale(level) * scale;
          return _ChecklistBulletRow(
            bullets: bullets,
            itemIndex: entry.key,
            column: 0,
            listStyle: slide.listStyle,
            checked: checked,
            text: text,
            level: level,
            fontSize: fontSize,
            bulletSize: bulletSize,
            bulletGap: bulletGap,
            scale: scale,
            font: font,
            profile: profile,
          );
        }),
      ],
    );
  }
}

class _BulletListColumn extends StatelessWidget {
  final List<String> bullets;
  final ListStyle listStyle;
  final String font;
  final ThemeProfile profile;
  final double bulletSize;
  final double bulletGap;
  final double scale;
  final int column;

  const _BulletListColumn({
    required this.bullets,
    required this.listStyle,
    required this.font,
    required this.profile,
    required this.bulletSize,
    required this.bulletGap,
    required this.scale,
    this.column = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...bullets.asMap().entries.map((entry) {
          final b = entry.value;
          int level = 0;
          while (level < b.length && b[level] == '\t') {
            level++;
          }
          final text = listStyle == ListStyle.checklist
              ? checklistItemText(b)
              : b.substring(level);
          final checked =
              listStyle == ListStyle.checklist && checklistItemChecked(b);
          final fontSize = bulletSize * _bulletLevelScale(level) * scale;
          return _ChecklistBulletRow(
            bullets: bullets,
            itemIndex: entry.key,
            column: column,
            listStyle: listStyle,
            checked: checked,
            text: text,
            level: level,
            fontSize: fontSize,
            bulletSize: bulletSize,
            bulletGap: bulletGap,
            scale: scale,
            font: font,
            profile: profile,
          );
        }),
      ],
    );
  }
}

/// Upper bound for growing bullet text to fill otherwise empty vertical space.
const double _kBulletsMaxScale = 3.2;

/// Split slides have a much narrower column, so short bullet lists can stay
/// visually timid unless they are allowed to grow a little further.
const double _kSplitBulletsMaxScale = 4.35;

/// Hard ceiling for the *rendered* bullet text size when auto-growing, as a
/// fraction of the slide width: ≈32pt on a standard 16:9 deck (PowerPoint's
/// 960pt-wide canvas). Presentation-design guidance consistently puts body
/// text at 24–32pt — beyond that it stops aiding readability and starts
/// competing with the title. The fit scale multiplies title and bullets
/// alike, so capping the bullet size also keeps the hierarchy intact.
const double _kBulletMaxFontFraction = 0.0335;

/// The largest auto-fit scale that keeps bullets at or under
/// [_kBulletMaxFontFraction], given the layout's own [layoutMax] growth bound.
double _bulletScaleCap(double w, double bulletSize, double layoutMax) =>
    math.min(layoutMax, _kBulletMaxFontFraction * w / bulletSize);

/// Line height used for bullet body text, shared by rendering and measuring.
const double _kBulletLineHeight = 1.16;

String _bulletMarkerForLevel(int level) {
  const markers = ['•', '◦', '▪', '▫', '–'];
  return markers[level.clamp(0, markers.length - 1)];
}

String _listMarker(List<String> items, int index, ListStyle style) {
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

double _bulletLevelScale(int level) {
  if (level <= 0) return 1.0;
  if (level == 1) return 0.86;
  if (level == 2) return 0.80;
  return 0.76;
}

/// Largest scale in [minScale, maxScale] for which the bullet block fits
/// [availH] at the full column width. Unlike a plain `BoxFit.scaleDown`, this
/// also grows the text *above* its design size when there is spare vertical
/// room, so short slides use the full height instead of clustering at the top.
double _bulletsFitScale({
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
  double minScale = 0.2,
  double maxScale = 1.0,
  ListStyle listStyle = ListStyle.bullets,
}) {
  if (availW <= 0 || !availH.isFinite || availH <= 0) return 1.0;
  // 2% safety margin so minor measurement differences never overflow.
  final budget = availH * 0.98;
  double measure(double scale) => _bulletsBlockHeight(
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

  // Everything already fits at the largest allowed size → use it.
  if (measure(maxScale) <= budget) return maxScale;

  // Otherwise binary-search the largest scale that fits. Search upward from the
  // design size when it fits, downward when even the design size overflows.
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

double _bulletsBlockHeight({
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
    height += _measureTextHeight(
      title,
      titleSize * scale,
      availW,
      bold: true,
      fontFamily: font,
    );
  }
  if (subtitle.isNotEmpty) {
    height += spacing * scale * 0.4;
    height += _measureTextHeight(
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
    int level = 0;
    while (level < b.length && b[level] == '\t') {
      level++;
    }
    // Measure exactly what gets rendered: checklists strip the `[x] ` prefix
    // and use a checkbox marker, numbered lists use `N.`. Measuring the raw
    // string with a bullet marker over-counts the height and would shrink the
    // text below the space it actually needs.
    final text = listStyle == ListStyle.checklist
        ? checklistItemText(b)
        : b.substring(level);
    final fontSize = bulletSize * _bulletLevelScale(level) * scale;
    final indent = level * bulletSize * 1.05 * scale;
    final marker = '${_listMarker(bullets, i, listStyle)} ';
    final markerW = _measureTextWidth(
      marker,
      fontSize,
      bold: true,
      fontFamily: font,
    );
    final wrapW = (availW - indent - markerW).clamp(1.0, availW);
    final textH = _measureTextHeight(
      text,
      fontSize,
      wrapW,
      lineHeight: _kBulletLineHeight,
      fontFamily: font,
    );
    final markerH = _measureTextHeight(
      marker,
      fontSize,
      double.infinity,
      fontFamily: font,
    );
    height += bulletGap * scale * 2 + (textH > markerH ? textH : markerH);
  }
  return height;
}

double _measureTextHeight(
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

double _measureTextWidth(
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
