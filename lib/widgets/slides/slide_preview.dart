import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import 'inline_markdown.dart';

/// Returns a TextStyle with the correct font, using GoogleFonts for web fonts.
TextStyle _applyFont(String font, TextStyle base) {
  if (font == 'EB Garamond') return GoogleFonts.ebGaramond(textStyle: base);
  return base.copyWith(fontFamily: font);
}

/// Geeft de link-tap-handler door aan alle tekst in een slide, zonder die door
/// elke sub-widget heen te hoeven sleuren. Draagt ook of er een TLP-markering
/// rechtsonder staat, zodat bijschriften daarboven uitwijken.
class _SlideLinkScope extends InheritedWidget {
  final void Function(String url)? onTapLink;
  final bool hasBottomTlp;
  const _SlideLinkScope({
    required this.onTapLink,
    this.hasBottomTlp = false,
    required super.child,
  });

  static void Function(String url)? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SlideLinkScope>()
        ?.onTapLink;
  }

  static bool hasBottomTlpOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SlideLinkScope>()
            ?.hasBottomTlp ??
        false;
  }

  @override
  bool updateShouldNotify(_SlideLinkScope oldWidget) =>
      oldWidget.onTapLink != onTapLink ||
      oldWidget.hasBottomTlp != hasBottomTlp;
}

/// Tekst met inline-markdown (**vet**, *cursief*, `code`, ~~door~~, [link](url)).
/// Vervangt platte [Text] op alle inhoudsplekken van een slide.
Widget _md(
  BuildContext context,
  String text,
  TextStyle style, {
  required Color linkColor,
  int? maxLines,
  TextAlign textAlign = TextAlign.start,
  TextOverflow overflow = TextOverflow.clip,
  bool softWrap = true,
}) {
  return InlineMarkdownText(
    text,
    style: style,
    linkColor: linkColor,
    onTapLink: _SlideLinkScope.of(context),
    maxLines: maxLines,
    textAlign: textAlign,
    overflow: overflow,
    softWrap: softWrap,
  );
}

Color _hexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(
    cleaned.length == 6 ? 'FF$cleaned' : cleaned,
    radix: 16,
  );
  return Color(value ?? 0xFFFFFFFF);
}

EdgeInsets _logoSafeInsets(double w, ThemeProfile profile) {
  if (profile.logoPath?.isEmpty ?? true) return EdgeInsets.zero;
  final reserved = w * ((profile.logoSize + 64) / 1280);
  if (profile.logoPosition.startsWith('top')) {
    return EdgeInsets.only(top: reserved);
  }
  return EdgeInsets.only(bottom: reserved);
}

EdgeInsets _splitTextLogoSafeInsets(double w, ThemeProfile profile) {
  if (profile.logoPath?.isEmpty ?? true) return EdgeInsets.zero;
  if (profile.logoPosition.endsWith('right')) return EdgeInsets.zero;
  final reserved = w * ((profile.logoSize + 24) / 1280);
  if (profile.logoPosition.startsWith('top')) {
    return EdgeInsets.only(top: reserved);
  }
  return EdgeInsets.only(bottom: reserved);
}

/// Renders a visual approximation of a Marp slide inside a 16:9 container.
/// All font sizes and paddings are proportional to the widget width so the
/// same widget works both as the full preview pane and as a tiny thumbnail.
/// Content that exceeds the slide height is scaled down proportionally via
/// FittedBox rather than clipped.
class SlidePreviewWidget extends StatelessWidget {
  final Slide slide;
  final String? projectPath;
  final ThemeProfile themeProfile;

  /// Het lettertype hoort bij de stijl (themeProfile), niet bij de app.
  String get fontFamily => themeProfile.fontFamily;

  /// Optioneel: maakt links in de tekst klikbaar (preview/presenter). In
  /// thumbnails en bij export blijft dit null → links zijn alleen gestyled.
  final void Function(String url)? onLinkTap;

  /// 1-gebaseerd slidenummer en totaal, voor footer-paginanummers en de
  /// {page}/{total}-tokens. Null → geen paginanummers.
  final int? slideNumber;
  final int? slideCount;

  /// TLP-classificatie van de presentatie; getoond als markering op de slide.
  final TlpLevel tlp;

  /// Of audio/video op deze slide afgespeeld kan worden (de audioknop verschijnt
  /// en video kan starten). Standaard uit — thumbnails en export spelen niets.
  final bool enableMedia;

  /// Of media automatisch start (audio-/video-autoplay). In de editor-preview
  /// staat dit uit (handmatig starten); in de presenter aan.
  final bool autoplayMedia;

  /// Wordt aangeroepen wanneer de audio van deze slide klaar is (voor de
  /// automatische modus van de presenter).
  final VoidCallback? onAudioComplete;

