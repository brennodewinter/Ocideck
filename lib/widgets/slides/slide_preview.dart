import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import '../../services/improvement/canvas_layout.dart';
import '../../services/improvement/canvas_slide.dart';
import '../../services/improvement/canvas_spec.dart';
import '../../services/improvement/tree_layout.dart';
import '../../services/improvement/tree_slide.dart';
import '../../services/improvement/tree_spec.dart';
import '../../services/improvement/flow_layout.dart';
import '../../services/improvement/flow_slide.dart';
import '../../services/improvement/flow_spec.dart';
import '../../services/improvement/chart_derivation.dart';
import '../../services/improvement/matrix_layout.dart';
import '../../services/improvement/matrix_slide.dart';
import '../../services/scene/scene.dart';
import '../slides/previews/scene_painter.dart';
import '../../models/checklist_spec.dart';
import '../../models/cockpit.dart';
import '../../models/cvss_builder.dart';
import '../../models/deck.dart';
import '../../models/improvement_y01.dart';
import '../../models/privacy_disposition.dart';
import '../../models/document_signature.dart';
import '../../models/finding_spec.dart';
import '../../models/findings_summary_spec.dart';
import '../../models/question.dart';
import '../../models/control_status_spec.dart';
import '../../models/scope_matrix_spec.dart';
import '../../models/asset_overview_spec.dart';
import '../../models/discoveries_spec.dart';
import '../../models/scorecard_spec.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../../models/video_source.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';
import '../../services/cvss/cvss4.dart';
import '../../services/finding_context_score.dart';
import '../../services/display_window_service.dart';
import '../../services/markdown_body_blocks.dart';
import '../../services/slide_layout_metrics.dart';
import '../../services/rich_text_layout.dart';
// De split-run-metingen zijn services (headless rekenwerk), maar hun natuurlijke
// vindplek is deze bibliotheek: elke aanroeper vraagt ze op naast
// `SlidePreviewWidget.fitScaleOverride`.
import '../../services/split_run.dart';
export '../../services/split_run.dart'
    show invalidateSplitRunLayout, sharedSplitFitScale, splitRunMemberScale;
import '../../services/web_asset_store.dart';
import '../../utils/bundled_asset.dart';
import '../../utils/image_focal.dart';
import '../../utils/mem_asset_blob.dart';
import '../../utils/jaro_winkler.dart';
import '../../utils/image_limits.dart';
import '../../utils/media_fetch.dart';
import '../../utils/table_dates.dart';
import '../../utils/text_diff.dart';
import '../../utils/log.dart';
import '../../utils/lru_cache.dart';
import '../../utils/net_guard.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../../utils/project_path.dart';
import '../../utils/title_contrast.dart' show kTitleOverlayAlpha;
import '../document_signature_view.dart' show decodeEmbeddedSignatureImage;
import '../privacy_badge.dart' show privacyKatSvg;
import '../../utils/inline_markdown.dart';
import 'inline_markdown.dart';
import 'image_zoom_dialog.dart';

