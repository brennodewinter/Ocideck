// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability (bullets+image layout); all imports live in
// the main library file. Top-level preview widgets relocate verbatim.
part of '../slide_preview.dart';

class _BulletsImagePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;
  final int richTextPage;

  /// First number for a numbered list (continues a chain across slides).
  final int numberStart;

  /// Shared font scale for a split run (see [SlidePreviewWidget.fitScaleOverride]).
  final double? fitScaleOverride;

  /// Position within a split run for the "(page/total)" title counter
  /// (see [SlidePreviewWidget.splitRunPosition]).
  final ({int page, int total})? splitRunPosition;

  const _BulletsImagePreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.richTextPage = 0,
    this.numberStart = 1,
    this.fitScaleOverride,
    this.splitRunPosition,
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
    final textPadding = _bulletsPadding(
      w: w,
      slide: slide,
      profile: profile,
      safe: safe,
      pad: leftPad,
      vPad: verticalPad,
      rightPad: 0,
    );

    return Container(
      color: AppTheme.parseHexColor(profile.slideBackgroundColor),
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
                _panelImage(
                  context,
                  slide.imagePath,
                  projectPath,
                  slide.imageZoom,
                  focalAlignment(slide.imageFocalX, slide.imageFocalY),
                  imageSemanticsLabel(
                    context,
                    slide.imageCaption,
                    altText: slide.imageAltText,
                  ),
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
                final scale = _imageBulletsScale(
                  availW: availW,
                  availH: availH,
                  bullets: bullets,
                  hasTitle: hasTitle,
                  titleSize: titleSize,
                  bulletSize: bulletSize,
                  spacing: spacing,
                  bulletGap: bulletGap,
                );
                // Deelt deze pagina een split-run met andere pagina's, dan
                // rendert ze op de gedeelde (kleinste) schaal — nooit groter dan
                // haar eigen fit.
                final resolvedScale = fitScaleOverride != null
                    ? math.min(fitScaleOverride!, scale)
                    : scale;

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
                          scale: resolvedScale,
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

  /// Resolved vertical fit-scale for the text column, memoised across rebuilds
  /// (see [memoizedRenderLayout]) so an unrelated edit doesn't re-measure this
  /// slide's unchanged text.
  double _imageBulletsScale({
    required double availW,
    required double availH,
    required List<String> bullets,
    required bool hasTitle,
    required double titleSize,
    required double bulletSize,
    required double spacing,
    required double bulletGap,
  }) {
    return memoizedRenderLayout<double>(
      slide: slide,
      font: font,
      width: w,
      availW: availW,
      availH: availH,
      compute: () {
        var s = bulletsFitScale(
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
        s = tightenVerticalFitScale(
          scale: s,
          availH: availH,
          measure: (m) => bulletsBlockHeight(
            scale: m,
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
        return s;
      },
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
    final textPadding = _bulletsPadding(
      w: w,
      slide: slide,
      profile: profile,
      safe: safe,
      pad: leftPad,
      vPad: verticalPad,
      rightPad: 0,
    );

    return Container(
      color: AppTheme.parseHexColor(profile.slideBackgroundColor),
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
                _panelImage(
                  context,
                  slide.imagePath,
                  projectPath,
                  slide.imageZoom,
                  focalAlignment(slide.imageFocalX, slide.imageFocalY),
                  imageSemanticsLabel(
                    context,
                    slide.imageCaption,
                    altText: slide.imageAltText,
                  ),
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
                        projectPath: projectPath,
                        richTextPage: richTextPage,
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
            _titleWithSplitCounter(
              context,
              slide.title,
              _applyFont(
                font,
                TextStyle(
                  fontSize: titleSize * scale,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.parseHexColor(profile.textColor),
                ),
              ),
              linkColor: AppTheme.parseHexColor(profile.accentColor),
              position: splitRunPosition,
              fit: slide.marpStyle.headingFit,
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
            if (isGroupHeading(b)) {
              return _GroupHeadingRow(
                label: groupHeadingText(b),
                fontSize: bulletSize * scale,
                bulletSize: bulletSize,
                bulletGap: bulletGap,
                scale: scale,
                isFirst: entry.key == 0,
                font: font,
                profile: profile,
              );
            }
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
              startNumber: numberStart,
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

  /// First number for a numbered list (continues a chain across slides).
  final int numberStart;

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
    this.numberStart = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...bullets.asMap().entries.map((entry) {
          final b = entry.value;
          if (isGroupHeading(b)) {
            return _GroupHeadingRow(
              label: groupHeadingText(b),
              fontSize: bulletSize * scale,
              bulletSize: bulletSize,
              bulletGap: bulletGap,
              scale: scale,
              isFirst: entry.key == 0,
              font: font,
              profile: profile,
            );
          }
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
            startNumber: numberStart,
          );
        }),
      ],
    );
  }
}

/// Reserveert boven- en onderrand voor het logo bij de smalle tekstkolom naast
/// een afbeelding. Woont bij de enige gebruiker (de bullets-met-afbeelding-
/// preview) zodat de bibliotheekwortel onder haar bestandsplafond blijft.
EdgeInsets _splitTextLogoSafeInsets(double w, ThemeProfile profile) {
  final (top, bottom) = logoSafeReserveEdges(w, profile, splitText: true);
  return EdgeInsets.only(top: top, bottom: bottom);
}

/// Rendert een paneelafbeelding (bulletsImage/twoImages) met optionele zoom.
/// `zoom == 0` → cover (standaard, vult slot, snijdt bij). `zoom > 0` →
/// hergebruikt [_zoomedImage] voor contain/zoom-in gedrag.
Widget _panelImage(
  BuildContext context,
  String imagePath,
  String? projectPath,
  int zoom,
  Alignment alignment,
  String? semanticLabel,
) {
  if (zoom == 0) {
    return _resolvedImage(
      context,
      imagePath,
      projectPath,
      alignment: alignment,
      semanticLabel: semanticLabel,
    );
  }
  return _zoomedImage(
    context,
    imagePath,
    projectPath,
    zoom,
    alignment: alignment,
    semanticLabel: semanticLabel,
  );
}
