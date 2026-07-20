import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/privacy_disposition.dart';
import '../../models/findings_summary_spec.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../../services/cvss/cvss4.dart';
import '../../services/image_service.dart';
import '../../services/slide_layout_metrics.dart';
import '../../services/split_run.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/info_safety_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../dialogs/add_slide_dialog.dart';
import '../editors/slide_editor_registry.dart';
import '../editors/slide_type_help.dart';
import '../panels/slide_quality_panel.dart';
import '../editors/markdown_deck_editor.dart';
import '../../utils/page_scoped_notes.dart';
import '../panels/preview_panel.dart';
import '../markdown_notes_editor.dart';

part 'editor_panel_controls.dart';
part 'editor_panel_slide_settings.dart';
part 'editor_panel_notes.dart';

class EditorPanel extends ConsumerWidget {
  const EditorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Alleen de deck-velden die dit paneel echt gebruikt (deck + revision):
    // wissels in isDirty/canUndo/canRedo hoeven de hele editorkolom niet te
    // herbouwen.
    final deck = ref.watch(deckProvider.select((s) => s.deck))!;
    final revision = ref.watch(deckProvider.select((s) => s.revision));
    final editor = ref.watch(editorProvider);

    final idx = editor.selectedIndex.clamp(0, deck.slides.length - 1);
    final slide = deck.slides[idx];