// Slide previews split by type; parts share this library's private scope.
part 'previews/preview_scaffold.dart';
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
part 'previews/chart_preview_extra.dart';
part 'previews/chart_preview_bullet.dart';
part 'previews/chart_preview_improvement.dart';
part 'previews/cockpit_preview.dart';
part 'previews/cockpit_painter_support.dart';
part 'previews/question_preview.dart';
part 'previews/question_preview_answers.dart';
part 'previews/timeline_preview.dart';
part 'previews/timeline_fit.dart';
part 'previews/scorecard_preview.dart';
part 'previews/asset_overview_preview.dart';
part 'previews/discoveries_preview.dart';
part 'previews/checklist_preview.dart';
part 'previews/finding_preview.dart';
part 'previews/scope_matrix_preview.dart';
part 'previews/control_status_preview.dart';
part 'previews/findings_summary_preview.dart';
part 'previews/signoff_preview.dart';
part 'previews/matrix_preview.dart';
part 'previews/canvas_preview.dart';
part 'previews/tree_preview.dart';
part 'previews/flow_preview.dart';
part 'previews/improvement_dispatch.dart';
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

  /// Of de media op deze slide door de privacyprojectie is weggehaald.
  ///
  /// Reist mee in de scope en niet als parameter langs de renderers, omdat het
  /// anders precies dáár misgaat waar het al eens misging: er zijn negen
  /// aanroepplekken van `_resolvedImage`, en een tiende die de vlag vergeet
  /// levert stilzwijgend weer een grijs "Afbeelding"-vak op een geredigeerde
  /// slide. Zie [Slide.mediaRedacted].
  final bool mediaRedacted;

  /// Bovengrens voor de decodeerresolutie van een dia-afbeelding, of null voor
  /// de gewone cap.
  ///
  /// Reist mee in de scope om precies de reden die hierboven bij
  /// [mediaRedacted] staat: er zijn negen aanroepplekken van `_resolvedImage`,
  /// en een tiende die de parameter vergeet decodeert stilzwijgend weer op
  /// volle resolutie.
  ///
  /// Alleen de slidestrook zet hem. Een telefoonfoto van 4032×3024 kost
  /// gedecodeerd bijna 49 MiB; tien zichtbare thumbnails met verschillende
  /// foto's zijn een halve gigabyte aan levende bitmaps voor een strook van
  /// ~180 px breed. Op desktop is dat een geheugengrafiek die niemand ziet, op
  /// web valt de tab om — en web is de demo-route (#612).
  final int? decodeMaxEdge;

  /// Wat er gebeurt als de gebruiker vanaf een geblokkeerde-online-media-
  /// placeholder online media wil aanzetten: een sprong naar de instelling.
  /// Alleen de editor-preview zet dit; in de presenter, thumbnails, export en de
  /// play-only-webdemo is het null en verschijnt er geen knop — daar zijn de
  /// instellingen niet te openen (#852).
  final VoidCallback? onEnableOnlineMedia;

  const _SlideLinkScope({
    required this.onTapLink,
    this.hasBottomTlp = false,
    this.allowRemoteMedia = false,
    this.mediaRedacted = false,
    this.decodeMaxEdge,
    this.onEnableOnlineMedia,
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

  static bool mediaRedactedOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SlideLinkScope>()
            ?.mediaRedacted ??
        false;
  }

  static int? decodeMaxEdgeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SlideLinkScope>()
      ?.decodeMaxEdge;

  static VoidCallback? onEnableOnlineMediaOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SlideLinkScope>()
      ?.onEnableOnlineMedia;

  @override
  bool updateShouldNotify(_SlideLinkScope oldWidget) =>
      oldWidget.onTapLink != onTapLink ||
      oldWidget.hasBottomTlp != hasBottomTlp ||
      oldWidget.allowRemoteMedia != allowRemoteMedia ||
      oldWidget.mediaRedacted != mediaRedacted ||
      oldWidget.decodeMaxEdge != decodeMaxEdge ||
      oldWidget.onEnableOnlineMedia != onEnableOnlineMedia;
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

EdgeInsets _logoSafeInsets(double w, ThemeProfile profile) {
  final (top, bottom) = logoSafeReserveEdges(w, profile);
  return EdgeInsets.only(top: top, bottom: bottom);
}

double _logoAwareBottomPadding(double defaultPad, double safeBottom) {
  if (safeBottom <= 0) return defaultPad;
  return math.max(defaultPad, safeBottom);
}

/// De dikte van een voortgangsbalk in een preview, afgeleid van de breedte
/// waarop de dia wordt opgemaakt.
///
/// Waarom niet gewoon `w * 0.014`: `LinearProgressIndicator` eist
/// `minHeight > 0`, en een preview wordt vaker *gemeten* dan getekend — een
/// inklappend paneel of een animatie die bij nul begint levert breedte nul, en
/// dan is die afgeleide dikte exact nul. De assertie die dan afgaat noemt de
/// dia niet en de breedte al helemaal niet. Een haarlijn is bij die breedte
/// het juiste antwoord: te zien is er toch niets, want de balk is zelf nul
/// breed, en de meting loopt door (#782).
double _progressBarThickness(double w) => math.max(0.5, w * 0.014);

/// Content-padding voor bulletslides: logo-safe bovenrand en de
/// checklist/logo-bewuste onderrand uit [bulletsSlideBottomInset]. [safe]
/// blijft bij de aanroeper (sommige previews hebben hem daarna nog nodig, en
/// split-slides gebruiken andere insets). Stond in vijf previews als
/// identiek blok uitgeschreven.
EdgeInsets _bulletsPadding({
  required double w,
  required Slide slide,
  required ThemeProfile profile,
  required EdgeInsets safe,
  required double pad,
  required double vPad,
  double? rightPad,
}) {
  return EdgeInsets.fromLTRB(
    pad,
    vPad + safe.top,
    rightPad ?? pad,
    bulletsSlideBottomInset(
      w: w,
      slide: slide,
      profile: profile,
      defaultBottomPad: vPad,
      safeBottom: safe.bottom,
    ),
  );
}

EdgeInsets _splitTextLogoSafeInsets(double w, ThemeProfile profile) {
  final (top, bottom) = logoSafeReserveEdges(w, profile, splitText: true);
  return EdgeInsets.only(top: top, bottom: bottom);
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

  /// Bovengrens voor de decodeerresolutie van dia-afbeeldingen, in pixels op de
  /// langste zijde. Null = de gewone cap.
  ///
  /// Alleen de slidestrook zet dit (#612). Preview, presentatiemodus en de
  /// rasteraar tekenen op ware grootte en houden dus null: daar is de
  /// resolutie het product.
  final int? decodeMaxEdge;

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

  /// Deck-brede visuele handtekening (§8 A1), gerenderd door de `signOff`-slide.
  /// Deck-niveau ambient context — net als [tlp]/[organization] doorgegeven door
  /// aanroepers die het deck hebben; null in losse previews (dan toont de
  /// sign-off-slide een placeholder).
  final DocumentSignature? deckSignature;

  /// De verzegeldatum van het deck (`ocideck_seal_at`) als het is afgerond, anders
  /// leeg. De `signOff`-slide toont daarmee "Verzegeld op …".
  final String sealedAt;

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

  /// Of een te groot mermaid-diagram hier zoombaar/scrollbaar is (#872/#930);
  /// opt-in, alleen de presentatie zet het aan (elders passend verkleinen).
  final bool scrollableMermaid;

  /// Gedeelde kijk-controller (zoom + scrollpositie) voor een groot mermaid-
  /// diagram; de presentatie deelt er één met het publieksvenster (#930).
  final MermaidViewController? mermaidViewController;

  /// Gebaren + zoomknoppen aan (presentator) of alleen meespiegelen (beamer).
  final bool mermaidInteractive;

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
  ///
  /// Voor oppervlakken die zélf door de pagina's bladeren (het editorpaneel, de
  /// presentator). Een oppervlak dat slides opsomt in plaats van doorbladert —
  /// de export — krijgt de pagina mee op de slide zelf; zie [_effectivePage].
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

  /// Aangeroepen terwijl de kijker een antwoord typt (vraagsoort 'getypt
  /// antwoord'). Null → het invoerveld staat er wel, maar is niet te bewerken:
  /// zo spiegelt het beamervenster wat er op de presentator zijn scherm getypt
  /// wordt, zonder dat er op twee plekken tegelijk getypt kan worden.
  final ValueChanged<String>? onAnswerTextChanged;

  /// Tijdlijn-slides in stap-voor-stap-modus: hoeveel gebeurtenissen tot nu toe
  /// onthuld zijn (door de presenter aangestuurd). Null = niet in stapmodus →
  /// de tijdlijn toont alles (en tekent zichzelf in bij [presentationMode]).
  final int? timelineRevealedCount;

  /// First number for this slide's numbered list. 1 restarts; a higher value
  /// continues a numbered list from a previous slide (see [numberedListStartFor]).
  /// Callers with the full deck compute it; standalone previews leave it at 1.
  final int numberStart;

  /// When this slide is one page of a multi-page split (see [Slide.continuesSplit]),
  /// the one font scale shared by every page of that run — the size of the
  /// fullest page — so the split list keeps a consistent size. Null → the
  /// slide sizes its own text independently (the standalone default). Callers
  /// with the full deck compute it via [sharedSplitFitScale].
  final double? fitScaleOverride;

  /// The deck's scope-object → CIA-rating index (see [deckScopeCiaIndex]). A
  /// `finding` header whose scope object is rated shows a context (environmental)
  /// score derived from it. Callers with the full deck build it once and pass it
  /// to every slide; standalone previews leave it empty (base score only).
  final Map<String, CiaRating> scopeCia;

  /// The language the report is written in ([Deck.language], MIAUW EIS 2.3), or
  /// empty when it is not recorded. A `finding` renders its section headings in
  /// this language while the Markdown keeps its stable English anchors
  /// (PENTEST_MIAUW §12.3). Empty resolves through the `en` fallback back to the
  /// anchors, so an unrecorded language renders exactly what the file says.
  ///
  /// NOT the interface language: a Dutch tester writing for an international
  /// client produces an English report from a Dutch UI.
  final String reportLanguage;

  /// Deck-level primary Y metric (**Y-01**) for chart limit resolution when
  /// a chart slide sets `yRef: "Y-01"`. Empty when the preview has no deck.
  final ImprovementY01Metric improvementY01;

  /// Sprong naar de online-media-instelling vanaf een geblokkeerde-media-
  /// placeholder (#852). Alleen de editor-preview zet dit; elders (presenter,
  /// thumbnails, export, play-only) blijft het null en verschijnt er geen knop.
  final VoidCallback? onEnableOnlineMedia;

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
    this.deckSignature,
    this.sealedAt = '',
    this.enableMedia = false,
    this.autoplayMedia = false,
    this.allowRemoteMedia = false,
    this.presentationMode = false,
    this.scrollableMermaid = false,
    this.mermaidViewController,
    this.mermaidInteractive = true,
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
    this.onAnswerTextChanged,
    this.timelineRevealedCount,
    this.numberStart = 1,
    this.fitScaleOverride,
    this.scopeCia = const {},
    this.reportLanguage = '',
    this.improvementY01 = ImprovementY01Metric.empty,
    this.decodeMaxEdge,
    this.onEnableOnlineMedia,
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
    return MermaidRenderScope(
      scrollable: scrollableMermaid,
      viewController: mermaidViewController,
      interactive: mermaidInteractive,
      child: MediaQuery.withNoTextScaling(
        child: _TableEditHost(
          enabled:
              presentationMode &&
              slide.type == SlideType.table &&
              tableEditMode,
          selectedRow: tableEditRow,
          selectedCol: tableEditCol,
          onCellSelected: onTableCellSelected,
          onCellChanged: onTableCellChanged,
          child: _ChecklistInteractionHost(
            // Op een geredigeerde slide is aanvinken uitgeschakeld: de presenter
            // schrijft de hele (zwartgelakte) slide terug. Zie
            // [Slide.contentRedacted].
            enabled:
                presentationMode &&
                onChecklistItemToggle != null &&
                !slide.contentRedacted,
            onToggle: onChecklistItemToggle,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: DefaultTextStyle(
                style: TextStyle(
                  color: AppTheme.parseHexColor(themeProfile.textColor),
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.normal,
                  fontStyle: FontStyle.normal,
                ),
                child: _SlideLinkScope(
                  onTapLink: onLinkTap,
                  hasBottomTlp: hasBottomRightTlp,
                  allowRemoteMedia: allowRemoteMedia,
                  mediaRedacted: slide.mediaRedacted,
                  decodeMaxEdge: decodeMaxEdge,
                  onEnableOnlineMedia: onEnableOnlineMedia,
                  child: _buildSlide(slide.projectionWithViewLimit()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// De pagina die deze render toont: de vaste pagina van een uitgeklapte
  /// render-kopie ([Slide.renderPage]) gaat vóór, anders de pagina waar het
  /// oppervlak zelf naartoe gebladerd heeft. De twee sluiten elkaar uit — een
  /// uitgeklapte kopie komt alleen voor waar niemand bladert.
  int get _effectivePage =>
      slide.renderPage > 0 ? slide.renderPage : richTextPage;

  Widget _buildSlide(Slide slide) {
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
                _buildContent(slide, w),
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
                      // Het privacy-shield. De effectieve stand is door de
                      // projectie op de slide gezet, dus elk renderoppervlak
                      // krijgt de badge automatisch — er is geen parameter om te
                      // vergeten.
                      if (slide.privacy == PrivacyDisposition.shield)
                        _OciWachtOverlay(
                          w: w,
                          tlpTakesLeft:
                              markingTlp != TlpLevel.none &&
                              themeProfile.logoPath?.isNotEmpty == true &&
                              slide.showLogo &&
                              themeProfile.logoPosition == 'bottom-right',
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

  Widget _buildContent(Slide slide, double w) {
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
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
        );
      case SlideType.bullets:
        return _BulletsPreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
          richTextPage: _effectivePage,
          numberStart: numberStart,
          fitScaleOverride: fitScaleOverride,
        );
      case SlideType.twoBullets:
        return _TwoBulletsPreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
          fitScaleOverride: fitScaleOverride,
        );
      case SlideType.bulletsImage:
        return _BulletsImagePreview(
          slide: slide,
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
          richTextPage: _effectivePage,
          numberStart: numberStart,
          fitScaleOverride: fitScaleOverride,
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
        return _videoPreview(slide, w);
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
          y01: improvementY01,
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
          onAnswerTextChanged: onAnswerTextChanged,
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
      case SlideType.scorecard:
      case SlideType.assets:
      case SlideType.discoveries:
        return _reportingPreview(slide, slide.type, w);
      case SlideType.checklist:
      case SlideType.finding:
      case SlideType.findingsSummary:
      case SlideType.scopeMatrix:
      case SlideType.signOff:
        return _securityPreview(slide, w);
      case SlideType.matrix:
      case SlideType.canvas:
      case SlideType.tree:
      case SlideType.flow:
      case SlideType.phaseGate:
        return _improvementPreview(slide, w);
      case SlideType.controlStatus:
        return _ControlStatusPreview(
          slide: slide,
          w: w,
          font: fontFamily,
          profile: themeProfile,
        );
    }
  }

  /// Previews for the recurring-report layouts (`scorecard`, `assets`,
  /// `discoveries`). Split out of [_buildContent] for the length ratchet, the
  /// same reason [_securityPreview] exists — and so a further reporting type
  /// costs the dispatch switch nothing.
  Widget _reportingPreview(
    Slide slide,
    SlideType type,
    double w,
  ) => switch (type) {
    SlideType.scorecard => _ScorecardPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
    ),
    SlideType.assets => _AssetOverviewPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
    ),
    SlideType.discoveries => _DiscoveriesPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
    ),
    // Only ever called for the three above; the default keeps the switch total.
    _ => const SizedBox.shrink(),
  };

  /// Preview for the Informatieveiligheid slide types: all five (`finding`
  /// P1-FIND, `checklist` P1-CHK, `scopeMatrix` P1-SCOPE, `findingsSummary`
  /// P1-SUM, `signOff` P1-SIGN) have a structured preview of their own.
  ///
  /// Er stond hier een steigervoorbeeld (`_ScaffoldPreview`, 35 regels) als
  /// terugval voor een type dat er nog geen had. Alle vijf hebben er inmiddels
  /// een, en de switch hierboven is uitputtend over `SlideType` — een nieuw
  /// type moet daar expliciet bij, waar de compiler het afdwingt. De terugval
  /// was dus onbereikbaar geworden: dertig regels die niemand ooit zag en die
  /// geen test rood kon krijgen. De default blijft alleen staan om de switch
  /// totaal te houden, net als in [_reportingPreview].
  Widget _securityPreview(Slide slide, double w) => switch (slide.type) {
    SlideType.finding => _FindingPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
      scopeCia: scopeCia,
      reportLanguage: reportLanguage,
    ),
    SlideType.checklist => _ChecklistPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
    ),
    SlideType.scopeMatrix => _ScopeMatrixPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
    ),
    SlideType.findingsSummary => _FindingsSummaryPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
    ),
    SlideType.signOff => _SignOffPreview(
      slide: slide,
      w: w,
      font: fontFamily,
      profile: themeProfile,
      signature: deckSignature,
      sealedAt: sealedAt,
    ),
    // Alleen voor de vijf hierboven aangeroepen; de default houdt de switch
    // totaal.
    _ => const SizedBox.shrink(),
  };

  Widget _videoPreview(Slide slide, double w) {
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
    case SlideType.tree:
    case SlideType.flow:
    case SlideType.phaseGate:
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
    // De rest deelt de standaardmarge — beeld en video hebben geen tekst om
    // mee uit te lijnen, de overige typen tekenen hun eigen padding. Bewust
    // uitgeschreven en niet als `default:`: die zet het compiler-vangnet uit,
    // en dan krijgt slidetype #25 stilzwijgend deze waarde toegewezen terwijl
    // zijn footer scheef onder de inhoud komt te staan.
    case SlideType.title ||
        SlideType.section ||
        SlideType.twoImages ||
        SlideType.image ||
        SlideType.video ||
        SlideType.scorecard ||
        SlideType.assets ||
        SlideType.discoveries ||
        SlideType.finding ||
        SlideType.findingsSummary ||
        SlideType.checklist ||
        SlideType.scopeMatrix ||
        SlideType.controlStatus ||
        SlideType.signOff ||
        SlideType.matrix ||
        SlideType.canvas ||
        SlideType.tree ||
        SlideType.flow:
      return w * 0.04;
  }
}
