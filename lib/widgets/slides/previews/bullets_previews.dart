// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Clips bullets-slide content to the real layout box. [OverflowBox] keeps the
/// inner column from throwing flex overflow; [ClipRect] hides any remainder.
Widget _bulletsSlideShell({
  required Color background,
  required EdgeInsets padding,
  required Widget Function(double availW, double availH) buildContent,
}) {
  return Container(
    color: background,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final outerW = constraints.maxWidth;
        final outerH = constraints.maxHeight;
        final availW = (outerW - padding.horizontal).clamp(1.0, outerW);
        final availH = (outerH - padding.vertical).clamp(1.0, outerH);
        return ClipRect(
          child: SizedBox(
            width: outerW,
            height: outerH,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: outerW,
              maxHeight: double.infinity,
              child: Padding(
                padding: padding,
                child: buildContent(availW, availH),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _BulletsPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final int richTextPage;
  final bool showRichTextPageControls;
  final ValueChanged<int>? onRichTextPageChanged;

  const _BulletsPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.richTextPage = 0,
    this.showRichTextPageControls = false,
    this.onRichTextPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (slide.listStyle == ListStyle.richText) {
      return _buildRichTextPreview(context);
    }

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

    final progressGap = w * 0.025;
    final progressW = w * 0.34;
    final padding = EdgeInsets.fromLTRB(
      pad,
      vPad + safe.top,
      pad,
      bulletsSlideBottomInset(
        w: w,
        slide: slide,
        profile: profile,
        defaultBottomPad: vPad,
        safeBottom: safe.bottom,
      ),
    );

    return _bulletsSlideShell(
      background: _hexColor(profile.slideBackgroundColor),
      padding: padding,
      buildContent: (contentW, availH) {
        final textAvailW = showProgress
            ? (contentW - progressGap - progressW).clamp(w * 0.12, contentW)
            : contentW;
        var scale = bulletsFitScale(
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
          maxScale: bulletScaleCap(w, bulletSize, kSplitBulletsMaxScale),
          listStyle: slide.listStyle,
        );
        scale = tightenVerticalFitScale(
          scale: scale,
          availH: availH,
          measure: (s) => bulletsBlockHeight(
            scale: s,
            availW: textAvailW,
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
            listStyle: slide.listStyle,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    marker: slide.bulletMarkerOverride ?? profile.bulletMarker,
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
        );
      },
    );
  }

  Widget _buildRichTextPreview(BuildContext context) {
    final pad = w * 0.07;
    final vPad = w * 0.05;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final padding = EdgeInsets.fromLTRB(
      pad,
      vPad + safe.top,
      pad,
      bulletsSlideBottomInset(
        w: w,
        slide: slide,
        profile: profile,
        defaultBottomPad: vPad,
        safeBottom: safe.bottom,
      ),
    );

    return _bulletsSlideShell(
      background: _hexColor(profile.slideBackgroundColor),
      padding: padding,
      buildContent: (contentW, availH) => _richTextPaginatedContent(
        context: context,
        slide: slide,
        w: w,
        font: font,
        profile: profile,
        contentW: contentW,
        availH: availH,
        splitWithImage: false,
        richTextPage: richTextPage,
        showPageControls: showRichTextPageControls,
      ),
    );
  }
}

Widget _richTextPaginatedContent({
  required BuildContext context,
  required Slide slide,
  required double w,
  required String font,
  required ThemeProfile profile,
  required double contentW,
  required double availH,
  required bool splitWithImage,
  int richTextPage = 0,
  bool showPageControls = false,
}) {
  final pad = splitWithImage ? w * 0.038 : w * 0.07;
  final vPad = splitWithImage ? w * 0.042 : w * 0.05;
  final titleSize = w * 0.042;
  final subtitleSize = w * 0.030;
  final spacing = splitWithImage ? vPad * 0.32 : pad * 0.5;
  final bodySize = splitWithImage ? w * 0.031 : w * 0.026;
  final footer = footerSafeInset(w: w, slide: slide, profile: profile);
  final budget = richTextLayoutBudget(availH, footer);

  final plan = planRichTextForSlide(
    slide: slide,
    profile: profile,
    w: w,
    availW: contentW,
    availH: availH,
    font: font,
    splitWithImage: splitWithImage,
  );
  final pageIndex = richTextPage.clamp(0, plan.pageCount - 1);
  final pageMarkdown = plan.markdownForPage(pageIndex);
  final maxScale = bulletScaleCap(
    w,
    bodySize,
    splitWithImage ? kBulletsMaxScale : kSplitBulletsMaxScale,
  );
  final scale = richTextScaleForPage(
    plan: plan,
    pageIndex: pageIndex,
    budget: budget,
    availW: contentW,
    refW: w,
    hasTitle: slide.title.isNotEmpty,
    title: slide.title,
    subtitle: slide.subtitle,
    titleSize: titleSize,
    subtitleSize: subtitleSize,
    spacing: spacing,
    bodySize: bodySize,
    font: font,
    maxScale: maxScale,
  );
  final showTitle = pageIndex == 0 && slide.title.isNotEmpty;
  final subtitle = slide.subtitle;
  final showSubtitle = pageIndex == 0 && subtitle.isNotEmpty;
  final body = pageMarkdown.trim();

  return SizedBox(
    width: contentW,
    height: availH,
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: contentW,
            maxHeight: double.infinity,
            child: SizedBox(
              width: contentW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTitle)
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
                  if (showSubtitle) ...[
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
                  if ((showTitle || showSubtitle) && body.isNotEmpty)
                    SizedBox(height: spacing * scale),
                  ..._markdownBodyBlocks(
                    context,
                    markdown: pageMarkdown,
                    w: w,
                    font: font,
                    profile: profile,
                    bodyFontSize: bodySize * scale,
                    contentWidth: contentW,
                    emptyLineHeight: w * 0.01 * scale,
                    heading1Size: w * 0.04 * scale,
                    heading2Size: w * 0.03 * scale,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (plan.pageCount > 1 && !showPageControls)
          Positioned(
            top: w * 0.012,
            right: w * 0.012,
            child: _richTextPageBadge(
              label: '${pageIndex + 1} / ${plan.pageCount}',
              w: w,
              font: font,
              profile: profile,
            ),
          ),
      ],
    ),
  );
}

Widget _richTextPageBadge({
  required String label,
  required double w,
  required String font,
  required ThemeProfile profile,
}) {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: w * 0.014, vertical: w * 0.005),
    decoration: BoxDecoration(
      color: _hexColor(profile.textColor).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(w * 0.008),
      border: Border.all(
        color: _hexColor(profile.textColor).withValues(alpha: 0.2),
      ),
    ),
    child: Text(
      label,
      style: _applyFont(
        font,
        TextStyle(
          fontSize: w * 0.018,
          color: _hexColor(profile.textColor).withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
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
            marker: slide.bulletMarkerOverride ?? profile.bulletMarker,
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
    final padding = EdgeInsets.fromLTRB(
      pad,
      vPad + safe.top,
      pad,
      bulletsSlideBottomInset(
        w: w,
        slide: slide,
        profile: profile,
        defaultBottomPad: vPad,
        safeBottom: safe.bottom,
      ),
    );

    return _bulletsSlideShell(
      background: _hexColor(profile.slideBackgroundColor),
      padding: padding,
      buildContent: (contentW, layoutH) {
        final columnW = ((contentW - columnGap) / 2).clamp(w * 0.12, w);
        var availH = layoutH;
        if (hasTitle) {
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
        var columnScale = math.min(leftScale, rightScale);
        columnScale = tightenVerticalFitScale(
          scale: columnScale,
          availH: availH,
          measure: (s) => math.max(
            bulletsBlockHeight(
              scale: s,
              availW: columnW,
              hasTitle: false,
              title: '',
              bullets: leftBullets,
              titleSize: titleSize,
              bulletSize: bulletSize,
              spacing: spacing,
              bulletGap: bulletGap,
              font: font,
              listStyle: slide.listStyle,
            ),
            bulletsBlockHeight(
              scale: s,
              availW: columnW,
              hasTitle: false,
              title: '',
              bullets: rightBullets,
              titleSize: titleSize,
              bulletSize: bulletSize,
              spacing: spacing,
              bulletGap: bulletGap,
              font: font,
              listStyle: slide.listStyle,
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
        );
      },
    );
  }
}

class _BulletsImagePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;
  final int richTextPage;
  final bool showRichTextPageControls;
  final ValueChanged<int>? onRichTextPageChanged;

  const _BulletsImagePreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.richTextPage = 0,
    this.showRichTextPageControls = false,
    this.onRichTextPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (slide.listStyle == ListStyle.richText) {
      return _buildRichTextWithImage(context);
    }

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
    final textPadding = EdgeInsets.fromLTRB(
      leftPad,
      verticalPad + safe.top,
      0,
      bulletsSlideBottomInset(
        w: w,
        slide: slide,
        profile: profile,
        defaultBottomPad: verticalPad,
        safeBottom: safe.bottom,
      ),
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
                _resolvedImage(
                  context,
                  slide.imagePath,
                  projectPath,
                  semanticLabel: imageSemanticsLabel(context, slide.imageCaption),
                ),
                _captionOverlay(context, slide.imageCaption, w),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: imgWidth + gap,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final outerW = constraints.maxWidth;
                final outerH = constraints.maxHeight;
                final availW = (outerW - textPadding.horizontal).clamp(
                  w * 0.12,
                  w,
                );
                final availH = (outerH - textPadding.vertical).clamp(
                  1.0,
                  outerH,
                );
                var scale = bulletsFitScale(
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
                  maxScale: bulletScaleCap(w, bulletSize, kBulletsMaxScale),
                  listStyle: slide.listStyle,
                );
                scale = tightenVerticalFitScale(
                  scale: scale,
                  availH: availH,
                  measure: (s) => bulletsBlockHeight(
                    scale: s,
                    availW: availW,
                    hasTitle: hasTitle,
                    title: slide.title,
                    bullets: bullets,
                    titleSize: titleSize,
                    bulletSize: bulletSize,
                    spacing: spacing,
                    bulletGap: bulletGap,
                    font: font,
                    listStyle: slide.listStyle,
                  ),
                );

                return ClipRect(
                  child: SizedBox(
                    width: outerW,
                    height: outerH,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: outerW,
                      maxHeight: double.infinity,
                      child: Padding(
                        padding: textPadding,
                        child: _contentColumn(
                          context: context,
                          scale: scale,
                          bullets: bullets,
                          hasTitle: hasTitle,
                          titleSize: titleSize,
                          bulletSize: bulletSize,
                          spacing: spacing,
                          bulletGap: bulletGap,
                          contentWidth: availW,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichTextWithImage(BuildContext context) {
    final leftPad = w * 0.038;
    final verticalPad = w * 0.042;
    final gap = leftPad;
    final safe = slide.showLogo
        ? _splitTextLogoSafeInsets(w, profile)
        : EdgeInsets.zero;
    final imgFraction = (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40)
        .clamp(0.1, 0.70);
    final imgWidth = w * imgFraction;
    final textPadding = EdgeInsets.fromLTRB(
      leftPad,
      verticalPad + safe.top,
      0,
      bulletsSlideBottomInset(
        w: w,
        slide: slide,
        profile: profile,
        defaultBottomPad: verticalPad,
        safeBottom: safe.bottom,
      ),
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
                _resolvedImage(
                  context,
                  slide.imagePath,
                  projectPath,
                  semanticLabel: imageSemanticsLabel(context, slide.imageCaption),
                ),
                _captionOverlay(context, slide.imageCaption, w),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: imgWidth + gap,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final outerW = constraints.maxWidth;
                final outerH = constraints.maxHeight;
                final availW = (outerW - textPadding.horizontal).clamp(
                  w * 0.12,
                  w,
                );
                final availH = (outerH - textPadding.vertical).clamp(
                  1.0,
                  outerH,
                );

                return ClipRect(
                  child: SizedBox(
                    width: outerW,
                    height: outerH,
                    child: Padding(
                      padding: textPadding,
                      child: _richTextPaginatedContent(
                        context: context,
                        slide: slide,
                        w: w,
                        font: font,
                        profile: profile,
                        contentW: availW,
                        availH: availH,
                        splitWithImage: true,
                        richTextPage: richTextPage,
                        showPageControls: showRichTextPageControls,
                      ),
                    ),
                  ),
                );
              },
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
    required double contentWidth,
  }) {
    return SizedBox(
      width: contentWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                slide.listStyle == ListStyle.checklist &&
                checklistItemChecked(b);
            final fontSize = bulletSize * bulletLevelScale(level) * scale;
            return _ChecklistBulletRow(
              bullets: bullets,
              itemIndex: entry.key,
              column: 0,
              listStyle: slide.listStyle,
              marker: slide.bulletMarkerOverride ?? profile.bulletMarker,
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
      ),
    );
  }
}

class _BulletListColumn extends StatelessWidget {
  final List<String> bullets;
  final ListStyle listStyle;
  final BulletMarker marker;
  final String font;
  final ThemeProfile profile;
  final double bulletSize;
  final double bulletGap;
  final double scale;
  final int column;

  const _BulletListColumn({
    required this.bullets,
    required this.listStyle,
    this.marker = BulletMarker.dot,
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
          final fontSize = bulletSize * bulletLevelScale(level) * scale;
          return _ChecklistBulletRow(
            bullets: bullets,
            itemIndex: entry.key,
            column: column,
            listStyle: listStyle,
            marker: marker,
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