  const SlidePreviewWidget({
    super.key,
    required this.slide,
    this.projectPath,
    this.themeProfile = const ThemeProfile(),
    this.onLinkTap,
    this.slideNumber,
    this.slideCount,
    this.tlp = TlpLevel.none,
    this.enableMedia = false,
    this.autoplayMedia = false,
    this.onAudioComplete,
  });

  @override
  Widget build(BuildContext context) {
    // Make the widget self-sufficient for text rendering. On screen it sits
    // inside a Material (which supplies a clean DefaultTextStyle), but the
    // export rasterizer mounts it in a bare Overlay subtree. Without an
    // explicit DefaultTextStyle there, any Text that doesn't set its own color
    // falls back to Flutter's broken default — red letters with a yellow
    // underline — which is exactly what showed up in exports. Wrapping here
    // guarantees identical results in the preview and the export.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          color: _hexColor(themeProfile.textColor),
          decoration: TextDecoration.none,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
        ),
        child: _SlideLinkScope(
          onTapLink: onLinkTap,
          hasBottomTlp: tlp != TlpLevel.none,
          child: _buildSlide(),
        ),
      ),
    );
  }

  Widget _buildSlide() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildContent(w),
                _FooterOverlay(
                  slide: slide,
                  w: w,
                  profile: themeProfile,
                  slideNumber: slideNumber,
                  slideCount: slideCount,
                  tlp: tlp,
                ),
                if (tlp != TlpLevel.none)
                  _TlpOverlay(tlp: tlp, w: w, profile: themeProfile),
                if (themeProfile.logoPath?.isNotEmpty == true && slide.showLogo)
                  _LogoOverlay(
                    logoPath: themeProfile.logoPath!,
                    projectPath: projectPath,
                    position: themeProfile.logoPosition,
                    size: w * (themeProfile.logoSize / 1280),
                  ),
                if (enableMedia && slide.audioPath.isNotEmpty)
                  _AudioPlayback(
                    audioPath: slide.audioPath,
                    projectPath: projectPath,
                    autoplay: autoplayMedia && slide.audioAutoplay,
                    onComplete: onAudioComplete,
                    w: w,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(double w) {
    switch (slide.type) {
      case SlideType.title:
        return _TitlePreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.section:
        return _SectionPreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.bullets:
        return _BulletsPreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.twoBullets:
        return _TwoBulletsPreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.bulletsImage:
        return _BulletsImagePreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.twoImages:
        return _TwoImagesPreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.image:
        return _ImagePreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.video:
        return _VideoPreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
          autoplay: autoplayMedia && slide.videoAutoplay,
        );
      case SlideType.quote:
        return _QuotePreview(
          slide: slide,
          w: w,
          font: fontFamily,
          projectPath: projectPath,
          profile: themeProfile,
        );
      case SlideType.table:
        return _TablePreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.freeMarkdown:
        return _MarkdownPreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
        );
    }
  }
}

class _AudioPlayback extends StatefulWidget {
  final String audioPath;
  final String? projectPath;
  final bool autoplay;
  final double w;
  final VoidCallback? onComplete;

  const _AudioPlayback({
    required this.audioPath,
    required this.projectPath,
    required this.autoplay,
    required this.w,
    this.onComplete,
  });

  @override
  State<_AudioPlayback> createState() => _AudioPlaybackState();
}

class _AudioPlaybackState extends State<_AudioPlayback> {
  VideoPlayerController? _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_AudioPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath != widget.audioPath ||
        oldWidget.autoplay != widget.autoplay) {
      _init();
    }
  }

  Future<void> _init() async {
    _controller?.removeListener(_onTick);
    await _controller?.dispose();
    _completed = false;
    final path = _resolvePath(widget.audioPath, widget.projectPath);
    if (path == null) return;
    final controller = VideoPlayerController.file(File(path));
    _controller = controller;
    try {
      await controller.initialize();
      controller.addListener(_onTick);
      if (widget.autoplay) await controller.play();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// Detecteer het einde van de audio en meld dat één keer (voor auto-advance).
  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _completed) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur > Duration.zero &&
        pos.inMilliseconds >= dur.inMilliseconds - 200 &&
        !c.value.isPlaying) {
      _completed = true;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Positioned(
      right: widget.w * 0.035,
      bottom: widget.w * 0.035,
      child: IconButton(
        tooltip: 'Audio',
        onPressed: controller == null || !controller.value.isInitialized
            ? null
            : () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
        icon: Icon(
          controller?.value.isPlaying == true
              ? Icons.volume_up
              : Icons.volume_up_outlined,
        ),
        iconSize: widget.w * 0.032,
      ),
    );
  }
}

// ── Individual slide-type renderers ──────────────────────────────────────────

