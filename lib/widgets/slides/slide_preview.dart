import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'mermaid_diagram.dart';
import 'video_playhead_bus.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/cockpit.dart';
import '../../models/deck.dart';
import '../../models/question.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../../models/video_source.dart';
import '../../theme/app_theme.dart';
import '../../services/slide_layout_metrics.dart';
import '../../services/rich_text_layout.dart';
import '../../utils/image_limits.dart';
import '../../utils/log.dart';
import '../../utils/net_guard.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../../utils/project_path.dart';
import 'inline_markdown.dart';
import 'image_zoom_dialog.dart';

// Slide preview widgets, split into part files by slide type for
// navigability. These parts share this library's imports and private scope.
part 'previews/text_previews.dart';
part 'previews/bullets_previews.dart';
part 'previews/bullets_image_preview.dart';
part 'previews/checklist_previews.dart';
part 'previews/table_preview.dart';
part 'previews/media_previews.dart';
part 'previews/media_previews_video.dart';
part 'previews/media_previews_image.dart';
part 'previews/code_preview.dart';
part 'previews/chart_preview.dart';
part 'previews/chart_preview_cartesian.dart';
part 'previews/chart_preview_radar.dart';
part 'previews/cockpit_preview.dart';
part 'previews/question_preview.dart';
part 'previews/timeline_preview.dart';
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

  /// Of online media (URL-afbeeldingen/-video's en embeds) live geladen mag
  /// worden. Standaard uit; de media-renderers tonen anders een placeholder met
  /// de URL i.p.v. naar buiten te bellen.
  final bool allowRemoteMedia;
  const _SlideLinkScope({
    required this.onTapLink,
    this.hasBottomTlp = false,
    this.allowRemoteMedia = false,
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

  static bool allowRemoteMediaOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SlideLinkScope>()
            ?.allowRemoteMedia ??
        false;
  }

  @override
  bool updateShouldNotify(_SlideLinkScope oldWidget) =>
      oldWidget.onTapLink != onTapLink ||
      oldWidget.hasBottomTlp != hasBottomTlp ||
      oldWidget.allowRemoteMedia != allowRemoteMedia;
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
    normalizeRichTextMarkdown(text),
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

double _logoAwareBottomPadding(double defaultPad, double safeBottom) {
  if (safeBottom <= 0) return defaultPad;
  return math.max(defaultPad, safeBottom);
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

  /// Actief cockpit-kleurschema (statuskleuren goed/waarschuwing/kritiek/koud).
  /// Globaal geselecteerd in de instellingen; alleen cockpit-slides gebruiken
  /// het. Default = het ingebouwde standaardschema.
  final CockpitColorScheme cockpitColorScheme;

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

  /// Of online media (URL-afbeeldingen/-video's en YouTube/Vimeo-embeds) live
  /// geladen mag worden. Komt uit de instelling `allowRemoteMedia` (fail-closed:
  /// standaard uit). Staat dit uit, dan tonen de renderers een placeholder met
  /// de URL i.p.v. naar buiten te bellen.
  final bool allowRemoteMedia;

  /// Vergroot grafieklabels voor weergave op afstand in presentatiemodus.
  final bool presentationMode;

  /// Wijzigt tijdens het presenteren een checklistitem. [column] is 0 voor de
  /// eerste/enkele lijst en 1 voor de rechterkolom.
  final void Function(int column, int itemIndex)? onChecklistItemToggle;

  /// Live tabelbewerking tijdens presenteren (toets E op een tabeldia).
  final bool tableEditMode;
  final int? tableEditRow;
  final int? tableEditCol;
  final void Function(int row, int col)? onTableCellSelected;
  final void Function(int row, int col, String value)? onTableCellChanged;

  /// Wordt aangeroepen wanneer de audio van deze slide klaar is (voor de
  /// automatische modus van de presenter).
  final VoidCallback? onAudioComplete;

  /// Wordt aangeroepen wanneer de video van deze slide klaar is.
  final VoidCallback? onVideoComplete;

  /// Pagina binnen een rich-text slide (0-gebaseerd). Alleen relevant bij
  /// [ListStyle.richText] wanneer de tekst over meerdere schermen loopt.
  final int richTextPage;

  /// Toont vorige/volgende-knoppen op rich-text slides met meerdere pagina's.
  final bool showRichTextPageControls;

  /// Callback wanneer de gebruiker van pagina wisselt binnen een rich-text slide.
  final ValueChanged<int>? onRichTextPageChanged;

  /// Live toestand van een vraag-slide tijdens het presenteren (de willekeurig
  /// getoonde opties, selectie, juist/fout, timer). Null in editor/thumbnail →
  /// de vraag wordt in auteursweergave getoond (alle antwoorden, juiste
  /// gemarkeerd).
  final QuestionView? questionView;

  /// Aangeroepen wanneer een antwoordoptie wordt aangetikt (presentatiemodus).
  final ValueChanged<int>? onAnswerSelected;

  /// Aangeroepen bij 'Bevestig' op een meerdere-juiste-antwoorden-vraag.
  final VoidCallback? onAnswerSubmit;

  /// Tijdlijn-slides in stap-voor-stap-modus: hoeveel gebeurtenissen tot nu toe
  /// onthuld zijn (door de presenter aangestuurd). Null = niet in stapmodus →
  /// de tijdlijn toont alles (en tekent zichzelf in bij [presentationMode]).
  final int? timelineRevealedCount;

  /// First number for this slide's numbered list. 1 restarts; a higher value
  /// continues a numbered list from a previous slide (see [numberedListStartFor]).
  /// Callers with the full deck compute it; standalone previews leave it at 1.
  final int numberStart;

  const SlidePreviewWidget({
    super.key,
    required this.slide,
    this.projectPath,
    this.themeProfile = const ThemeProfile(),
    this.cockpitColorScheme = CockpitColorScheme.standard,
    this.onLinkTap,
    this.slideNumber,
    this.slideCount,
    this.tlp = TlpLevel.none,
    this.showClassificationWatermark = false,
    this.organization = '',
    this.enableMedia = false,
    this.autoplayMedia = false,
    this.allowRemoteMedia = false,
    this.presentationMode = false,
    this.onChecklistItemToggle,
    this.tableEditMode = false,
    this.tableEditRow,
    this.tableEditCol,
    this.onTableCellSelected,
    this.onTableCellChanged,
    this.onAudioComplete,
    this.onVideoComplete,
    this.richTextPage = 0,
    this.showRichTextPageControls = false,
    this.onRichTextPageChanged,
    this.questionView,
    this.onAnswerSelected,
    this.onAnswerSubmit,
    this.timelineRevealedCount,
    this.numberStart = 1,
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
      child: _TableEditHost(
        enabled:
            presentationMode && slide.type == SlideType.table && tableEditMode,
        selectedRow: tableEditRow,
        selectedCol: tableEditCol,
        onCellSelected: onTableCellSelected,
        onCellChanged: onTableCellChanged,
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
                allowRemoteMedia: allowRemoteMedia,
                child: _buildSlide(),
              ),
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
        final splitImage = slide.type.splitWithImage;
        final richTextPages =
            showRichTextPageControls &&
                onRichTextPageChanged != null &&
                slideUsesRichText(slide)
            ? richTextPageCountForSlide(
                slide: slide,
                profile: themeProfile,
                splitWithImage: splitImage,
              )
            : 1;
        final showRichTextControls = richTextPages > 1;
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildContent(w),
                // Decoratieve overlays (watermerk, footer, TLP, logo)
                // mogen geen muis/tikken afvangen: anders blokkeren ze de hover
                // van de media-knoppen eronder en het tikken om door te
                // bladeren. Eén gedeelde IgnorePointer i.p.v. per overlay, zodat
                // een nieuwe decoratieve laag dit niet opnieuw kan introduceren.
                // De interactieve overlays staan hier bewust bóvenop.
                IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (showClassificationWatermark &&
                          markingTlp != TlpLevel.none)
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
                      if (themeProfile.logoPath?.isNotEmpty == true &&
                          slide.showLogo)
                        _LogoOverlay(
                          logoPath: themeProfile.logoPath!,
                          projectPath: projectPath,
                          position: themeProfile.logoPosition,
                          size: w * (themeProfile.logoSize / 1280),
                        ),
                    ],
                  ),
                ),
                if (showRichTextControls)
                  _RichTextPageControlsOverlay(
                    slide: slide,
                    w: w,
                    font: fontFamily,
                    profile: themeProfile,
                    tlp: markingTlp,
                    pageIndex: richTextPage.clamp(0, richTextPages - 1),
                    pageCount: richTextPages,
                    onPrevious: richTextPage > 0
                        ? () => onRichTextPageChanged!(richTextPage - 1)
                        : null,
                    onNext: richTextPage < richTextPages - 1
                        ? () => onRichTextPageChanged!(richTextPage + 1)
                        : null,
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
          richTextPage: richTextPage,
          showRichTextPageControls: showRichTextPageControls,
          onRichTextPageChanged: onRichTextPageChanged,
          numberStart: numberStart,
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
          richTextPage: richTextPage,
          showRichTextPageControls: showRichTextPageControls,
          onRichTextPageChanged: onRichTextPageChanged,
          numberStart: numberStart,
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
        return _videoPreview(w);
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
      case SlideType.cockpit:
        return _CockpitPreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
          scheme: cockpitColorScheme,
          presentationMode: presentationMode,
        );
      case SlideType.question:
        return _QuestionPreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
          presentationMode: presentationMode,
          view: questionView,
          onAnswerSelected: onAnswerSelected,
          onAnswerSubmit: onAnswerSubmit,
        );
      case SlideType.timeline:
        return _TimelinePreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
          presentationMode: presentationMode,
          revealedCount: timelineRevealedCount,
        );
    }
  }

  Widget _videoPreview(double w) {
    final source = VideoSource.parse(slide.videoPath);
    if (source.isEmbed) {
      return _VideoEmbedPreview(
        slide: slide,
        source: source,
        w: w,
        font: fontFamily,
        profile: themeProfile,
        autoplay: autoplayMedia && slide.videoAutoplay,
        allowRemoteMedia: allowRemoteMedia,
        onComplete: onVideoComplete,
      );
    }
    return _VideoPreview(
      slide: slide,
      source: source,
      w: w,
      projectPath: projectPath,
      font: fontFamily,
      profile: themeProfile,
      autoplay: autoplayMedia && slide.videoAutoplay,
      allowRemoteMedia: allowRemoteMedia,
      onComplete: onVideoComplete,
    );
  }
}

String? _resolvePath(String path, String? projectPath) =>
    resolveSlideAssetPath(path, projectPath);

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
    case SlideType.cockpit:
      return w * 0.06;
    case SlideType.twoBullets:
      return w * 0.065;
    case SlideType.table:
      return w * 0.06;
    case SlideType.bulletsImage:
      return w * 0.038;
    case SlideType.question:
      return w * 0.06;
    case SlideType.timeline:
      return w * 0.06;
    case SlideType.quote:
      return w * 0.08;
    default:
      // Beeld/video: geen tekstmarge om mee uit te lijnen.
      return w * 0.04;
  }
}
