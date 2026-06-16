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
import '../../services/slide_layout_metrics.dart';
import '../../utils/log.dart';
import 'inline_markdown.dart';

// Slide preview widgets, split into part files by slide type for
// navigability. These parts share this library's imports and private scope.
part 'previews/text_previews.dart';
part 'previews/bullets_previews.dart';
part 'previews/checklist_previews.dart';
part 'previews/table_preview.dart';
part 'previews/media_previews.dart';
part 'previews/code_preview.dart';
part 'previews/chart_preview.dart';
part 'previews/overlays.dart';

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

  /// TLP-classificatie van de presentatie (deck-niveau). Samen met
  /// [slide.tlp] bepaalt dit de zichtbare markering via [effectiveTlp].
  final TlpLevel tlp;

  /// Diagonaal classificatie-watermerk (organisatie-instelling).
  final bool showClassificationWatermark;

  /// Organisatienaam voor het watermerk (uit deck-metadata).
  final String organization;

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
    this.showClassificationWatermark = false,
    this.organization = '',
    this.enableMedia = false,
    this.autoplayMedia = false,
    this.presentationMode = false,
    this.onChecklistItemToggle,
    this.onAudioComplete,
    this.onVideoComplete,
  });

  @override
  Widget build(BuildContext context) {
    final markingTlp = effectiveTlp(deckTlp: tlp, slideTlp: slide.tlp);
    final hasBottomRightTlp =
        markingTlp != TlpLevel.none &&
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
    final markingTlp = effectiveTlp(deckTlp: tlp, slideTlp: slide.tlp);
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
                if (showClassificationWatermark && markingTlp != TlpLevel.none)
                  _ClassificationWatermark(
                    tlp: markingTlp,
                    w: w,
                    organization: organization,
                  ),
                _FooterOverlay(
                  slide: slide,
                  w: w,
                  profile: themeProfile,
                  slideNumber: slideNumber,
                  slideCount: slideCount,
                  tlp: markingTlp,
                ),
                if (markingTlp != TlpLevel.none)
                  _TlpOverlay(
                    tlp: markingTlp,
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
                if (markingTlp != TlpLevel.none)
                  _ClassificationBanner(tlp: markingTlp, w: w),
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
