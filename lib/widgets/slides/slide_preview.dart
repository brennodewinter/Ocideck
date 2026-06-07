import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:video_player/video_player.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import 'inline_markdown.dart';

/// Returns a TextStyle with the correct font. 'EB Garamond' is bundled with the
/// app (see pubspec.yaml); all other fonts resolve to system families.
TextStyle _applyFont(String font, TextStyle base) {
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
    final hasBottomRightTlp =
        tlp != TlpLevel.none &&
        !((themeProfile.logoPath?.isNotEmpty == true && slide.showLogo) &&
            themeProfile.logoPosition == 'bottom-right');
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
          hasBottomTlp: hasBottomRightTlp,
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
                  _TlpOverlay(
                    tlp: tlp,
                    w: w,
                    profile: themeProfile,
                    hasLogo:
                        themeProfile.logoPath?.isNotEmpty == true &&
                        slide.showLogo,
                  ),
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
      case SlideType.code:
        return _CodePreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.chart:
        return _ChartPreview(
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
          context,
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
                    _resolvedImage(context, slide.imagePath, projectPath),
                    _captionOverlay(context, slide.imageCaption, w),
                  ],
                ),
              ),
              SizedBox(
                width: rightW,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _resolvedImage(context, slide.imagePath2, projectPath),
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
          context,
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
          context,
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
        child: _resolvedImage(
          context,
          logoPath,
          projectPath,
          fit: BoxFit.contain,
        ),
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
                children: _buildBlocks(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Parse the free Markdown into block widgets: fenced ```code``` (syntax
  /// highlighted), `$$…$$` display math, and ordinary heading/bullet/text lines.
  List<Widget> _buildBlocks(BuildContext context) {
    final link = _hexColor(profile.accentColor);
    final lines = slide.customMarkdown.split('\n');
    final widgets = <Widget>[];
    var i = 0;
    // Cap rendered blocks so a huge slide can't blow up layout (the preview is a
    // thumbnail; FittedBox scales the rest down).
    while (i < lines.length && widgets.length < 24) {
      final line = lines[i];

      // Fenced code block: ``` or ```language … ```
      final fence = RegExp(r'^\s*```(.*)$').firstMatch(line);
      if (fence != null) {
        final language = fence.group(1)!.trim();
        final code = <String>[];
        i++;
        while (i < lines.length && !RegExp(r'^\s*```\s*$').hasMatch(lines[i])) {
          code.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // consume the closing fence
        widgets.add(_codeBlock(code.join('\n'), language));
        continue;
      }

      // Display math fenced by lines containing only `$$`.
      if (line.trim() == r'$$') {
        final tex = <String>[];
        i++;
        while (i < lines.length && lines[i].trim() != r'$$') {
          tex.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // consume the closing $$
        widgets.add(_mathBlock(tex.join('\n')));
        continue;
      }
      // Single-line display math: $$ … $$
      final oneLine = RegExp(r'^\s*\$\$(.+)\$\$\s*$').firstMatch(line);
      if (oneLine != null) {
        widgets.add(_mathBlock(oneLine.group(1)!.trim()));
        i++;
        continue;
      }

      widgets.add(_textLine(context, line, link));
      i++;
    }
    return widgets;
  }

  Widget _textLine(BuildContext context, String line, Color link) {
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
          TextStyle(fontSize: w * 0.03, fontWeight: FontWeight.w600),
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
  }

  Widget _codeBlock(String code, String language) {
    _ensureHighlightLanguages();
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: w * 0.02,
      height: 1.3,
      color: const Color(0xFF24292E),
    );
    // HighlightView throws on an unregistered language, so only use it for ones
    // we actually know; otherwise fall back to plain monospace.
    final known = language.isNotEmpty && allLanguages.containsKey(language);
    final Widget content = known
        ? HighlightView(
            code,
            language: language,
            theme: githubTheme,
            padding: EdgeInsets.zero,
            textStyle: mono,
          )
        : Text(code, style: mono);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: w * 0.008),
      padding: EdgeInsets.all(w * 0.018),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(w * 0.008),
        border: Border.all(color: const Color(0xFFE1E4E8)),
      ),
      child: content,
    );
  }

  Widget _mathBlock(String tex) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.012),
      child: Math.tex(
        tex,
        textStyle: _applyFont(font, TextStyle(fontSize: w * 0.032)),
        onErrorFallback: (err) => Text(
          '\$\$$tex\$\$',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: w * 0.022,
            color: Colors.red,
          ),
        ),
      ),
    );
  }
}