    final deckNotifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);
    final imgService = ref.read(imageServiceProvider);
    final richTextPage = ref.watch(richTextPreviewPageProvider);
    final richTextPages = richTextPageCount(slide, deck.themeProfile);
    final multiPageNotes = richTextPages > 1;

    void update(Slide updated) => deckNotifier.updateSlide(idx, updated);

    final settings = ref.watch(settingsProvider);
    // Gate de informatieveiligheid-slidetypes in de TYPE-kiezer net als in
    // 'Slide toevoegen', zodat beide plekken exact dezelfde types aanbieden.
    final revealed = ref.watch(infoSafetyRevealProvider);

    // Zoekpaden voor de afbeeldingencarousel: projectmap eerst, dan alle
    // bibliotheken als (recursief gescande) zoekwortels.
    final searchPaths = [
      if (deck.projectPath != null) '${deck.projectPath}/images',
      if (deck.projectPath != null) deck.projectPath!,
      ...settings.libraryPaths,
    ];

    if (editor.mode == EditorMode.markdown) {
      return _markdownEditor(ref, revision, editor, deck);
    }

    // De tekstvelden cachen hun inhoud in eigen controllers en verversen alleen
    // op slide-id. Bij undo/redo verandert [revision], waardoor deze subtree
    // remount en de velden de teruggedraaide inhoud tonen.
    return KeyedSubtree(
      key: ValueKey('editor-rev-$revision'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Kopregel: type, stijl, hulp en slidekwaliteit op één regel ─────
          _EditorHeaderBar(
            slide: slide,
            profiles: settings.themeProfiles,
            activeProfile: deck.themeProfile,
            defaultProfile: settings.themeProfile,
            revealInfoSafety: revealed,
            onTypeChanged: (newType) {
              if (newType == slide.type) return;
              update(_convertSlideType(slide, newType));
            },
            onProfileChanged: (profile) =>
                deckNotifier.updateThemeProfile(profile),
            onDefaultProfileRequested: () =>
                deckNotifier.updateThemeProfile(settings.themeProfile),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildEditor(
                  slide,
                  update,
                  imgService,
                  searchPaths,
                  deck.projectPath,
                  (variants) {
                    final first = deckNotifier.insertSlides(
                      variants,
                      afterIndex: idx,
                    );
                    if (first >= 0) editorNotifier.select(first);
                  },
                  themeAnimationDurationMs:
                      deck.themeProfile.animationDurationMs,
                  previousSlideIsNumbered:
                      idx > 0 && isNumberedListSlide(deck.slides[idx - 1]),
                  canContinueSplit: canContinueSplitFrom(deck.slides, idx),
                  // Only the findingsSummary editor uses it; skip the parse for
                  // every other type.
                  deckFindingSeverities: slide.type == SlideType.findingsSummary
                      ? deckFindingSeverities(deck.slides)
                      : const <Cvss4Severity>[],
                  deckResolvedCount: slide.type == SlideType.findingsSummary
                      ? deckRetestResolvedCount(deck.slides)
                      : 0,
                  nestedInScrollView: true,
                  onSplitVideo: (atMs) {
                    deckNotifier.splitVideoSlide(idx, atMs);
                    // Spring naar het nieuwe vervolgdeel zodat je het meteen ziet.
                    editorNotifier.select(idx + 1);
                  },
                ),
                ..._belowEditorControls(
                  slide: slide,
                  update: update,
                  deckNotifier: deckNotifier,
                  imageService: imgService,
                  deck: deck,
                  richTextPage: richTextPage,
                  richTextPages: richTextPages,
                  multiPageNotes: multiPageNotes,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// De controls onder de type-specifieke editor: eerst het inklapbare blok met
  /// slide-instellingen (audio, logo, footer, tabel, timing, TLP), daarna de
  /// notitievelden. Losgetrokken uit [build] om die binnen de lengtegrens te
  /// houden.
  List<Widget> _belowEditorControls({
    required Slide slide,
    required ValueChanged<Slide> update,
    required DeckNotifier deckNotifier,
    required ImageService imageService,
    required Deck deck,
    required int richTextPage,
    required int richTextPages,
    required bool multiPageNotes,
  }) {
    // Volgorde: eerst de slide-specifieke inhoud (hierboven, via _buildEditor),
    // dan de aanvullende instellingen als inklapbaar blok, dan de notities.
    return [
      const Divider(height: 1),
      _SlideSettingsSection(
        slide: slide,
        onUpdate: update,
        imageService: imageService,
        deck: deck,
      ),
      const Divider(height: 1),
      _NotesField(
        slide: slide,
        richTextPage: richTextPage,
        richTextPageCount: richTextPages,
        onUpdate: update,
      ),
      const Divider(height: 1),
      _UserNotesField(
        slide: slide,
        note:
            deckNotifier.userNoteForSlide(
              slide.id,
              pageIndex: richTextPage,
              multiPage: multiPageNotes,
            ) ??
            '',
        richTextPage: richTextPage,
        richTextPageCount: richTextPages,
        onChanged: (text) => deckNotifier.setUserNoteForSlide(
          slide.id,
          text,
          pageIndex: richTextPage,
          multiPage: multiPageNotes,
        ),
      ),
    ];
  }

  Widget _markdownEditor(
    WidgetRef ref,
    int revision,
    EditorState editor,
    Deck deck,
  ) {
    final deckNotifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);
    final scope = editor.markdownScope;
    final isSlide = scope == MarkdownScope.slide;
    final idx = editor.selectedIndex.clamp(0, deck.slides.length - 1);
    return MarkdownDeckEditor(
      // Verse instantie na undo/redo zodat de markdown opnieuw wordt geladen.
      // Bij wisselen van omvang of actieve slide blijft de widget bestaan
      // (zodat de scope-toggle vloeiend animeert) en herlaadt hij zijn inhoud
      // via didUpdateWidget op basis van de veranderde initialContent.
      key: ValueKey('md-$revision'),
      initialContent: isSlide
          ? deckNotifier.generateSlideMarkdown(idx)
          : deckNotifier.generateMarkdown(),
      scope: scope,
      slideNumber: idx + 1,
      slideCount: deck.slides.length,
      onScopeChanged: editorNotifier.setMarkdownScope,
      onApply: (md) {
        final ok = isSlide
            ? deckNotifier.applySlideMarkdown(idx, md)
            : deckNotifier.applyMarkdown(md);
        editorNotifier.setParseError(!ok);
        return ok;
      },
      parseError: editor.parseError,
      onExitMarkdown: () => editorNotifier.setMode(EditorMode.visual),
    );
  }

  /// Re-type a slide while carrying over text fields where they make sense.
  static Slide _convertSlideType(Slide slide, SlideType newType) {
    final keepsBullets =
        newType == SlideType.bullets ||
        newType == SlideType.twoBullets ||
        newType == SlideType.bulletsImage;
    final keepsImage =
        newType == SlideType.bulletsImage ||
        newType == SlideType.image ||
        newType == SlideType.twoImages ||
        newType == SlideType.question;
    return Slide(
      id: slide.id,
      type: newType,
      title: slide.title,
      subtitle: slide.subtitle,
      bullets: newType == SlideType.timeline
          ? (slide.bullets.isNotEmpty
                ? slide.bullets
                : timelineEventsToBullets(defaultTimelineEvents()))
          : keepsBullets
          ? (slide.bullets.isNotEmpty ? slide.bullets : [''])
          : const [],
      bullets2: newType == SlideType.twoBullets
          ? (slide.bullets2.isNotEmpty ? slide.bullets2 : [''])
          : const [],
      listStyle: slide.listStyle,
      showChecklistProgress: slide.showChecklistProgress,
      imagePath: keepsImage ? slide.imagePath : '',
      imagePath2: newType == SlideType.twoImages ? slide.imagePath2 : '',
      imageCaption: keepsImage ? slide.imageCaption : '',
      imageCaption2: newType == SlideType.twoImages ? slide.imageCaption2 : '',
      videoPath: newType == SlideType.video ? slide.videoPath : '',
      videoAutoplay: slide.videoAutoplay,
      audioPath: slide.audioPath,
      audioAutoplay: slide.audioAutoplay,
      quote: slide.quote,
      quoteAuthor: slide.quoteAuthor,
      customMarkdown: newType == SlideType.cockpit
          ? (slide.type == SlideType.cockpit
                ? slide.customMarkdown
                : Slide.create(SlideType.cockpit).customMarkdown)
          : newType == SlideType.question
          ? (slide.type == SlideType.question
                ? slide.customMarkdown
                : Slide.create(SlideType.question).customMarkdown)
          : slide.customMarkdown,
      codeLanguage: slide.codeLanguage,
      cssClass: slide.cssClass,
      notes: slide.notes,
      advanceDuration: slide.advanceDuration,
      imageSize: slide.imageSize,
      showLogo: slide.showLogo,
      showFooter: slide.showFooter,
      tlp: slide.tlp,
      tableRows: newType == SlideType.table
          ? (slide.tableRows.isNotEmpty
                ? slide.tableRows
                : const [
                    // Lege koppen; de editor toont 'Kolom 1' etc. als hint.
                    ['', ''],
                    ['', ''],
                  ])
          : const [],
      timelineLayout: slide.timelineLayout,
      timelineReveal: slide.timelineReveal,
    );
  }

  Widget _buildEditor(
    Slide slide,
    ValueChanged<Slide> onUpdate,
    ImageService imgService,
    List<String> searchPaths,
    String? captionBasePath,
    ValueChanged<List<Slide>> onAddChartVariants, {
    required int themeAnimationDurationMs,
    bool previousSlideIsNumbered = false,
    bool canContinueSplit = false,
    bool nestedInScrollView = false,
    void Function(int atMs)? onSplitVideo,
    List<Cvss4Severity> deckFindingSeverities = const [],
    int deckResolvedCount = 0,
  }) {
    return slideEditorBuilders[slide.type]!(
      SlideEditorContext(
        slide: slide,
        onUpdate: onUpdate,
        imageService: imgService,
        searchPaths: searchPaths,
        captionBasePath: captionBasePath,
        onAddChartVariants: onAddChartVariants,
        themeAnimationDurationMs: themeAnimationDurationMs,
        previousSlideIsNumbered: previousSlideIsNumbered,
        canContinueSplit: canContinueSplit,
        nestedInScrollView: nestedInScrollView,
        onSplitVideo: onSplitVideo,
        deckFindingSeverities: deckFindingSeverities,
        deckResolvedCount: deckResolvedCount,
      ),
    );
  }
}

// ── Editor toolbar: slide-type + stijlprofiel dropdowns ──────────────────────

/// Toolbar icon per slide type. A guard test asserts every [SlideType] is here.
const Map<SlideType, IconData> slideTypeIcons = {
  SlideType.title: Icons.title,
  SlideType.section: Icons.bookmark_outline,
  SlideType.bullets: Icons.format_list_bulleted,
  SlideType.twoBullets: Icons.view_column_outlined,
  SlideType.bulletsImage: Icons.view_agenda_outlined,
  SlideType.twoImages: Icons.auto_stories_outlined,
  SlideType.image: Icons.image_outlined,
  SlideType.video: Icons.movie_outlined,
  SlideType.quote: Icons.format_quote_outlined,
  SlideType.table: Icons.table_chart_outlined,
  SlideType.freeMarkdown: Icons.code,
  SlideType.code: Icons.terminal,
  SlideType.chart: Icons.bar_chart,
  SlideType.cockpit: Icons.speed_outlined,
  SlideType.scorecard: Icons.scoreboard_outlined,
  SlideType.question: Icons.quiz_outlined,
  SlideType.timeline: Icons.timeline_outlined,
  SlideType.finding: Icons.bug_report_outlined,
  SlideType.findingsSummary: Icons.summarize_outlined,
  SlideType.checklist: Icons.checklist,
  SlideType.scopeMatrix: Icons.grid_on_outlined,
  SlideType.signOff: Icons.draw_outlined,
};
