import 'dart:io';
import 'dart:math' as math;

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
  // Reserve just enough to clear the logo plus a small margin (matching the
  // split-layout reserve). A larger margin needlessly shrinks the text area.
  final reserved = w * ((profile.logoSize + 24) / 1280);
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

  /// Vergroot grafieklabels voor weergave op afstand in presentatiemodus.
  final bool presentationMode;

  /// Wijzigt tijdens het presenteren een checklistitem. [column] is 0 voor de
  /// eerste/enkele lijst en 1 voor de rechterkolom.
  final void Function(int column, int itemIndex)? onChecklistItemToggle;

  /// Wordt aangeroepen wanneer de audio van deze slide klaar is (voor de
  /// automatische modus van de presenter).
  final VoidCallback? onAudioComplete;

  /// Wordt aangeroepen wanneer de video van deze slide klaar is.
  final VoidCallback? onVideoComplete;

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
    this.presentationMode = false,
    this.onChecklistItemToggle,
    this.onAudioComplete,
    this.onVideoComplete,
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
    // The slide is a fixed 16:9 design surface whose sizes all derive from
    // its width; interface text scaling must not reflow it (the auto-fit
    // measuring assumes unscaled text), so the canvas opts out.
    return MediaQuery.withNoTextScaling(
      child: _ChecklistInteractionHost(
        enabled: presentationMode && onChecklistItemToggle != null,
        onToggle: onChecklistItemToggle,
        child: Directionality(
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
          onComplete: onVideoComplete,
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
          presentationMode: presentationMode,
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

class _ChecklistProgress extends StatelessWidget {
  final List<String> bullets;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ChecklistProgress({
    required this.bullets,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final items = bullets
        .where((bullet) => checklistItemText(bullet).trim().isNotEmpty)
        .toList();
    final checked = items.where(checklistItemChecked).length;
    final total = items.length;
    final checkedPercent = total == 0 ? 0 : ((checked / total) * 100).round();
    final openPercent = total == 0 ? 0 : 100 - checkedPercent;
    final textColor = _hexColor(profile.textColor);
    final checkedColor = _hexColor(profile.checklistCheckedColor);
    final openColor = _hexColor(profile.checklistUncheckedColor);
    final labelStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0125,
        height: 1.2,
        color: textColor,
        fontWeight: FontWeight.w600,
      ),
    );

    final interaction = _ChecklistInteractionScope.maybeOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Grow the pie to fill the width it is handed instead of staying at a
        // fixed, tiny size. Every caller gives this widget a bounded column
        // width, so the chart now scales with the space that is actually
        // available next to (or above) the bullets.
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : w * 0.4;
        // Cap the pie so it stays a balanced companion to the bullet column
        // rather than dominating it: a smaller chart keeps the visual split
        // closer to 50/50 and, crucially, never forces the surrounding text to
        // shrink to fit the chart's height when a slide has many bullets.
        final diameter = maxW.clamp(w * 0.22, w * 0.30).toDouble();
        final baseRadius = diameter * 0.44;
        final hoverRadius = diameter * 0.48;
        final pieTitleStyle = _applyFont(
          font,
          TextStyle(
            fontSize: diameter * 0.085,
            height: 1.1,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        );

        Widget pie(bool? hovered) => PieChart(
          key: const ValueKey('checklist-progress-pie'),
          PieChartData(
            sectionsSpace: w * 0.002,
            centerSpaceRadius: 0,
            startDegreeOffset: -90,
            sections: [
              if (checkedPercent > 0)
                PieChartSectionData(
                  value: checkedPercent.toDouble(),
                  color: checkedColor,
                  radius: hovered == true ? hoverRadius : baseRadius,
                  title: '$checkedPercent%',
                  titleStyle: pieTitleStyle.copyWith(color: Colors.white),
                ),
              if (openPercent > 0)
                PieChartSectionData(
                  value: openPercent.toDouble(),
                  color: openColor,
                  radius: hovered == false ? hoverRadius : baseRadius,
                  title: '$openPercent%',
                  titleStyle: pieTitleStyle,
                ),
            ],
            pieTouchData: PieTouchData(
              enabled: interaction?.enabled == true,
              touchCallback: (event, response) {
                if (interaction?.enabled != true) return;
                final index = event.isInterestedForInteractions
                    ? response?.touchedSection?.touchedSectionIndex
                    : null;
                if (index == null) {
                  interaction!.hovered.value = null;
                } else if (checkedPercent == 0) {
                  interaction!.hovered.value = false;
                } else {
                  interaction!.hovered.value = index == 0;
                }
              },
            ),
          ),
          duration: Duration.zero,
        );

        return Semantics(
          label:
              '${context.l10n.d('Afgevinkt')} $checkedPercent%, '
              '${context.l10n.d('Niet afgevinkt')} $openPercent%',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: diameter,
                height: diameter,
                child: interaction == null
                    ? pie(null)
                    : ValueListenableBuilder<bool?>(
                        valueListenable: interaction.hovered,
                        builder: (_, hovered, _) => pie(hovered),
                      ),
              ),
              SizedBox(height: w * 0.008),
              MouseRegion(
                key: const ValueKey('checklist-progress-checked'),
                onEnter: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = true,
                onExit: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = null,
                child: Text(
                  '${context.l10n.d('Afgevinkt')} $checkedPercent%',
                  style: labelStyle,
                ),
              ),
              MouseRegion(
                key: const ValueKey('checklist-progress-unchecked'),
                onEnter: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = false,
                onExit: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = null,
                child: Text(
                  '${context.l10n.d('Niet afgevinkt')} $openPercent%',
                  style: labelStyle.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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

class _ChecklistBulletRow extends StatelessWidget {
  final List<String> bullets;
  final int itemIndex;
  final int column;
  final ListStyle listStyle;
  final bool checked;
  final String text;
  final int level;
  final double fontSize;
  final double bulletSize;
  final double bulletGap;
  final double scale;
  final String font;
  final ThemeProfile profile;

  const _ChecklistBulletRow({
    required this.bullets,
    required this.itemIndex,
    required this.column,
    required this.listStyle,
    required this.checked,
    required this.text,
    required this.level,
    required this.fontSize,
    required this.bulletSize,
    required this.bulletGap,
    required this.scale,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final interaction = _ChecklistInteractionScope.maybeOf(context);
    Widget row(bool highlighted) => AnimatedContainer(
      key: ValueKey('checklist-preview-item-$column-$itemIndex'),
      duration: const Duration(milliseconds: 140),
      padding: EdgeInsets.symmetric(horizontal: highlighted ? wScale(6) : 0),
      decoration: BoxDecoration(
        color: highlighted
            ? _hexColor(profile.accentColor).withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(wScale(5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: ValueKey('checklist-preview-toggle-$column-$itemIndex'),
            behavior: HitTestBehavior.opaque,
            onTap:
                listStyle == ListStyle.checklist && interaction?.enabled == true
                ? () => interaction!.onToggle?.call(column, itemIndex)
                : null,
            child: MouseRegion(
              cursor:
                  listStyle == ListStyle.checklist &&
                      interaction?.enabled == true
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              child: Text(
                '${_listMarker(bullets, itemIndex, listStyle)} ',
                style: TextStyle(
                  fontSize: fontSize,
                  color: _hexColor(profile.accentColor),
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                  decoration: checked && profile.checklistStrikeThrough
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: _hexColor(profile.textColor),
                ),
              ),
              linkColor: _hexColor(profile.accentColor),
            ),
          ),
        ],
      ),
    );

    final padded = Padding(
      padding: EdgeInsets.only(
        left: level * bulletSize * 1.05 * scale,
        top: bulletGap * scale,
        bottom: bulletGap * scale,
      ),
      child: interaction == null || listStyle != ListStyle.checklist
          ? row(false)
          : ValueListenableBuilder<bool?>(
              valueListenable: interaction.hovered,
              builder: (_, hovered, _) => row(hovered == checked),
            ),
    );
    return padded;
  }

  double wScale(double value) => value * scale;
}

class _ChecklistInteractionHost extends StatefulWidget {
  final bool enabled;
  final void Function(int column, int itemIndex)? onToggle;
  final Widget child;

  const _ChecklistInteractionHost({
    required this.enabled,
    required this.onToggle,
    required this.child,
  });

  @override
  State<_ChecklistInteractionHost> createState() =>
      _ChecklistInteractionHostState();
}

class _ChecklistInteractionHostState extends State<_ChecklistInteractionHost> {
  final ValueNotifier<bool?> hovered = ValueNotifier(null);

  @override
  void dispose() {
    hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ChecklistInteractionScope(
      enabled: widget.enabled,
      hovered: hovered,
      onToggle: widget.onToggle,
      child: widget.child,
    );
  }
}

class _ChecklistInteractionScope extends InheritedWidget {
  final bool enabled;
  final ValueNotifier<bool?> hovered;
  final void Function(int column, int itemIndex)? onToggle;

  const _ChecklistInteractionScope({
    required this.enabled,
    required this.hovered,
    required this.onToggle,
    required super.child,
  });

  static _ChecklistInteractionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChecklistInteractionScope>();

  @override
  bool updateShouldNotify(_ChecklistInteractionScope oldWidget) =>
      enabled != oldWidget.enabled || onToggle != oldWidget.onToggle;
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
  final VoidCallback? onComplete;

  const _VideoPreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.autoplay = false,
    this.onComplete,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  String? _path;
  bool _completed = false;

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
    _controller?.removeListener(_onTick);
    await _controller?.dispose();
    _controller = null;
    _completed = false;
    _path = _resolvePath(widget.slide.videoPath, widget.projectPath);
    if (_path == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(File(_path!));
    _controller = controller;
    try {
      await controller.initialize();
      controller.addListener(_onTick);
      await controller.setLooping(false);
      if (widget.autoplay) await controller.play();
    } catch (_) {
      // Keep the placeholder visible when the platform cannot open the file.
    }
    if (mounted) setState(() {});
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _completed ||
        !widget.autoplay) {
      return;
    }
    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration > Duration.zero &&
        position.inMilliseconds >= duration.inMilliseconds - 200 &&
        !controller.value.isPlaying) {
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

  /// Natural (unwrapped) size of [text] in [style]: width is the longest line,
  /// height the full block. Used to scale code to the available space.
  static Size _measureMono(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.size;
  }

  @override
  Widget build(BuildContext context) {
    _ensureHighlightLanguages();
    final pad = w * 0.05;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final code = slide.customMarkdown;
    final lang = slide.codeLanguage.trim();
    final known = lang.isNotEmpty && allLanguages.containsKey(lang);

    final codeBg = _hexColor(profile.codeBackgroundColor);
    final codeFg = _hexColor(profile.codeTextColor);

    // The chosen monospace family, always backed by a generic monospace fallback
    // so an uninstalled face still renders fixed-width.
    final fallback = <String>['Menlo', 'Consolas', 'Courier New', 'monospace']
      ..removeWhere((f) => f == profile.codeFontFamily);
    final baseFont = w * 0.024;
    final maxFont = w * 0.040; // grow to fill, but never huge
    TextStyle monoAt(double size) => TextStyle(
      fontFamily: profile.codeFontFamily,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: 1.4,
      color: codeFg,
    );

    // HighlightView throws on an unknown language, so fall back to plain (but
    // monospace) text. When syntax highlighting is off we always render plain
    // text so the whole block is one colour — needed for a CRT-green screen.
    final useHighlight = known && profile.codeHighlightSyntax;
    final highlightTheme = {
      ...atomOneDarkTheme,
      // Keep atom-one-dark's per-token colours but drop its own background so
      // our themed [codeBg] shows through unchanged.
      'root': (atomOneDarkTheme['root'] ?? const TextStyle()).copyWith(
        backgroundColor: codeBg,
        color: codeFg,
      ),
    };
    Widget buildCode(TextStyle style) => useHighlight
        ? HighlightView(
            code,
            language: lang,
            theme: highlightTheme,
            padding: EdgeInsets.zero,
            textStyle: style,
          )
        : Text(code, style: style);

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The slide title belongs to the slide, not inside the code window,
            // so it sits above the panel like other slide types.
            if (slide.title.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.025,
                  vertical: w * 0.01,
                ),
                decoration: BoxDecoration(
                  color: _hexColor(profile.titleBackgroundColor),
                  borderRadius: BorderRadius.circular(w * 0.012),
                  border: Border(
                    left: BorderSide(
                      color: _hexColor(profile.accentColor),
                      width: w * 0.006,
                    ),
                  ),
                ),
                child: _md(
                  context,
                  slide.title,
                  _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.032,
                      height: 1.1,
                      fontWeight: FontWeight.bold,
                      color: _hexColor(profile.titleTextColor),
                    ),
                  ),
                  linkColor: _hexColor(profile.accentColor),
                ),
              ),
              SizedBox(height: w * 0.018),
            ],
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: codeBg,
                  borderRadius: BorderRadius.circular(w * 0.012),
                  border: Border.all(color: codeFg.withValues(alpha: 0.22)),
                ),
                padding: EdgeInsets.all(w * 0.03),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Size the code to fill the panel: scale up to use spare
                    // space (capped at [maxFont]) and down so long fragments
                    // still fit, rather than leaving a small block in a big box.
                    final measured = useHighlight
                        ? code.replaceAll('\t', '        ')
                        : code;
                    final natural = _measureMono(measured, monoAt(baseFont));
                    final availW = math.max(1.0, constraints.maxWidth - 1);
                    final availH = math.max(1.0, constraints.maxHeight - 1);
                    var scale = math.min(
                      availW / natural.width,
                      availH / natural.height,
                    );
                    if (!scale.isFinite || scale <= 0) scale = 1;
                    final size = math.min(baseFont * scale, maxFont);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: buildCode(monoAt(size)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a chart slide (bar/line/pie) from its ```chart JSON spec.
class _ChartPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final bool presentationMode;

  const _ChartPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.presentationMode,
  });

  @override
  State<_ChartPreview> createState() => _ChartPreviewState();
}

class _ChartPreviewState extends State<_ChartPreview> {
  Slide get slide => widget.slide;
  double get w => widget.w;
  String get font => widget.font;
  ThemeProfile get profile => widget.profile;
  bool get presentationMode => widget.presentationMode;

  /// Legend entry the pointer is over: a series index for bar/line charts, or a
  /// slice (category) index for pie charts. Null when nothing is hovered.
  int? _hovered;

  /// The radar vertex under the pointer, used to draw its tooltip. Null when not
  /// hovering a point.
  ({int series, int entry, double value, Offset offset})? _radarTouch;

  void _setHover(int? index) {
    if (_hovered != index) setState(() => _hovered = index);
  }

  /// True when another legend entry is hovered, so [index] should fade back.
  bool _dimmed(int index) => _hovered != null && _hovered != index;

  /// Series colour with legend-hover feedback: non-hovered series fade out so
  /// the hovered one stands out in the plot.
  Color _seriesDisplayColor(ChartSeries series, int i) {
    final base = _seriesColor(series, i);
    return _dimmed(i) ? base.withValues(alpha: 0.2) : base;
  }

  double get _labelScale => presentationMode ? 1.12 : 1;

  Color _seriesColor(ChartSeries series, int i) {
    if (series.color == null && i == 0) {
      return _hexColor(profile.accentColor);
    }
    return _hexColor(chartSeriesColor(series, i));
  }

  /// Text alternative for the chart (WCAG 1.1.1): chart type, title and the
  /// underlying values per series, so a screen reader conveys the same
  /// information the visual encodes.
  String _semanticsLabel(BuildContext context, ChartSpec spec) {
    final l10n = context.l10n;
    final typeName = switch (spec.type) {
      ChartType.bar => l10n.d('Staaf'),
      ChartType.line => l10n.d('Lijn'),
      ChartType.pie => l10n.d('Cirkel'),
      ChartType.radar => l10n.d('Spider'),
    };
    final buffer = StringBuffer('${l10n.d('Grafiek')} ($typeName)');
    if (spec.title.isNotEmpty) {
      buffer.write(': ${stripInlineMarkdown(spec.title)}');
    }
    if (!spec.hasInlineData) return buffer.toString();
    for (var si = 0; si < spec.series.length; si++) {
      final series = spec.series[si];
      final name = series.name.isEmpty
          ? '${l10n.d('Reeks')} ${si + 1}'
          : series.name;
      final values = [
        for (var xi = 0; xi < spec.x.length && xi < series.data.length; xi++)
          '${spec.x[xi]} ${_fmtNum(series.data[xi])}',
      ];
      buffer.write('. $name: ${values.join(', ')}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final spec = ChartSpec.parse(slide.customMarkdown);
    final horizontalPad = w * 0.05;
    final verticalPad = w * 0.018;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final textColor = _hexColor(profile.textColor);

    return Semantics(
      image: true,
      label: _semanticsLabel(context, spec),
      // The visual chart (axis labels, legend chips, tooltips) would read as
      // disconnected fragments; the label above carries the full story.
      child: ExcludeSemantics(
        child: _chartBody(
          context,
          spec,
          horizontalPad,
          verticalPad,
          safe,
          textColor,
        ),
      ),
    );
  }

  Widget _chartBody(
    BuildContext context,
    ChartSpec spec,
    double horizontalPad,
    double verticalPad,
    EdgeInsets safe,
    Color textColor,
  ) {
    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPad,
          verticalPad + safe.top,
          horizontalPad,
          verticalPad + safe.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (spec.title.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.025,
                  vertical: w * 0.01,
                ),
                decoration: BoxDecoration(
                  color: _hexColor(profile.titleBackgroundColor),
                  borderRadius: BorderRadius.circular(w * 0.012),
                  border: Border(
                    left: BorderSide(
                      color: _hexColor(profile.accentColor),
                      width: w * 0.006,
                    ),
                  ),
                ),
                child: _md(
                  context,
                  spec.title,
                  _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.032,
                      height: 1.1,
                      fontWeight: FontWeight.bold,
                      color: _hexColor(profile.titleTextColor),
                    ),
                  ),
                  linkColor: _hexColor(profile.accentColor),
                ),
              ),
              SizedBox(height: w * 0.012),
            ],
            Expanded(
              child: Container(
                key: const ValueKey('chart-surface'),
                padding: EdgeInsets.fromLTRB(
                  w * 0.02,
                  w * 0.01,
                  w * 0.025,
                  w * 0.01,
                ),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(w * 0.014),
                  border: Border.all(color: textColor.withValues(alpha: 0.09)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: spec.hasInlineData
                          ? _chart(spec, textColor)
                          : _placeholder(context),
                    ),
                    if (spec.hasInlineData && spec.series.isNotEmpty) ...[
                      SizedBox(height: w * 0.006),
                      spec.type == ChartType.pie
                          ? _pieLegend(spec, textColor)
                          : _legend(spec, textColor),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(ChartSpec spec, Color textColor) {
    return SizedBox(
      height: w * 0.03,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < spec.series.length; i++) ...[
              if (i > 0) SizedBox(width: w * 0.01),
              MouseRegion(
                onEnter: (_) => _setHover(i),
                onExit: (_) => _setHover(null),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: _dimmed(i) ? 0.4 : 1,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.01,
                      vertical: w * 0.004,
                    ),
                    decoration: BoxDecoration(
                      color: _hovered == i
                          ? _seriesColor(
                              spec.series[i],
                              i,
                            ).withValues(alpha: 0.18)
                          : textColor.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(w),
                      border: Border.all(
                        color: _hovered == i
                            ? _seriesColor(spec.series[i], i)
                            : Colors.transparent,
                        width: w * 0.0015,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: w * 0.012,
                          height: w * 0.012,
                          decoration: BoxDecoration(
                            color: _seriesColor(spec.series[i], i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: w * 0.006),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: w * 0.16),
                          child: Text(
                            spec.series[i].name.isEmpty
                                ? 'Reeks ${i + 1}'
                                : spec.series[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _applyFont(
                              font,
                              TextStyle(
                                fontSize: w * 0.013,
                                fontWeight: FontWeight.w600,
                                color: textColor.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pieLegend(ChartSpec spec, Color textColor) {
    final itemCount = math.min(spec.x.length, 18);
    final columns = math.min(itemCount, presentationMode ? 4 : 6);
    final rows = (itemCount / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = w * 0.006;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return SizedBox(
          height: rows * w * 0.03 * _labelScale + (rows - 1) * gap,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < itemCount; i++)
                MouseRegion(
                  onEnter: (_) => _setHover(i),
                  onExit: (_) => _setHover(null),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _dimmed(i) ? 0.4 : 1,
                    child: Container(
                      width: itemWidth,
                      height: w * 0.03 * _labelScale,
                      padding: EdgeInsets.symmetric(horizontal: w * 0.008),
                      decoration: BoxDecoration(
                        color: _hovered == i
                            ? _hexColor(
                                chartRowColor(spec, i),
                              ).withValues(alpha: 0.18)
                            : textColor.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(w),
                        border: Border.all(
                          color: _hovered == i
                              ? _hexColor(chartRowColor(spec, i))
                              : Colors.transparent,
                          width: w * 0.0015,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: w * 0.012,
                            height: w * 0.012,
                            decoration: BoxDecoration(
                              color: _hexColor(chartRowColor(spec, i)),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: w * 0.006),
                          Expanded(
                            child: Text(
                              spec.x[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _applyFont(
                                font,
                                TextStyle(
                                  fontSize: w * 0.013 * _labelScale,
                                  fontWeight: FontWeight.w600,
                                  color: textColor.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
      case ChartType.radar:
        return _radarChart(spec, textColor);
    }
  }

  double _maxY(ChartSpec spec) {
    var m = 0.0;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (v > m) m = v;
      }
    }
    // Keep any bound line comfortably inside the plot so its label is visible.
    if (spec.supportsBounds) {
      for (final b in [spec.minBound, spec.maxBound]) {
        if (b != null && b > m) m = b;
      }
    }
    return m <= 0 ? 1 : m * 1.15;
  }

  double _minY(ChartSpec spec) {
    var m = 0.0;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (v < m) m = v;
      }
    }
    if (spec.supportsBounds) {
      for (final b in [spec.minBound, spec.maxBound]) {
        if (b != null && b < m) m = b;
      }
    }
    return m >= 0 ? 0 : m * 1.15;
  }

  /// Optional min/max threshold lines drawn across the plot (bar/line only).
  ExtraLinesData _boundLines(ChartSpec spec) {
    if (!spec.supportsBoundLines) return const ExtraLinesData();
    final dash = [
      (w * 0.018).round().clamp(4, 14),
      (w * 0.01).round().clamp(3, 9),
    ];
    HorizontalLine line(double value, Color color, String prefix) =>
        HorizontalLine(
          y: value,
          color: color,
          strokeWidth: w * 0.0035,
          dashArray: dash,
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.topRight,
            padding: EdgeInsets.only(right: w * 0.006, bottom: w * 0.002),
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.0115 * _labelScale,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            labelResolver: (_) => '$prefix ${_fmtNum(value)}',
          ),
        );
    return ExtraLinesData(
      horizontalLines: [
        if (spec.minBound != null)
          line(spec.minBound!, const Color(0xFFF59E0B), 'min'),
        if (spec.maxBound != null)
          line(spec.maxBound!, const Color(0xFFEF4444), 'max'),
      ],
    );
  }

  FlTitlesData _titles(ChartSpec spec, Color textColor, {bool bars = false}) {
    final style = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0115 * _labelScale,
        color: textColor.withValues(alpha: 0.88),
        fontWeight: presentationMode ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: w * 0.05 * _labelScale,
          getTitlesWidget: (value, meta) => Text(
            _fmtNum(value),
            style: style.copyWith(fontSize: w * 0.0105 * _labelScale),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: w * 0.044 * _labelScale,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            final n = spec.x.length;
            if (i < 0 || i >= n) return const SizedBox.shrink();
            // Show as many labels as fit without colliding: keep at least
            // [minSlot] of horizontal room per label, then thin them out
            // evenly based on the actual pixel spacing between points. Line
            // charts spread n points over n-1 intervals; bar groups are laid
            // out spaceEvenly, which puts their centres (axis + groupWidth) /
            // (n + 1) apart.
            final spacing = bars
                ? (meta.parentAxisSize + _barGroupWidth(spec)) / (n + 1)
                : (n > 1 ? meta.parentAxisSize / (n - 1) : meta.parentAxisSize);
            final minSlot = w * 0.085 * _labelScale;
            final step = math.max(1, (minSlot / spacing).ceil());
            final lastMultiple = ((n - 1) ~/ step) * step;
            final lastGap = n - 1 - lastMultiple;
            final showLast = i == n - 1 && lastGap > step / 2;
            if (i % step != 0 && !showLast) return const SizedBox.shrink();
            // The extra end label can sit closer than a full step to its
            // neighbour; shrink both of their slots to the real gap so they
            // never run through each other.
            var slotSteps = step.toDouble();
            if (showLast || (i == lastMultiple && lastGap > step / 2)) {
              slotSteps = math.min(slotSteps, lastGap.toDouble());
            }
            final slot = (slotSteps * spacing - w * 0.012).clamp(
              w * 0.04,
              w * 0.16,
            );
            return Padding(
              padding: EdgeInsets.only(top: w * 0.008),
              child: SizedBox(
                width: slot,
                child: Text(
                  spec.x[i],
                  style: style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
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

  /// Width of one bar rod, shared by the chart and the axis-label spacing.
  double _barRodWidth(ChartSpec spec) =>
      (w * 0.032 / spec.series.length).clamp(w * 0.008, w * 0.022);

  /// Total width of one bar group: its rods plus fl_chart's default 2px
  /// spacing between rods within a group.
  double _barGroupWidth(ChartSpec spec) {
    final rods = math.max(1, spec.series.length);
    return rods * _barRodWidth(spec) + (rods - 1) * 2;
  }

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
                  color: _seriesDisplayColor(spec.series[si], si),
                  width: _barRodWidth(spec),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(w * 0.006),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: _maxY(spec),
                    color: textColor.withValues(alpha: 0.025),
                  ),
                ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        // The axis-label spacing in _titles assumes this layout; keep it
        // explicit rather than relying on fl_chart's default.
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: groups,
        titlesData: _titles(spec, textColor, bars: true),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        barTouchData: BarTouchData(
          enabled: true,
          mouseCursorResolver: (event, response) => response?.spot == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF0F172A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = group.x >= 0 && group.x < spec.x.length
                  ? spec.x[group.x]
                  : '';
              final series = rodIndex < spec.series.length
                  ? spec.series[rodIndex].name
                  : '';
              return BarTooltipItem(
                '$label\n${series.isEmpty ? 'Reeks ${rodIndex + 1}' : series}: ${_fmtNum(rod.toY)}',
                _tooltipStyle(),
              );
            },
          ),
        ),
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
          color: _seriesDisplayColor(spec.series[si], si),
          barWidth: w * (_hovered == si ? 0.0065 : 0.0045),
          isCurved: true,
          curveSmoothness: 0.22,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: w * 0.005,
              color: _seriesDisplayColor(spec.series[si], si),
              strokeWidth: w * 0.0025,
              strokeColor: _hexColor(profile.slideBackgroundColor),
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: _seriesDisplayColor(
              spec.series[si],
              si,
            ).withValues(alpha: spec.series.length == 1 ? 0.14 : 0.05),
          ),
        ),
      );
    }
    return LineChart(
      LineChartData(
        minY: _minY(spec),
        maxY: _maxY(spec),
        lineBarsData: bars,
        titlesData: _titles(spec, textColor),
        gridData: _grid(textColor),
        borderData: FlBorderData(show: false),
        extraLinesData: _boundLines(spec),
        lineTouchData: LineTouchData(
          enabled: true,
          // Measure proximity to the actual dot (x *and* y), not just the
          // column, so the tooltip belongs to the point under the cursor.
          distanceCalculator: (touch, spot) => (touch - spot).distance,
          touchSpotThreshold: (w * 0.02).clamp(8.0, 24.0).toDouble(),
          mouseCursorResolver: (event, response) =>
              response?.lineBarSpots?.isEmpty ?? true
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF0F172A),
            // Show every dot near the cursor. When several dots sit on (almost)
            // the same spot they all appear; the font shrinks to keep them
            // readable when stacked.
            getTooltipItems: (spots) {
              final style = _lineTooltipStyle(spots.length);
              return [
                for (final spot in spots)
                  LineTooltipItem(
                    '${spot.spotIndex < spec.x.length ? spec.x[spot.spotIndex] : ''}\n'
                    '${spot.barIndex < spec.series.length && spec.series[spot.barIndex].name.isNotEmpty ? spec.series[spot.barIndex].name : 'Reeks ${spot.barIndex + 1}'}: ${_fmtNum(spot.y)}',
                    style,
                  ),
              ];
            },
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }

  Widget _pieChart(ChartSpec spec, Color textColor) {
    if (spec.series.isEmpty || spec.x.isEmpty) {
      return _placeholderText('—');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleSeries = math.min(spec.series.length, 2);
        final columns = visibleSeries;
        const rows = 1;
        final tileHeight = constraints.maxHeight / rows;
        final tileWidth = constraints.maxWidth / columns;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: tileWidth / tileHeight,
            crossAxisSpacing: w * 0.012,
            mainAxisSpacing: w * 0.008,
          ),
          itemCount: visibleSeries,
          itemBuilder: (context, si) {
            final series = spec.series[si];
            final values = [
              for (var xi = 0; xi < spec.x.length; xi++)
                xi < series.data.length && series.data[xi] > 0
                    ? series.data[xi]
                    : 0.0,
            ];
            final total = values.fold<double>(0, (a, b) => a + b);
            return Row(
              children: [
                Expanded(
                  flex: 4,
                  child: total <= 0
                      ? Center(
                          child: Text(
                            '0',
                            style: _applyFont(
                              font,
                              TextStyle(
                                fontSize: w * 0.025,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, pieConstraints) {
                            final available =
                                pieConstraints.biggest.shortestSide;
                            final radius = (available * 0.42).clamp(
                              w * 0.018,
                              w * 0.075,
                            );
                            return ClipRect(
                              child: _HoverPieChart(
                                externalHover: _hovered,
                                values: values,
                                labels: spec.x,
                                colors: [
                                  for (var xi = 0; xi < values.length; xi++)
                                    _hexColor(chartRowColor(spec, xi)),
                                ],
                                radius: radius,
                                centerSpaceRadius: radius * 0.42,
                                sectionSpace: w * 0.002,
                                titleStyle: _applyFont(
                                  font,
                                  TextStyle(
                                    fontSize: (radius * 0.18).clamp(
                                      w * 0.009,
                                      w * 0.013,
                                    ),
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                tooltipStyle: _tooltipStyle(),
                              ),
                            );
                          },
                        ),
                ),
                SizedBox(width: w * 0.008),
                Expanded(
                  flex: 2,
                  child: Text(
                    series.name.isEmpty ? 'Reeks ${si + 1}' : series.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * 0.015,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _radarChart(ChartSpec spec, Color textColor) {
    if (spec.x.length < 3 || spec.series.isEmpty) {
      return _placeholderText(
        context.l10n.d('Een spider-diagram heeft minstens drie labels nodig'),
      );
    }
    final grid = textColor.withValues(alpha: 0.18);
    final scale = radarScale(spec);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: w * 0.012),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve a slim column on the right for the scale legend; the rest
          // of the area is shared between the spider and its axis labels.
          final legendWidth = w * 0.075;
          final boxW = math.max(
            0.0,
            constraints.maxWidth - legendWidth - w * 0.02,
          );
          final boxH = constraints.maxHeight;
          if (boxW <= 0 || !boxH.isFinite || boxH <= 0) {
            return const SizedBox.shrink();
          }
          // Measure every axis label and grow the spider until the labels just
          // fit between the polygon and the edges of the available area, so
          // the diagram uses the space the old fixed label bands wasted.
          final layout = _radarLabelLayout(spec, boxW, boxH, textColor);
          final chartSide = layout.chartSide;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: boxW,
                    height: boxH,
                    child: Stack(
                      children: [
                        for (var i = 0; i < spec.x.length; i++)
                          _radarAxisLabel(
                            label: spec.x[i],
                            index: i,
                            count: spec.x.length,
                            layout: layout,
                            textColor: textColor,
                          ),
                        Positioned(
                          left: (boxW - chartSide) / 2,
                          top: (boxH - chartSide) / 2,
                          width: chartSide,
                          height: chartSide,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: RadarChart(
                                  RadarChartData(
                                    dataSets: [
                                      for (
                                        var si = 0;
                                        si < spec.series.length;
                                        si++
                                      )
                                        RadarDataSet(
                                          dataEntries: [
                                            for (
                                              var xi = 0;
                                              xi < spec.x.length;
                                              xi++
                                            )
                                              RadarEntry(
                                                value:
                                                    xi <
                                                        spec
                                                            .series[si]
                                                            .data
                                                            .length
                                                    ? spec.series[si].data[xi]
                                                    : 0,
                                              ),
                                          ],
                                          fillColor:
                                              _seriesDisplayColor(
                                                spec.series[si],
                                                si,
                                              ).withValues(
                                                alpha: _dimmed(si)
                                                    ? 0.04
                                                    : 0.16,
                                              ),
                                          borderColor: _seriesDisplayColor(
                                            spec.series[si],
                                            si,
                                          ),
                                          borderWidth:
                                              w *
                                              (_hovered == si
                                                  ? 0.0055
                                                  : 0.0035),
                                          entryRadius:
                                              w *
                                              (_hovered == si ? 0.006 : 0.004),
                                        ),
                                      // Invisible anchor pinning the scale to [lo, hi]
                                      // so the rings represent a fixed scale.
                                      RadarDataSet(
                                        dataEntries: [
                                          for (
                                            var xi = 0;
                                            xi < spec.x.length;
                                            xi++
                                          )
                                            RadarEntry(
                                              value: xi == 0
                                                  ? scale.hi
                                                  : scale.lo,
                                            ),
                                        ],
                                        fillColor: Colors.transparent,
                                        borderColor: Colors.transparent,
                                        borderWidth: 0,
                                        entryRadius: 0,
                                      ),
                                    ],
                                    radarShape: RadarShape.polygon,
                                    radarBackgroundColor: Colors.transparent,
                                    radarBorderData: BorderSide(
                                      color: grid,
                                      width: 1,
                                    ),
                                    gridBorderData: BorderSide(
                                      color: grid,
                                      width: 1,
                                    ),
                                    tickBorderData: BorderSide(
                                      color: grid,
                                      width: 1,
                                    ),
                                    tickCount: scale.ticks,
                                    isMinValueAtCenter: true,
                                    // The scale now lives in a side legend, so hide
                                    // fl_chart's in-chart ring numbers.
                                    ticksTextStyle: const TextStyle(
                                      color: Colors.transparent,
                                      fontSize: 0.001,
                                    ),
                                    titlePositionPercentageOffset: 0,
                                    getTitle: (index, angle) => RadarChartTitle(
                                      text: index < spec.x.length
                                          ? spec.x[index]
                                          : '',
                                    ),
                                    // Labels are rendered as constrained widgets
                                    // around the chart so long text can wrap.
                                    titleTextStyle: const TextStyle(
                                      color: Colors.transparent,
                                      fontSize: 0.001,
                                    ),
                                    radarTouchData: RadarTouchData(
                                      enabled: true,
                                      touchSpotThreshold: (w * 0.02)
                                          .clamp(8.0, 24.0)
                                          .toDouble(),
                                      mouseCursorResolver: (event, response) =>
                                          _radarSpotFrom(response, spec) == null
                                          ? SystemMouseCursors.basic
                                          : SystemMouseCursors.click,
                                      touchCallback: (event, response) {
                                        final next =
                                            event.isInterestedForInteractions
                                            ? _radarSpotFrom(response, spec)
                                            : null;
                                        if (next != _radarTouch) {
                                          setState(() => _radarTouch = next);
                                        }
                                      },
                                    ),
                                  ),
                                  duration: Duration.zero,
                                ),
                              ),
                              if (_radarTouch != null)
                                _radarTooltip(spec, chartSide, _radarTouch!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: legendWidth,
                child: _radarScaleLegend(scale, textColor),
              ),
            ],
          );
        },
      ),
    );
  }

  TextStyle _radarLabelStyle(int count, Color textColor) => _applyFont(
    font,
    TextStyle(
      fontSize: w * (count <= 6 ? 0.013 : 0.0115) * _labelScale,
      height: 1.05,
      color: textColor.withValues(alpha: 0.88),
      fontWeight: presentationMode ? FontWeight.w600 : FontWeight.w500,
    ),
  );

  /// True when the vertex in [direction] gets its label placed beside the
  /// polygon (left/right) rather than above/below it.
  static bool _radarLabelBeside(Offset direction) => direction.dx.abs() > 0.35;

  /// Sizes the spider and places every axis label around it.
  ///
  /// Each label is measured at its real text size, then the polygon radius is
  /// grown until the tightest label exactly fits between the polygon and the
  /// edge of the [boxW]×[boxH] area. fl_chart draws the polygon at 0.4× the
  /// side of its (square) widget, which is what ties [chartSide] to the
  /// resulting radius.
  ({double chartSide, List<Rect> rects, List<TextAlign> aligns, int maxLines})
  _radarLabelLayout(ChartSpec spec, double boxW, double boxH, Color textColor) {
    const radiusFactor = 0.4; // fl_chart: radius = min(w, h) / 2 * 0.8
    final n = spec.x.length;
    final style = _radarLabelStyle(n, textColor);
    final gap = w * 0.008;
    final maxLines = n <= 6 ? 3 : 2;
    final sideCap = math.min(boxW * 0.28, w * 0.2);
    final topCap = math.min(boxW * 0.5, w * 0.3);

    Size measure(String text, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0.0, maxWidth));
      final size = Size(painter.width, painter.height);
      painter.dispose();
      return size;
    }

    final directions = <Offset>[];
    final sizes = <Size>[];
    for (var i = 0; i < n; i++) {
      final angle = (2 * math.pi * i / n) - math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      directions.add(dir);
      sizes.add(measure(spec.x[i], _radarLabelBeside(dir) ? sideCap : topCap));
    }

    // The largest polygon radius every label still fits next to.
    var radius = radiusFactor * math.min(boxW, boxH);
    for (var i = 0; i < n; i++) {
      final dx = directions[i].dx.abs();
      final dy = directions[i].dy.abs();
      if (_radarLabelBeside(directions[i])) {
        radius = math.min(radius, (boxW / 2 - gap - sizes[i].width) / dx);
        if (dy > 0.01) {
          radius = math.min(radius, (boxH / 2 - sizes[i].height / 2) / dy);
        }
      } else {
        radius = math.min(radius, (boxH / 2 - gap - sizes[i].height) / dy);
        if (dx > 0.01) {
          radius = math.min(radius, (boxW / 2 - sizes[i].width / 2) / dx);
        }
      }
    }
    // Never let extreme labels crush the spider entirely; below this floor the
    // labels get clamped (and ellipsized) instead.
    final floor = 0.18 * math.min(boxW, boxH);
    radius = radius.clamp(
      math.min(floor, radiusFactor * math.min(boxW, boxH)),
      radiusFactor * math.min(boxW, boxH),
    );
    final chartSide = radius / radiusFactor;

    final center = Offset(boxW / 2, boxH / 2);
    final rects = <Rect>[];
    final aligns = <TextAlign>[];
    for (var i = 0; i < n; i++) {
      final dir = directions[i];
      final anchor = center + dir * (radius + gap);
      var size = sizes[i];
      double left;
      double top;
      if (_radarLabelBeside(dir)) {
        // Re-measure against the room actually left beside the polygon, so a
        // clamped radius still produces a label that wraps inside the box.
        final room = dir.dx > 0 ? boxW - anchor.dx : anchor.dx;
        if (size.width > room) size = measure(spec.x[i], room);
        left = dir.dx > 0 ? anchor.dx : anchor.dx - size.width;
        top = anchor.dy - size.height / 2;
        aligns.add(dir.dx > 0 ? TextAlign.left : TextAlign.right);
      } else {
        left = anchor.dx - size.width / 2;
        top = dir.dy < 0 ? anchor.dy - size.height : anchor.dy;
        aligns.add(TextAlign.center);
      }
      rects.add(
        Rect.fromLTWH(
          left.clamp(0.0, math.max(0.0, boxW - size.width)),
          top.clamp(0.0, math.max(0.0, boxH - size.height)),
          size.width,
          size.height,
        ),
      );
    }
    return (
      chartSide: chartSide,
      rects: rects,
      aligns: aligns,
      maxLines: maxLines,
    );
  }

  Widget _radarAxisLabel({
    required String label,
    required int index,
    required int count,
    required ({
      double chartSide,
      List<Rect> rects,
      List<TextAlign> aligns,
      int maxLines,
    })
    layout,
    required Color textColor,
  }) {
    final rect = layout.rects[index];
    return Positioned(
      key: ValueKey('radar-axis-label-$index'),
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Text(
        label,
        maxLines: layout.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: layout.aligns[index],
        style: _radarLabelStyle(count, textColor),
      ),
    );
  }

  /// Extract the touched real-series vertex from a radar touch response,
  /// ignoring the invisible scale anchor dataset.
  ({int series, int entry, double value, Offset offset})? _radarSpotFrom(
    RadarTouchResponse? response,
    ChartSpec spec,
  ) {
    final spot = response?.touchedSpot;
    if (spot == null) return null;
    if (spot.touchedDataSetIndex < 0 ||
        spot.touchedDataSetIndex >= spec.series.length) {
      return null; // the anchor dataset, or out of range
    }
    return (
      series: spot.touchedDataSetIndex,
      entry: spot.touchedRadarEntryIndex,
      value: spot.touchedRadarEntry.value,
      offset: spot.offset,
    );
  }

  /// A small floating tooltip for the hovered radar vertex, like the other
  /// charts: the axis label, the series name and the value.
  Widget _radarTooltip(
    ChartSpec spec,
    double side,
    ({int series, int entry, double value, Offset offset}) touch,
  ) {
    final axis = touch.entry >= 0 && touch.entry < spec.x.length
        ? spec.x[touch.entry]
        : '';
    final series = touch.series < spec.series.length
        ? spec.series[touch.series].name
        : '';
    final label = series.isEmpty ? 'Reeks ${touch.series + 1}' : series;
    final onLeftHalf = touch.offset.dx <= side / 2;
    return Positioned(
      left: onLeftHalf ? (touch.offset.dx + w * 0.012) : null,
      right: onLeftHalf ? null : (side - touch.offset.dx + w * 0.012),
      top: (touch.offset.dy - w * 0.03).clamp(0.0, math.max(0.0, side - 1)),
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: side * 0.6),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.012,
              vertical: w * 0.006,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(w * 0.008),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 6),
              ],
            ),
            child: Text(
              '${axis.isEmpty ? '' : '$axis\n'}$label: ${_fmtNum(touch.value)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _tooltipStyle(),
            ),
          ),
        ),
      ),
    );
  }

  /// Vertical scale legend shown to the right of a radar chart: the tick values
  /// from the outer ring (top) down to the centre (bottom), in a small font.
  Widget _radarScaleLegend(
    ({double lo, double hi, int ticks}) scale,
    Color textColor,
  ) {
    final style = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.012 * _labelScale,
        color: textColor.withValues(alpha: 0.62),
        fontWeight: FontWeight.w600,
      ),
    );
    final tickColor = textColor.withValues(alpha: 0.3);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var k = scale.ticks; k >= 0; k--) ...[
          if (k != scale.ticks) SizedBox(height: w * 0.018 * _labelScale),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: w * 0.012, height: 1, color: tickColor),
              SizedBox(width: w * 0.006),
              Flexible(
                child: Text(
                  _fmtNum(scale.lo + (scale.hi - scale.lo) * k / scale.ticks),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Resolves the radar scale: a low/high pair plus an even tick count. Honours
  /// the optional [ChartSpec.minBound]/[maxBound] and otherwise rounds the data
  /// range to a tidy scale so the rings read as round numbers.
  ({double lo, double hi, int ticks}) radarScale(ChartSpec spec) {
    var dataMin = 0.0;
    var dataMax = 0.0;
    var seen = false;
    for (final s in spec.series) {
      for (final v in s.data) {
        if (!seen) {
          dataMin = v;
          dataMax = v;
          seen = true;
        } else {
          if (v < dataMin) dataMin = v;
          if (v > dataMax) dataMax = v;
        }
      }
    }
    if (!seen) {
      dataMin = 0;
      dataMax = 1;
    }
    final rawLo = spec.minBound ?? (dataMin < 0 ? dataMin : 0);
    final rawHi = spec.maxBound ?? dataMax;
    final nice = _niceScale(rawLo, rawHi);
    final lo = spec.minBound ?? nice.lo;
    var hi = spec.maxBound ?? nice.hi;
    if (hi <= lo) hi = lo + nice.step;
    final ticks = math.max(2, ((hi - lo) / nice.step).round());
    return (lo: lo, hi: hi, ticks: ticks);
  }

  ({double lo, double hi, double step}) _niceScale(double lo, double hi) {
    final range = (hi - lo).abs();
    final r = range <= 0 ? 1.0 : range;
    final rawStep = r / 4;
    final mag = math
        .pow(10, (math.log(rawStep) / math.ln10).floor())
        .toDouble();
    final norm = rawStep / mag;
    final niceNorm = norm < 1.5
        ? 1.0
        : norm < 3
        ? 2.0
        : norm < 7
        ? 5.0
        : 10.0;
    final step = niceNorm * mag;
    return (
      lo: (lo / step).floor() * step,
      hi: (hi / step).ceil() * step,
      step: step,
    );
  }

  TextStyle _tooltipStyle() => _applyFont(
    font,
    TextStyle(
      color: Colors.white,
      fontSize: (w * 0.013 * _labelScale).clamp(11, 18),
      height: 1.25,
      fontWeight: FontWeight.w700,
    ),
  );

  /// Tooltip style for line charts. Each touched dot adds two lines, so when
  /// several dots overlap the font shrinks a step to keep the stack readable.
  TextStyle _lineTooltipStyle(int count) {
    final base = (w * 0.013 * _labelScale).clamp(11.0, 18.0);
    final shrink = (1 - (count - 2) * 0.13).clamp(0.6, 1.0);
    return _applyFont(
      font,
      TextStyle(
        color: Colors.white,
        fontSize: (base * shrink).clamp(8.0, 18.0),
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
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

class _HoverPieChart extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final double radius;
  final double centerSpaceRadius;
  final double sectionSpace;
  final TextStyle titleStyle;
  final TextStyle tooltipStyle;

  /// Slice index highlighted from outside (e.g. hovering the legend), combined
  /// with this chart's own touch hover.
  final int? externalHover;

  const _HoverPieChart({
    required this.values,
    required this.labels,
    required this.colors,
    required this.radius,
    required this.centerSpaceRadius,
    required this.sectionSpace,
    required this.titleStyle,
    required this.tooltipStyle,
    this.externalHover,
  });

  @override
  State<_HoverPieChart> createState() => _HoverPieChartState();
}

class _HoverPieChartState extends State<_HoverPieChart> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final total = widget.values.fold<double>(0, (a, b) => a + b);
    final external = widget.externalHover;
    final hovered =
        _hovered ??
        (external != null && external >= 0 && external < widget.values.length
            ? external
            : null);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: PieChart(
            PieChartData(
              sections: [
                for (var i = 0; i < widget.values.length; i++)
                  PieChartSectionData(
                    value: widget.values[i],
                    color: widget.colors[i],
                    title: widget.values[i] / total >= 0.08
                        ? '${(widget.values[i] / total * 100).round()}%'
                        : '',
                    radius: widget.radius * (hovered == i ? 1.08 : 1),
                    titleStyle: widget.titleStyle,
                  ),
              ],
              sectionsSpace: widget.sectionSpace,
              centerSpaceRadius: widget.centerSpaceRadius,
              pieTouchData: PieTouchData(
                enabled: true,
                mouseCursorResolver: (event, response) =>
                    response?.touchedSection == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                touchCallback: (event, response) {
                  final next = event.isInterestedForInteractions
                      ? response?.touchedSection?.touchedSectionIndex
                      : null;
                  if (next != _hovered) setState(() => _hovered = next);
                },
              ),
            ),
            duration: Duration.zero,
          ),
        ),
        if (hovered != null && hovered >= 0 && hovered < widget.values.length)
          Positioned(
            top: 4,
            left: 4,
            right: 4,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const ValueKey('pie-hover-tooltip'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 6),
                    ],
                  ),
                  child: Text(
                    '${widget.labels[hovered]}: ${_formatChartValue(widget.values[hovered])}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: widget.tooltipStyle,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _formatChartValue(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

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
  return ColoredBox(
    color: const Color(0xFFE2E8F0),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.biggest.shortestSide;
        if (shortestSide < 48) {
          return Center(
            child: Icon(
              Icons.image_outlined,
              color: const Color(0xFF94A3B8),
              size: shortestSide * 0.65,
            ),
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.image_outlined,
                color: Color(0xFF94A3B8),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.d('Afbeelding'),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
              ),
            ],
          ),
        );
      },
    ),
  );
}