class _TitlePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  const _TitlePreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
  });

  Widget _content(BuildContext context) {
    final pad = w * 0.08;
    final link = _hexColor(profile.accentColor);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: SizedBox(
        width: w,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (slide.title.isNotEmpty)
                _md(
                  context,
                  slide.title,
                  _applyFont(
                    font,
                    TextStyle(
                      color: _hexColor(profile.titleTextColor),
                      fontSize: w * 0.055,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  linkColor: link,
                ),
              if (slide.subtitle.isNotEmpty) ...[
                SizedBox(height: w * 0.02),
                _md(
                  context,
                  slide.subtitle,
                  _applyFont(
                    font,
                    TextStyle(
                      color: _hexColor(
                        profile.titleTextColor,
                      ).withValues(alpha: 0.72),
                      fontSize: w * 0.03,
                      height: 1.3,
                    ),
                  ),
                  linkColor: link,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBg = slide.imagePath.isNotEmpty;

    if (!hasBg) {
      return Container(
        color: _hexColor(profile.titleBackgroundColor),
        child: SizedBox.expand(child: _content(context)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomedImage(
          slide.imagePath,
          projectPath,
          slide.imageSize,
          bgColor: _hexColor(profile.titleBackgroundColor),
        ),
        Container(
          color: _hexColor(
            profile.titleBackgroundColor,
          ).withValues(alpha: 0.62),
        ),
        _content(context),
        _captionOverlay(context, slide.imageCaption, w),
      ],
    );
  }
}

class _SectionPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _SectionPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.08;
    return Container(
      color: _hexColor(profile.sectionBackgroundColor),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (slide.title.isNotEmpty)
                    _md(
                      context,
                      slide.title,
                      _applyFont(
                        font,
                        TextStyle(
                          color: _hexColor(profile.titleTextColor),
                          fontSize: w * 0.05,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
                  if (slide.subtitle.isNotEmpty) ...[
                    SizedBox(height: w * 0.015),
                    _md(
                      context,
                      slide.subtitle,
                      _applyFont(
                        font,
                        TextStyle(
                          color: _hexColor(
                            profile.titleTextColor,
                          ).withValues(alpha: 0.72),
                          fontSize: w * 0.025,
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final titleSize = w * 0.042;
    final bulletSize = w * 0.026;
    final spacing = pad * 0.5;
    final bulletGap = w * 0.006;
    final bullets = slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final hasTitle = slide.title.isNotEmpty;

    final slideHeight = w * 9 / 16;
    final availW = (w - pad * 2).clamp(w * 0.12, w);
    final availH = slideHeight - (pad + safe.top) - (pad + safe.bottom);
    // Grow (or, when needed, shrink) the text so it uses the full vertical
    // space instead of leaving a large empty area below a few short bullets.
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
      maxScale: _kSplitBulletsMaxScale,
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
                pad + safe.top,
                pad,
                pad + safe.bottom,
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
                  if (hasTitle && bullets.isNotEmpty)
                    SizedBox(height: spacing * scale),
                  ...bullets.map((b) {
                    int level = 0;
                    while (level < b.length && b[level] == '\t') {
                      level++;
                    }
                    final text = b.substring(level);
                    final fontSize =
                        bulletSize * _bulletLevelScale(level) * scale;
                    return Padding(
                      padding: EdgeInsets.only(
                        left: level * bulletSize * 1.05 * scale,
                        top: bulletGap * scale,
                        bottom: bulletGap * scale,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_bulletMarkerForLevel(level)} ',
                            style: TextStyle(
                              fontSize: fontSize,
                              color: _hexColor(profile.accentColor),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: _md(
                              context,
                              text,
                              _applyFont(
                                font,
                                TextStyle(
                                  fontSize: fontSize,
                                  height: _kBulletLineHeight,
                                  color: _hexColor(profile.textColor),
                                ),
                              ),
                              linkColor: _hexColor(profile.accentColor),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TablePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _TablePreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.06;
    final safe = slide.showLogo
        ? _splitTextLogoSafeInsets(w, profile)
        : EdgeInsets.zero;
    final titleSize = w * 0.038;
    final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    // Scale cell text down as the table grows so it keeps fitting nicely.
    final density = (rows.length + colCount).clamp(2, 24);
    final cellSize = (w * 0.025 * (10 / (density + 6))).clamp(
      w * 0.010,
      w * 0.021,
    );

    final accent = _hexColor(profile.accentColor);
    final textColor = _hexColor(profile.tableTextColor);
    final headerTextColor = _hexColor(profile.tableHeaderTextColor);
    final borderColor = accent.withValues(alpha: 0.35);

    Widget cell(String value, {required bool header}) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: cellSize * 0.55,
          vertical: cellSize * 0.36,
        ),
        child: _md(
          context,
          value,
          _applyFont(
            font,
            TextStyle(
              fontSize: cellSize,
              color: header ? headerTextColor : textColor,
              fontWeight: header ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          linkColor: header ? headerTextColor : accent,
        ),
      );
    }

    TableRow buildRow(List<String> row, {required bool header}) {
      return TableRow(
        decoration: BoxDecoration(color: header ? accent : null),
        children: List.generate(colCount, (c) {
          final value = c < row.length ? row[c] : '';
          return TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: cell(value, header: header),
          );
        }),
      );
    }

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: w,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              pad,
              pad + safe.top,
              pad,
              pad + safe.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (slide.title.isNotEmpty) ...[
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
                  SizedBox(height: pad * 0.35),
                ],
                if (rows.isNotEmpty && colCount > 0)
                  Table(
                    border: TableBorder.all(
                      color: borderColor,
                      width: w * 0.0012,
                    ),
                    defaultColumnWidth: const FlexColumnWidth(),
                    children: [
                      buildRow(rows.first, header: true),
                      for (var i = 1; i < rows.length; i++)
                        buildRow(rows[i], header: false),
                    ],
                  ),
              ],
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

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.065;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final titleSize = w * 0.04;
    final bulletSize = w * 0.024;
    final spacing = pad * 0.38;
    final bulletGap = w * 0.0055;
    final columnGap = w * 0.055;
    final leftBullets = slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final rightBullets = slide.bullets2
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final hasTitle = slide.title.isNotEmpty;

    final slideHeight = w * 9 / 16;
    final contentW = (w - pad * 2).clamp(w * 0.12, w);
    final columnW = ((contentW - columnGap) / 2).clamp(w * 0.12, w);
    var availH = slideHeight - (pad + safe.top) - (pad + safe.bottom);
    if (hasTitle) {
      availH -= _measureTextHeight(
        slide.title,
        titleSize,
        contentW,
        bold: true,
      );
      availH -= spacing;
    }
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
      maxScale: _kBulletsMaxScale,
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
      maxScale: _kBulletsMaxScale,
    );
    final scale = leftScale < rightScale ? leftScale : rightScale;

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: SizedBox.expand(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            pad,
            pad + safe.top,
            pad,
            pad + safe.bottom,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: columnW,
                        child: _BulletListColumn(
                          bullets: leftBullets,
                          font: font,
                          profile: profile,
                          bulletSize: bulletSize,
                          bulletGap: bulletGap,
                          scale: scale,
                        ),
                      ),
                      SizedBox(width: columnGap),
                      SizedBox(
                        width: columnW,
                        child: _BulletListColumn(
                          bullets: rightBullets,
                          font: font,
                          profile: profile,
                          bulletSize: bulletSize,
                          bulletGap: bulletGap,
                          scale: scale,
                        ),
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
      maxScale: _kBulletsMaxScale,
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
                _resolvedImage(slide.imagePath, projectPath),
                _captionOverlay(
                  context,
                  slide.imageCaption,
                  w,
                  right: w * 0.018,
                ),
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
        ...bullets.map((b) {
          int level = 0;
          while (level < b.length && b[level] == '\t') {
            level++;
          }
          final text = b.substring(level);
          final fontSize = bulletSize * _bulletLevelScale(level) * scale;
          return Padding(
            padding: EdgeInsets.only(
              left: level * bulletSize * 1.05 * scale,
              top: bulletGap * scale,
              bottom: bulletGap * scale,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_bulletMarkerForLevel(level)} ',
                  style: TextStyle(
                    fontSize: fontSize,
                    color: _hexColor(profile.accentColor),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: _md(
                    context,
                    text,
                    _applyFont(
                      font,
                      TextStyle(
                        fontSize: fontSize,
                        height: _kBulletLineHeight,
                        color: _hexColor(profile.textColor),
                      ),
                    ),
                    linkColor: _hexColor(profile.accentColor),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _BulletListColumn extends StatelessWidget {
  final List<String> bullets;
  final String font;
  final ThemeProfile profile;
  final double bulletSize;
  final double bulletGap;
  final double scale;

  const _BulletListColumn({
    required this.bullets,
    required this.font,
    required this.profile,
    required this.bulletSize,
    required this.bulletGap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...bullets.map((b) {
          int level = 0;
          while (level < b.length && b[level] == '\t') {
            level++;
          }
          final text = b.substring(level);
          final fontSize = bulletSize * _bulletLevelScale(level) * scale;
          return Padding(
            padding: EdgeInsets.only(
              left: level * bulletSize * 1.05 * scale,
              top: bulletGap * scale,
              bottom: bulletGap * scale,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_bulletMarkerForLevel(level)} ',
                  style: TextStyle(
                    fontSize: fontSize,
                    color: _hexColor(profile.accentColor),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: _md(
                    context,
                    text,
                    _applyFont(
                      font,
                      TextStyle(
                        fontSize: fontSize,
                        height: _kBulletLineHeight,
                        color: _hexColor(profile.textColor),
                      ),
                    ),
                    linkColor: _hexColor(profile.accentColor),
                  ),
                ),
              ],
            ),
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

/// Line height used for bullet body text, shared by rendering and measuring.
const double _kBulletLineHeight = 1.16;

String _bulletMarkerForLevel(int level) {
  const markers = ['•', '◦', '▪', '▫', '–'];
  return markers[level.clamp(0, markers.length - 1)];
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
  double minScale = 0.2,
  double maxScale = 1.0,
}) {
  if (availW <= 0 || !availH.isFinite || availH <= 0) return 1.0;
  // 2% safety margin so minor measurement differences never overflow.
  final budget = availH * 0.98;
  double measure(double scale) => _bulletsBlockHeight(
    scale: scale,
    availW: availW,
    hasTitle: hasTitle,
    title: title,
    bullets: bullets,
    titleSize: titleSize,
    bulletSize: bulletSize,
    spacing: spacing,
    bulletGap: bulletGap,
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
}) {
  var height = 0.0;
  if (hasTitle) {
    height += _measureTextHeight(title, titleSize * scale, availW, bold: true);
  }
  if (hasTitle && bullets.isNotEmpty) height += spacing * scale;
  for (final b in bullets) {
    int level = 0;
    while (level < b.length && b[level] == '\t') {
      level++;
    }
    final text = b.substring(level);
    final fontSize = bulletSize * _bulletLevelScale(level) * scale;
    final indent = level * bulletSize * 1.05 * scale;
    final marker = '${_bulletMarkerForLevel(level)} ';
    final markerW = _measureTextWidth(marker, fontSize, bold: true);
    final wrapW = (availW - indent - markerW).clamp(1.0, availW);
    final textH = _measureTextHeight(
      text,
      fontSize,
      wrapW,
      lineHeight: _kBulletLineHeight,
    );
    final markerH = _measureTextHeight(marker, fontSize, double.infinity);
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
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: stripInlineMarkdown(text),
      style: TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);
  return painter.height;
}

double _measureTextWidth(String text, double fontSize, {bool bold = false}) {
  final painter = TextPainter(
    text: TextSpan(
      text: stripInlineMarkdown(text),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

class _TwoImagesPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  const _TwoImagesPreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final splitFraction = (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.5)
        .clamp(0.1, 0.9);
    final leftW = w * splitFraction;
    final rightW = w * (1 - splitFraction);
    final titleSize = w * 0.032;

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Twee afbeeldingen naast elkaar
          Row(
            children: [
              SizedBox(
                width: leftW,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _resolvedImage(slide.imagePath, projectPath),
                    _captionOverlay(context, slide.imageCaption, w),
                  ],
                ),
              ),
              SizedBox(
                width: rightW,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _resolvedImage(slide.imagePath2, projectPath),
                    _captionOverlay(context, slide.imageCaption2, w),
                  ],
                ),
              ),
            ],
          ),
          // Optionele ondertitel
          if (slide.title.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: w * 0.04,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.04,
                  vertical: w * 0.015,
                ),
                child: _md(
                  context,
                  slide.title,
                  _applyFont(
                    font,
                    TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  linkColor: const Color(0xFF8BB8FF),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  const _ImagePreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final hasTitle = slide.title.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomedImage(
          slide.imagePath,
          projectPath,
          slide.imageSize,
          bgColor: _hexColor(profile.slideBackgroundColor),
          // When zoomed out, anchor the image to the top so the bottom title
          // banner sits in the freed-up space instead of over the picture.
          alignment: hasTitle ? Alignment.topCenter : Alignment.center,
        ),
        if (slide.title.isNotEmpty)
          Positioned(
            left: w * 0.06,
            right: w * 0.06,
            bottom: w * 0.06,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.04,
                vertical: w * 0.02,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: _md(
                context,
                slide.title,
                _applyFont(
                  font,
                  TextStyle(
                    color: Colors.white,
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                linkColor: const Color(0xFF8BB8FF),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        _captionOverlay(context, slide.imageCaption, w),
      ],
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;
  final bool autoplay;

  const _VideoPreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.autoplay = false,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  String? _path;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.videoPath != widget.slide.videoPath ||
        oldWidget.autoplay != widget.autoplay) {
      _init();
    }
  }

  Future<void> _init() async {
    await _controller?.dispose();
    _controller = null;
    _path = _resolvePath(widget.slide.videoPath, widget.projectPath);
    if (_path == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(File(_path!));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(widget.autoplay);
      if (widget.autoplay) await controller.play();
    } catch (_) {
      // Keep the placeholder visible when the platform cannot open the file.
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      color: _hexColor(widget.profile.slideBackgroundColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else
            _mediaPlaceholder(Icons.movie_outlined, 'Video'),
          if (widget.slide.title.isNotEmpty)
            Positioned(
              left: widget.w * 0.06,
              right: widget.w * 0.06,
              top: widget.w * 0.04,
              child: _md(
                context,
                widget.slide.title,
                _applyFont(
                  widget.font,
                  TextStyle(
                    color: _hexColor(widget.profile.textColor),
                    fontSize: widget.w * 0.038,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                linkColor: _hexColor(widget.profile.accentColor),
              ),
            ),
          Positioned(
            left: widget.w * 0.04,
            bottom: widget.w * 0.035,
            child: IconButton(
              onPressed: controller == null || !controller.value.isInitialized
                  ? null
                  : () {
                      setState(() {
                        controller.value.isPlaying
                            ? controller.pause()
                            : controller.play();
                      });
                    },
              icon: Icon(
                controller?.value.isPlaying == true
                    ? Icons.pause_circle
                    : Icons.play_circle,
              ),
              iconSize: widget.w * 0.045,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final String? projectPath;
  final ThemeProfile profile;

  const _QuotePreview({
    required this.slide,
    required this.w,
    required this.font,
    this.projectPath,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.08;
    final hasBg = slide.imagePath.isNotEmpty;
    final textColor = hasBg ? Colors.white : _hexColor(profile.textColor);
    final authorColor = hasBg ? Colors.white70 : Colors.grey[600]!;
    final accentColor = hasBg ? Colors.white : _hexColor(profile.accentColor);

    final content = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: SizedBox(
        width: w,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: w * 0.008,
                    height: w * 0.12,
                    color: accentColor,
                    margin: EdgeInsets.only(right: pad * 0.4),
                  ),
                  Expanded(
                    child: _md(
                      context,
                      slide.quote.isEmpty ? '' : '"${slide.quote}"',
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.033,
                          fontStyle: FontStyle.italic,
                          color: textColor,
                          height: 1.4,
                        ),
                      ),
                      linkColor: accentColor,
                    ),
                  ),
                ],
              ),
              if (slide.quoteAuthor.isNotEmpty) ...[
                SizedBox(height: pad * 0.6),
                _md(
                  context,
                  '— ${slide.quoteAuthor}',
                  _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.026,
                      color: authorColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  linkColor: accentColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!hasBg) {
      return Container(
        color: _hexColor(profile.slideBackgroundColor),
        child: SizedBox.expand(child: content),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomedImage(
          slide.imagePath,
          projectPath,
          slide.imageSize,
          bgColor: _hexColor(profile.slideBackgroundColor),
        ),
        Container(color: Colors.black.withValues(alpha: 0.52)),
        content,
        _captionOverlay(context, slide.imageCaption, w),
      ],
    );
  }
}

class _LogoOverlay extends StatelessWidget {
  final String logoPath;
  final String? projectPath;
  final String position;
  final double size;

  const _LogoOverlay({
    required this.logoPath,
    required this.projectPath,
    required this.position,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalInset = size * 0.28;
    final topInset = size * 0.42;
    final bottomInset = size * 0.12;
    return Positioned(
      top: position.startsWith('top') ? topInset : null,
      bottom: position.startsWith('bottom') ? bottomInset : null,
      left: position.endsWith('left') ? horizontalInset : null,
      right: position.endsWith('right') ? horizontalInset : null,
      child: SizedBox(
        width: size,
        height: size,
        child: _resolvedImage(logoPath, projectPath, fit: BoxFit.contain),
      ),
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _MarkdownPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final lines = slide.customMarkdown.split('\n');

    return Container(
      color: Colors.white,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                pad + safe.top,
                pad,
                pad + safe.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: lines.take(20).map((line) {
                  final link = _hexColor(profile.accentColor);
                  if (line.startsWith('# ')) {
                    return _md(
                      context,
                      line.substring(2),
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.04,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.navy,
                        ),
                      ),
                      linkColor: link,
                    );
                  } else if (line.startsWith('## ')) {
                    return _md(
                      context,
                      line.substring(3),
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.03,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      linkColor: link,
                    );
                  } else if (line.startsWith('- ')) {
                    return _md(
                      context,
                      '• ${line.substring(2)}',
                      _applyFont(font, TextStyle(fontSize: w * 0.024)),
                      linkColor: link,
                    );
                  } else if (line.isEmpty) {
                    return SizedBox(height: w * 0.01);
                  }
                  return _md(
                    context,
                    line,
                    _applyFont(font, TextStyle(fontSize: w * 0.024)),
                    linkColor: link,
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared helper ─────────────────────────────────────────────────────────────

/// Rendert een afbeelding met zoomfactor op basis van BoxFit.contain.
///   imageSize = 0   → cover (Marp-standaard, vult frame, snijdt bij)
///   imageSize = 100 → volledige afbeelding zichtbaar (contain, evt. randen)
///   imageSize > 100 → inzoomen: groter dan contain, bijgesneden door ClipRect
///   imageSize < 100 → nog meer uitzoomen: afbeelding kleiner dan contain
Widget _zoomedImage(
  String imagePath,
  String? projectPath,
  int imageSize, {
  Color bgColor = Colors.black,
  Alignment alignment = Alignment.center,
}) {
  if (imageSize == 0) {
    return _resolvedImage(imagePath, projectPath); // BoxFit.cover standaard
  }
  final scale = imageSize / 100.0;
  // Size the image box to `scale` × the available area and let BoxFit.contain
  // fit the picture inside it. This produces the same visual result as a
  // Transform.scale but without a transform layer, which `RepaintBoundary
  // .toImage` (used for exports) captures far more reliably — a scaled
  // transform layer would frequently render blank in the exported PNG.
  return ClipRect(
    child: ColoredBox(
      color: bgColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxW = constraints.maxWidth * scale;
          final boxH = constraints.maxHeight * scale;
          return Align(
            alignment: alignment,
            child: SizedBox(
              width: boxW,
              height: boxH,
              // BoxFit.contain: toont de volledige afbeelding zonder bijsnijden
              child: _resolvedImage(
                imagePath,
                projectPath,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _resolvedImage(
  String imagePath,
  String? projectPath, {
  BoxFit fit = BoxFit.cover,
}) {
  if (imagePath.isEmpty) return _imagePlaceholder();

  final String resolved;
  if (imagePath.startsWith('/') || imagePath.contains(':\\')) {
    resolved = imagePath;
  } else if (projectPath != null) {
    resolved = '$projectPath/$imagePath';
  } else {
    resolved = imagePath;
  }

  return Image.file(
    File(resolved),
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
  );
}

Widget _captionOverlay(
  BuildContext context,
  String caption,
  double w, {
  double? right,
  double? bottom,
}) {
  final text = caption.trim();
  if (text.isEmpty) return const SizedBox.shrink();
  // Een copyright/bijschrift staat rechtsonder; als daar een TLP-markering
  // staat, schuift het bijschrift erboven zodat het niet wordt overschreven.
  final lift = _SlideLinkScope.hasBottomTlpOf(context)
      ? _tlpVerticalReserve(w)
      : 0.0;
  return Positioned(
    right: right ?? w * 0.018,
    bottom: (bottom ?? w * 0.014) + lift,
    child: Container(
      constraints: BoxConstraints(maxWidth: w * 0.5),
      padding: EdgeInsets.symmetric(horizontal: w * 0.008, vertical: w * 0.005),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.011,
          height: 1.25,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

String? _resolvePath(String path, String? projectPath) {
  if (path.isEmpty) return null;
  if (path.startsWith('/') || path.contains(':\\')) return path;
  if (projectPath != null) return '$projectPath/$path';
  return path;
}

// ── TLP-markering: maten gedeeld door de badge en de footer-uitsparing ──────
const double _kTlpFont = 0.018; // × slidebreedte
const double _kTlpEdge = 0.025; // afstand tot de slidehoek (× breedte)
const double _kTlpHPad = 0.011;
const double _kTlpVPad = 0.005;

/// Geschatte breedte van de TLP-badge, zodat de footer ervoor kan uitwijken.
double _tlpBadgeWidth(double w, TlpLevel tlp) =>
    tlp.label.length * w * _kTlpFont * 0.62 + 2 * (w * _kTlpHPad);

/// Verticale ruimte die een TLP-badge rechtsonder inneemt (voor bijschriften).
double _tlpVerticalReserve(double w) =>
    w * _kTlpFont + 2 * (w * _kTlpVPad) + w * 0.014;

/// Officiële TLP 2.0-markering (FIRST): de gekleurde label op een zwart vlak,
/// rechtsonder. Wijkt uit naar linksonder als het logo rechtsonder staat.
class _TlpOverlay extends StatelessWidget {
  final TlpLevel tlp;
  final double w;
  final ThemeProfile profile;

  const _TlpOverlay({
    required this.tlp,
    required this.w,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final toLeft = profile.logoPosition == 'bottom-right';
    return Positioned(
      bottom: w * 0.022,
      left: toLeft ? w * _kTlpEdge : null,
      right: toLeft ? null : w * _kTlpEdge,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * _kTlpHPad,
          vertical: w * _kTlpVPad,
        ),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(w * 0.005),
        ),
        child: Text(
          tlp.label,
          style: TextStyle(
            color: Color(tlp.foreground),
            fontSize: w * _kTlpFont,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Footer onderaan een slide: vrije tekst (links) + paginanummers (rechts),
/// op basis van het stijlprofiel. Verborgen op titel-/sectieslides (daar is
/// een footer ongebruikelijk en valt 'ie weg tegen de donkere achtergrond).
/// Linkermarge waar de inhoud (bullets/tekst) van een slide begint. Wordt
/// gebruikt om een links-uitgelijnde footer ermee te laten uitlijnen, zodat het
/// geheel consistenter oogt. Moet overeenkomen met de `pad`-waarden van de
/// afzonderlijke slide-renderers hierboven.
double _contentLeftInset(Slide slide, double w) {
  switch (slide.type) {
    case SlideType.bullets:
    case SlideType.freeMarkdown:
      return w * 0.07;
    case SlideType.twoBullets:
      return w * 0.065;
    case SlideType.table:
      return w * 0.06;
    case SlideType.bulletsImage:
      return w * 0.038;
    case SlideType.quote:
      return w * 0.08;
    default:
      // Beeld/video: geen tekstmarge om mee uit te lijnen.
      return w * 0.04;
  }
}

class _FooterOverlay extends StatelessWidget {
  final Slide slide;
  final double w;
  final ThemeProfile profile;
  final int? slideNumber;
  final int? slideCount;
  final TlpLevel tlp;

  const _FooterOverlay({
    required this.slide,
    required this.w,
    required this.profile,
    this.slideNumber,
    this.slideCount,
    this.tlp = TlpLevel.none,
  });

  String _applyTokens(String s) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(now.day)}-${two(now.month)}-${now.year}';
    return s
        .replaceAll('{page}', slideNumber?.toString() ?? '')
        .replaceAll('{total}', slideCount?.toString() ?? '')
        .replaceAll('{date}', date)
        .replaceAll('{title}', slide.title);
  }

  @override
  Widget build(BuildContext context) {
    if (!slide.showFooter) return const SizedBox.shrink();
    if (slide.type == SlideType.title || slide.type == SlideType.section) {
      return const SizedBox.shrink();
    }

    final footerText = _applyTokens(profile.footerText).trim();
    final showPages = profile.footerShowPageNumbers && slideNumber != null;
    if (footerText.isEmpty && !showPages) return const SizedBox.shrink();

    // Iets kleiner dan voorheen, zodat 'ie niet tegen het logo aan drukt.
    final fontSize = w * 0.0145;
    final style = TextStyle(
      color: _hexColor(profile.textColor).withValues(alpha: 0.7),
      fontSize: fontSize,
      // Lichte schaduw zodat de footer ook over een afbeelding leesbaar blijft.
      shadows: [
        Shadow(
          color: Colors.white.withValues(alpha: 0.5),
          blurRadius: w * 0.003,
        ),
      ],
    );

    // Onderhoeken vrijhouden: de footer wijkt horizontaal uit voor het logo en
    // de TLP-badge, zodat ze netjes uitlijnen i.p.v. over elkaar te vallen.
    double mx(double a, double b) => a > b ? a : b;
    final hasLogo = profile.logoPath?.isNotEmpty == true && slide.showLogo;
    final logoBottom = hasLogo && profile.logoPosition.startsWith('bottom');
    final logoOnLeft = profile.logoPosition.endsWith('left');
    final logoSpan = w * (profile.logoSize / 1280) * 1.28 + w * 0.012;
    final logoLeftEdge = w * (profile.logoSize / 1280) * 0.28;
    final tlpOnRight = profile.logoPosition != 'bottom-right';
    final tlpSpan = tlp == TlpLevel.none
        ? 0.0
        : w * _kTlpEdge + _tlpBadgeWidth(w, tlp) + w * 0.012;
    final footerLeftAligned = profile.footerPosition == 'left';

    // Links uitgelijnd begint de footer waar het logo of de bullets beginnen,
    // voor een consistente linkermarge. Anders de standaardmarge.
    var left = footerLeftAligned
        ? (logoBottom && logoOnLeft
              ? logoLeftEdge
              : _contentLeftInset(slide, w))
        : w * 0.04;
    var right = w * 0.04;
    if (logoBottom) {
      if (logoOnLeft) {
        // Een links-uitgelijnde footer mag bewust met de logo-linkerkant
        // uitlijnen; anders schuift 'ie rechts van het logo om overlap te
        // voorkomen.
        if (!footerLeftAligned) left = mx(left, logoSpan);
      } else {
        right = mx(right, logoSpan);
      }
    }
    if (tlp != TlpLevel.none) {
      if (tlpOnRight) {
        right = mx(right, tlpSpan);
      } else {
        left = mx(left, tlpSpan);
      }
    }

    final alignment = switch (profile.footerPosition) {
      'left' => Alignment.centerLeft,
      'center' => Alignment.center,
      _ => Alignment.centerRight,
    };
    final textAlign = switch (profile.footerPosition) {
      'left' => TextAlign.left,
      'center' => TextAlign.center,
      _ => TextAlign.right,
    };

    return Positioned(
      left: left,
      right: right,
      bottom: w * 0.02,
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: w - left - right),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (footerText.isNotEmpty)
                Flexible(
                  child: Text(
                    footerText,
                    style: style,
                    textAlign: textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (footerText.isNotEmpty && showPages) SizedBox(width: w * 0.02),
              if (showPages)
                Text(
                  '$slideNumber / ${slideCount ?? slideNumber}',
                  style: style,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _mediaPlaceholder(IconData icon, String label) {
  return Container(
    color: const Color(0xFFE2E8F0),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF94A3B8), size: 32),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

Widget _imagePlaceholder() {
  return Container(
    color: const Color(0xFFE2E8F0),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: Color(0xFF94A3B8), size: 24),
          SizedBox(height: 4),
          Text(
            'Afbeelding',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
          ),
        ],
      ),
    ),
  );
}
