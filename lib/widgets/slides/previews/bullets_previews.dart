// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// De titel van een bulletdia, met — wanneer de dia één pagina van een
/// gesplitste reeks is ([position] niet null en meer dan één pagina) — een
/// bescheiden "(pagina/totaal)"-teller erachter (#1164). Zonder reeks precies
/// [_md]: een losse dia toont niets extra en de bestaande goldens veranderen niet.
///
/// De teller loopt als trailing-span in dezelfde paragraaf mee: kleiner en
/// gedempt, op de tekstbaseline, en met een vaste-spatie aan het laatste woord
/// geplakt zodat hij bij een titel over meerdere regels tegen de titel blijft
/// staan in plaats van naar de rechterrand te zweven. Gedeeld door de drie
/// bullet-previews zodat de Flutter-renderoppervlakken (editor, slidestrook,
/// presentatie, publiek en de gerasterde PDF-export) dezelfde teller tonen. De
/// markdown-getrouwe HTML/Marp-export rendert de titel uit de ruwe markdown en
/// toont de teller bewust niet — een render-decoratie hoort niet in de
/// interchange-inhoud.
Widget _titleWithSplitCounter(
  BuildContext context,
  String title,
  TextStyle style, {
  required Color linkColor,
  required ({int page, int total})? position,
}) {
  if (position == null || position.total <= 1) {
    return _md(context, title, style, linkColor: linkColor);
  }
  final baseColor = style.color ?? Colors.black;
  // Non-breaking space: de teller breekt niet los van het laatste woord.
  final counter = TextSpan(
    text: '\u00A0${position.page}/${position.total}',
    style: style.copyWith(
      fontSize: (style.fontSize ?? 12) * 0.62,
      fontWeight: FontWeight.w500,
      color: baseColor.withValues(alpha: 0.55),
    ),
  );
  return _md(context, title, style, linkColor: linkColor, trailing: counter);
}

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
        // `clamp` gooit `ArgumentError` zodra de bovengrens onder de ondergrens
        // zakt, en die bovengrens is hier een layout-constraint: bij een
        // breedte onder 1,0 viel deze regel om met `Invalid argument(s): 1.0`.
        // Zelfde fout als #714, andere plek — daar was het `clamp(1, total)`
        // met een teller die nul mocht zijn.
        //
        // Een nulbreedte is geen onzin-invoer: Flutter meet een widget vaker
        // dan hij hem tekent, en een inklappend paneel of een rij zonder
        // resterende ruimte levert er precies dat aan. Een preview hoort dan
        // niets te tekenen, niet te ontploffen.
        final availW = math.max(
          1.0,
          math.min(outerW, outerW - padding.horizontal),
        );
        final availH = math.max(
          1.0,
          math.min(outerH, outerH - padding.vertical),
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

/// De breedte die de bullettekst overhoudt naast de voortgangsgrafiek.
///
/// Zelfde valkuil als in [_bulletsSlideShell]: hier was het
/// `.clamp(w * 0.12, contentW)`, en `contentW` is de bovengrens. Zakt die onder
/// de ondergrens, dan gooit `clamp` — dus wordt de ondergrens zelf eerst door de
/// beschikbare ruimte begrensd.
double _textWidthBesideProgress(
  double contentW,
  double w,
  double progressGap,
  double progressW,
) => math.max(
  math.min(w * 0.12, contentW),
  math.min(contentW, contentW - progressGap - progressW),
);

class _BulletsPreview extends StatelessWidget {
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

  const _BulletsPreview({
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
      return _buildRichTextPreview(context);
    }

    final pad = w * 0.07;
    final vPad = w * 0.05;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final padding = _bulletsPadding(
      w: w,
      slide: slide,
      profile: profile,
      safe: safe,
      pad: pad,
      vPad: vPad,
    );

    return _bulletsSlideShell(
      background: AppTheme.parseHexColor(profile.slideBackgroundColor),
      padding: padding,
      buildContent: (contentW, availH) =>
          _bulletsContent(context, contentW, availH),
    );
  }

  Widget _bulletsContent(BuildContext context, double contentW, double availH) {
    final titleSize = w * 0.042;
    final subtitleSize = w * 0.030;
    final bulletSize = w * 0.026;
    final spacing = w * 0.07 * 0.5;
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
    final textAvailW = showProgress
        ? _textWidthBesideProgress(contentW, w, progressGap, progressW)
        : contentW;
    final scale = memoizedRenderLayout<double>(
      slide: slide,
      font: font,
      width: w,
      availW: textAvailW,
      availH: availH,
      compute: () {
        var s = bulletsFitScale(
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
        s = tightenVerticalFitScale(
          scale: s,
          availH: availH,
          measure: (m) => bulletsBlockHeight(
            scale: m,
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
        return s;
      },
    );

    // A split run shares one size: cap this page at the run's shared scale (the
    // fullest page's fit). `min` keeps it safe — never larger than what fits
    // this page — so a shared scale can only shrink an emptier page, not
    // overflow a fuller one.
    final resolvedScale = fitScaleOverride != null
        ? math.min(fitScaleOverride!, scale)
        : scale;

    return Column(
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
                fontSize: titleSize * resolvedScale,
                fontWeight: FontWeight.bold,
                color: AppTheme.parseHexColor(profile.textColor),
              ),
            ),
            linkColor: AppTheme.parseHexColor(profile.accentColor),
            position: splitRunPosition,
          ),
        if (hasSubtitle) ...[
          SizedBox(height: spacing * resolvedScale * 0.4),
          _md(
            context,
            subtitle,
            _applyFont(
              font,
              TextStyle(
                fontSize: subtitleSize * resolvedScale,
                fontWeight: FontWeight.w600,
                color: AppTheme.parseHexColor(profile.accentColor),
              ),
            ),
            linkColor: AppTheme.parseHexColor(profile.accentColor),
          ),
        ],
        if ((hasTitle || hasSubtitle) && bullets.isNotEmpty)
          SizedBox(height: spacing * resolvedScale),
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
                scale: resolvedScale,
                column: 0,
                numberStart: numberStart,
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
  }

  Widget _buildRichTextPreview(BuildContext context) {
    final pad = w * 0.07;
    final vPad = w * 0.05;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final padding = _bulletsPadding(
      w: w,
      slide: slide,
      profile: profile,
      safe: safe,
      pad: pad,
      vPad: vPad,
    );

    return _bulletsSlideShell(
      background: AppTheme.parseHexColor(profile.slideBackgroundColor),
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
        projectPath: projectPath,
        richTextPage: richTextPage,
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
  String? projectPath,
  int richTextPage = 0,
}) {
  final pad = splitWithImage ? w * 0.038 : w * 0.07;
  final vPad = splitWithImage ? w * 0.042 : w * 0.05;
  final titleSize = w * 0.042;
  final subtitleSize = w * 0.030;
  final spacing = splitWithImage ? vPad * 0.32 : pad * 0.5;
  // Spiegel de planner: free-markdown houdt w*0,024 (#1409), bullets w*0,026.
  final bodySize = slide.type == SlideType.freeMarkdown
      ? w * 0.024
      : (splitWithImage ? w * 0.031 : w * 0.026);
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
  // Every page of a rich-text slide renders at the plan's single shared scale
  // (sized to the fullest page), so paging through never changes the text size —
  // the same principle as the split-bullets fix. The plan already grew this
  // scale to the largest that fits the tallest page, so no page overflows and a
  // sparse last page no longer swells larger than the rest.
  final scale = plan.scale;
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
                          color: AppTheme.parseHexColor(profile.textColor),
                        ),
                      ),
                      linkColor: AppTheme.parseHexColor(profile.accentColor),
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
                          color: AppTheme.parseHexColor(profile.accentColor),
                        ),
                      ),
                      linkColor: AppTheme.parseHexColor(profile.accentColor),
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
                    projectPath: projectPath,
                    scale: scale,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Geen "1 / 3"-teller op de dia. Die telde per slide opnieuw vanaf één,
        // terwijl de zaal naar dia 7 van 24 kijkt — twee nummeringen door
        // elkaar, waarvan de opvallendste de minst betekenisvolle was. Wie wél
        // moet weten waar hij is, ziet het waar het thuishoort: de editor en de
        // presentatorweergave tonen "Pagina 2 / 3" in hun eigen rand, en de
        // export klapt de pagina's uit tot echte dia's zodat de voettekst ze
        // gewoon meetelt (`expandRichTextForRender`).
      ],
    ),
  );
}