/// Een 'broncode-sheet': de code op een donker editor-vlak, met
/// syntaxkleuring wanneer een taal bekend is. De tekst blijft platte tekst maar
/// wordt monospace en gekleurd weergegeven. Past zich met een FittedBox aan de
/// slide aan zodat lange fragmenten netjes verkleinen i.p.v. af te kappen.
class _CodePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _CodePreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    _ensureHighlightLanguages();
    final pad = w * 0.05;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final code = slide.customMarkdown;
    final lang = slide.codeLanguage.trim();
    final known = lang.isNotEmpty && allLanguages.containsKey(lang);

    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: w * 0.024,
      height: 1.4,
      color: const Color(0xFFABB2BF), // atom-one-dark voorgrond
    );

    // HighlightView gooit een fout bij een onbekende taal; daarom vallen we
    // dan terug op platte (maar wel monospace) tekst.
    final Widget codeContent = known
        ? HighlightView(
            code,
            language: lang,
            theme: atomOneDarkTheme,
            padding: EdgeInsets.zero,
            textStyle: mono,
          )
        : Text(code, style: mono);

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          pad,
          pad + safe.top,
          pad,
          pad + safe.bottom,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF282C34), // atom-one-dark achtergrond
            borderRadius: BorderRadius.circular(w * 0.012),
            border: Border.all(color: const Color(0xFF3A3F4B)),
          ),
          padding: EdgeInsets.all(w * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (slide.title.isNotEmpty) ...[
                _md(
                  context,
                  slide.title,
                  _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.03,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFE5E7EB),
                    ),
                  ),
                  linkColor: _hexColor(profile.accentColor),
                ),
                SizedBox(height: w * 0.02),
              ],
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  // Een onbegrensde breedte laat code-regels op hun natuurlijke
                  // lengte staan (geen woordafbreking), waarna de FittedBox het
                  // geheel verkleint tot het past.
                  child: codeContent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a chart slide (bar/line/pie) from its ```chart JSON spec.
class _ChartPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ChartPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  static const _palette = <int>[
    0xFF2563EB,
    0xFFF59E0B,
    0xFF10B981,
    0xFFEF4444,
    0xFF8B5CF6,
    0xFF06B6D4,
    0xFFEC4899,
    0xFF84CC16,
  ];

  Color _seriesColor(int i) => i == 0
      ? _hexColor(profile.accentColor)
      : Color(_palette[i % _palette.length]);

  @override
  Widget build(BuildContext context) {
    final spec = ChartSpec.parse(slide.customMarkdown);
    final pad = w * 0.06;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final textColor = _hexColor(profile.textColor);

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          pad,
          pad + safe.top,
          pad,
          pad + safe.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (spec.title.isNotEmpty) ...[
              _md(
                context,
                spec.title,
                _applyFont(
                  font,
                  TextStyle(
                    fontSize: w * 0.04,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                linkColor: _hexColor(profile.accentColor),
              ),
              SizedBox(height: w * 0.02),
            ],
            if (spec.series.length > 1 && spec.type != ChartType.pie)
              _legend(spec, textColor),
            Expanded(
              child: spec.hasInlineData
                  ? _chart(spec, textColor)
                  : _placeholder(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(ChartSpec spec, Color textColor) {
    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.015),
      child: Wrap(
        spacing: w * 0.02,
        runSpacing: w * 0.008,
        children: [
          for (var i = 0; i < spec.series.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: w * 0.018,
                  height: w * 0.018,
                  decoration: BoxDecoration(
                    color: _seriesColor(i),
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: w * 0.008),
                Text(
                  spec.series[i].name,
                  style: _applyFont(
                    font,
                    TextStyle(fontSize: w * 0.02, color: textColor),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chart(ChartSpec spec, Color textColor) {
    switch (spec.type) {
      case ChartType.bar:
        return _barChart(spec, textColor);
      case ChartType.line:
        return _lineChart(spec, textColor);
      case ChartType.pie:
        return _pieChart(spec, textColor);
    }
  }

  double _maxY(ChartSpec spec) {
    var m = 0.0;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (v > m) m = v;
      }
    }
    return m <= 0 ? 1 : m * 1.15;
  }

  FlTitlesData _titles(ChartSpec spec, Color textColor) {
    final style = _applyFont(
      font,
      TextStyle(fontSize: w * 0.018, color: textColor.withValues(alpha: 0.8)),
    );
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: w * 0.06,
          getTitlesWidget: (value, meta) =>
              Text(_fmtNum(value), style: style.copyWith(fontSize: w * 0.016)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: w * 0.05,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            if (i < 0 || i >= spec.x.length) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(top: w * 0.008),
              child: Text(spec.x[i], style: style),
            );
          },
        ),
      ),
    );
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  FlGridData _grid(Color textColor) => FlGridData(
    show: true,
    drawVerticalLine: false,
    getDrawingHorizontalLine: (v) =>
        FlLine(color: textColor.withValues(alpha: 0.12), strokeWidth: 1),
  );

  Widget _barChart(ChartSpec spec, Color textColor) {
    final groups = <BarChartGroupData>[];
    for (var xi = 0; xi < spec.x.length; xi++) {
      groups.add(
        BarChartGroupData(
          x: xi,
          barRods: [
            for (var si = 0; si < spec.series.length; si++)
              if (xi < spec.series[si].data.length)
                BarChartRodData(
                  toY: spec.series[si].data[xi],
                  color: _seriesColor(si),
                  width: w * 0.012,
                  borderRadius: BorderRadius.circular(w * 0.003),
                ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        maxY: _maxY(spec),
        barGroups: groups,
        titlesData: _titles(spec, textColor),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
      ),
      duration: Duration.zero,
    );
  }

  Widget _lineChart(ChartSpec spec, Color textColor) {
    final bars = <LineChartBarData>[];
    for (var si = 0; si < spec.series.length; si++) {
      bars.add(
        LineChartBarData(
          spots: [
            for (var xi = 0; xi < spec.series[si].data.length; xi++)
              FlSpot(xi.toDouble(), spec.series[si].data[xi]),
          ],
          color: _seriesColor(si),
          barWidth: w * 0.004,
          isCurved: false,
          dotData: const FlDotData(show: true),
        ),
      );
    }
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: _maxY(spec),
        lineBarsData: bars,
        titlesData: _titles(spec, textColor),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
      ),
      duration: Duration.zero,
    );
  }

  Widget _pieChart(ChartSpec spec, Color textColor) {
    // A pie uses the first series; each slice is an x label.
    final series = spec.series.isNotEmpty ? spec.series.first : null;
    if (series == null) return _placeholderText('—');
    final total = series.data.fold<double>(0, (a, b) => a + b);
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < series.data.length; i++) {
      final v = series.data[i];
      final pct = total > 0 ? (v / total * 100) : 0;
      sections.add(
        PieChartSectionData(
          value: v,
          color: _seriesColor(i),
          title: '${pct.toStringAsFixed(0)}%',
          radius: w * 0.16,
          titleStyle: _applyFont(
            font,
            TextStyle(
              fontSize: w * 0.02,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 1,
              centerSpaceRadius: w * 0.05,
              pieTouchData: PieTouchData(enabled: false),
            ),
            duration: Duration.zero,
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < spec.x.length && i < series.data.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: w * 0.004),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: w * 0.018,
                        height: w * 0.018,
                        decoration: BoxDecoration(
                          color: _seriesColor(i),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: w * 0.008),
                      Flexible(
                        child: Text(
                          spec.x[i],
                          style: _applyFont(
                            font,
                            TextStyle(fontSize: w * 0.02, color: textColor),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder(BuildContext context) =>
      _placeholderText(context.l10n.d('Geen grafiekgegevens'));

  Widget _placeholderText(String text) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bar_chart_outlined,
          size: w * 0.08,
          color: const Color(0xFF94A3B8),
        ),
        SizedBox(height: w * 0.01),
        Text(
          text,
          style: TextStyle(color: const Color(0xFF94A3B8), fontSize: w * 0.02),
        ),
      ],
    ),
  );
}

/// Register highlight.js language definitions once, so [HighlightView] can
/// colour any common language without throwing.
bool _highlightReady = false;
void _ensureHighlightLanguages() {
  if (_highlightReady) return;
  allLanguages.forEach(highlight.registerLanguage);
  _highlightReady = true;
}

// ── Shared helper ─────────────────────────────────────────────────────────────

/// Rendert een afbeelding met zoomfactor op basis van BoxFit.contain.
///   imageSize = 0   → cover (Marp-standaard, vult frame, snijdt bij)
///   imageSize = 100 → volledige afbeelding zichtbaar (contain, evt. randen)
///   imageSize > 100 → inzoomen: groter dan contain, bijgesneden door ClipRect
///   imageSize < 100 → nog meer uitzoomen: afbeelding kleiner dan contain
Widget _zoomedImage(
  BuildContext context,
  String imagePath,
  String? projectPath,
  int imageSize, {
  Color bgColor = Colors.black,
  Alignment alignment = Alignment.center,
}) {
  if (imageSize == 0) {
    return _resolvedImage(
      context,
      imagePath,
      projectPath,
    ); // BoxFit.cover standaard
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
                context,
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
  BuildContext context,
  String imagePath,
  String? projectPath, {
  BoxFit fit = BoxFit.cover,
}) {
  if (imagePath.isEmpty) return _imagePlaceholder(context);

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
    // Keep showing the previous frame while the next image decodes. Without
    // this the widget paints nothing for a frame on a source change, which
    // shows up as a black flash between slides — fatal when recording video.
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) => _imagePlaceholder(context),
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
    right: right ?? w * _kTlpEdge,
    bottom: (bottom ?? _tlpBottomInset(w)) + lift,
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

String? _resolvePath(String path, String? projectPath) =>
    resolveSlideAssetPath(path, projectPath);

/// Resolves an image/media path the way the slide renderer does, so callers
/// (e.g. the presenter, to precache) can point at the exact file that will be
/// displayed. Returns null for an empty path.
String? resolveSlideAssetPath(String path, String? projectPath) {
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

double _tlpBottomInset(double w) => w * 0.022;

/// Geschatte breedte van de TLP-badge, zodat de footer ervoor kan uitwijken.
double _tlpBadgeWidth(double w, TlpLevel tlp) =>
    tlp.label.length * w * _kTlpFont * 0.62 + 2 * (w * _kTlpHPad);

/// Verticale ruimte die een TLP-badge rechtsonder inneemt (voor bijschriften).
double _tlpVerticalReserve(double w) =>
    w * _kTlpFont + 2 * (w * _kTlpVPad) + _tlpBottomInset(w);

/// Officiële TLP 2.0-markering (FIRST): de gekleurde label op een zwart vlak,
/// rechtsonder. Wijkt uit naar linksonder als het logo rechtsonder staat.
class _TlpOverlay extends StatelessWidget {
  final TlpLevel tlp;
  final double w;
  final ThemeProfile profile;
  final bool hasLogo;

  const _TlpOverlay({
    required this.tlp,
    required this.w,
    required this.profile,
    required this.hasLogo,
  });

  @override
  Widget build(BuildContext context) {
    final toLeft = hasLogo && profile.logoPosition == 'bottom-right';
    return Positioned(
      bottom: _tlpBottomInset(w),
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
    case SlideType.code:
      return w * 0.05;
    case SlideType.chart:
      return w * 0.06;
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
    final tlpOnRight = !(hasLogo && profile.logoPosition == 'bottom-right');
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

Widget _imagePlaceholder(BuildContext context) {
  return Container(
    color: const Color(0xFFE2E8F0),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, color: Color(0xFF94A3B8), size: 24),
          const SizedBox(height: 4),
          Text(
            context.l10n.d('Afbeelding'),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
          ),
        ],
      ),
    ),
  );
}