class _TwoBulletsPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  /// Shared font scale for a split run (see [SlidePreviewWidget.fitScaleOverride]).
  final double? fitScaleOverride;

  /// Position within a split run for the "(page/total)" title counter
  /// (see [SlidePreviewWidget.splitRunPosition]).
  final ({int page, int total})? splitRunPosition;

  const _TwoBulletsPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.fitScaleOverride,
    this.splitRunPosition,
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
                          color: AppTheme.parseHexColor(profile.accentColor),
                        ),
                      ),
                      linkColor: AppTheme.parseHexColor(profile.accentColor),
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
    final vPad = w * 0.045;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final padding = _bulletsPadding(
      w: w,
      slide: slide,
      profile: profile,
      safe: safe,
      pad: pad,
      vPad: vPad,
    );
    return _bulletsSlideShell(
      background: AppTheme.parseHexColor(profile.slideBackgroundColor),
      padding: padding,
      buildContent: (contentW, layoutH) =>
          _twoBulletsContent(context, contentW, layoutH),
    );
  }

  Widget _twoBulletsContent(
    BuildContext context,
    double contentW,
    double layoutH,
  ) {
    final pad = w * 0.065;
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
    final layout = _twoBulletsScale(
      contentW,
      layoutH,
      columnGap: columnGap,
      hasTitle: hasTitle,
      titleSize: titleSize,
      col1Title: col1Title,
      col2Title: col2Title,
      headingSize: headingSize,
      hasColumnTitles: hasColumnTitles,
      headingGap: headingGap,
      leftBullets: leftBullets,
      rightBullets: rightBullets,
      bulletSize: bulletSize,
      spacing: spacing,
      bulletGap: bulletGap,
    );
    final columnW = layout.columnW;
    // A split run shares one size: cap at the run's shared scale (see
    // _bulletsContent). `min` keeps it safe — never larger than what fits here.
    final columnScale = fitScaleOverride != null
        ? math.min(fitScaleOverride!, layout.columnScale)
        : layout.columnScale;
    final maxHeadingH = layout.maxHeadingH;

    return Column(
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
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
                color: AppTheme.parseHexColor(profile.textColor),
              ),
            ),
            linkColor: AppTheme.parseHexColor(profile.accentColor),
            position: splitRunPosition,
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
  }

  ({double columnW, double columnScale, double maxHeadingH}) _twoBulletsScale(
    double contentW,
    double layoutH, {
    required double columnGap,
    required bool hasTitle,
    required double titleSize,
    required String col1Title,
    required String col2Title,
    required double headingSize,
    required bool hasColumnTitles,
    required double headingGap,
    required List<String> leftBullets,
    required List<String> rightBullets,
    required double bulletSize,
    required double spacing,
    required double bulletGap,
  }) {
    return memoizedRenderLayout(
      slide: slide,
      font: font,
      width: w,
      availW: contentW,
      availH: layoutH,
      compute: () {
        // `w * 0.12` is de ondergrens en `w` de bovengrens; die verhouding
        // klopt altijd, maar bij `w == 0` vallen ze samen op nul en levert dit
        // een breedte 0 op in plaats van een uitzondering. Ondergrens ten
        // minste 1 zodat de meting hieronder een geldige breedte krijgt.
        final columnW = math.max(
          1.0,
          ((contentW - columnGap) / 2)
              .clamp(math.min(w * 0.12, w), w)
              .toDouble(),
        );
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
        return (
          columnW: columnW,
          columnScale: columnScale,
          maxHeadingH: maxHeadingH,
        );
      },
    );
  }
}
