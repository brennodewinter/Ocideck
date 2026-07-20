import 'package:flutter/material.dart';

import '../../models/slide.dart';
import '../../services/cvss/cvss4.dart';
import '../../services/image_service.dart';
import 'actions_editor.dart';
import 'asset_overview_editor.dart';
import 'bullets_editor.dart';
import 'bullets_image_editor.dart';
import 'chart_editor.dart';
import 'checklist_editor.dart';
import 'code_editor.dart';
import 'cockpit_editor.dart';
import 'finding_editor.dart';
import 'findings_summary_editor.dart';
import 'free_markdown_editor.dart';
import 'image_slide_editor.dart';
import 'question_editor.dart';
import 'quote_editor.dart';
import 'scope_matrix_editor.dart';
import 'scorecard_editor.dart';
import 'section_editor.dart';
import 'signoff_editor.dart';
import 'table_editor.dart';
import 'timeline_editor.dart';
import 'title_editor.dart';
import 'two_bullets_editor.dart';
import 'two_images_editor.dart';
import 'video_slide_editor.dart';

/// Everything a per-type slide editor might need, bundled so the registry can
/// dispatch by [SlideType] without threading every argument through a switch.
/// Each editor pulls the fields it uses; the rest are ignored.
class SlideEditorContext {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final List<String> searchPaths;
  final String? captionBasePath;
  final ValueChanged<List<Slide>> onAddChartVariants;
  final bool nestedInScrollView;
  final void Function(int atMs)? onSplitVideo;

  /// The active theme's shared activation duration (ms), shown by animated-slide
  /// editors as the inherited value when the slide sets no own duration.
  final int themeAnimationDurationMs;

  /// Whether the slide before this one renders a numbered list — gates the
  /// "continue numbering from the previous slide" option in the bullets editor.
  final bool previousSlideIsNumbered;

  /// Whether the slide before this one can form a split run with it (same type,
  /// same list style) — gates the "continuation of the previous slide" switch,
  /// which controls the shared font size of a split run.
  final bool canContinueSplit;

  /// The severity band of every finding in the deck, for the `findingsSummary`
  /// editor's "refresh from deck". Computed by the panel (which has the deck);
  /// empty for the other editors, which ignore it.
  final List<Cvss4Severity> deckFindingSeverities;

  /// How many deck findings are resolved after retest, for the same
  /// "refresh from deck" (see [deckRetestResolvedCount]); 0 for other editors.
  final int deckResolvedCount;

  const SlideEditorContext({
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    required this.searchPaths,
    required this.captionBasePath,
    required this.onAddChartVariants,
    required this.themeAnimationDurationMs,
    this.previousSlideIsNumbered = false,
    this.canContinueSplit = false,
    this.nestedInScrollView = false,
    this.onSplitVideo,
    this.deckFindingSeverities = const [],
    this.deckResolvedCount = 0,
  });

  Key get _key => ValueKey(slide.id);
}

/// The single place each slide type's editor widget is wired. Replaces the big
/// `switch (slide.type)` dispatch; a guard test (`slide_type_meta_test.dart`)
/// asserts every [SlideType] has an entry, so a new type fails fast instead of
/// hitting the null-assertion at runtime.
final Map<SlideType, Widget Function(SlideEditorContext)> slideEditorBuilders =
    {
      SlideType.title: (c) => TitleEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        searchPaths: c.searchPaths,
        captionBasePath: c.captionBasePath,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.section: (c) => SectionEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.bullets: (c) => BulletsEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        previousSlideIsNumbered: c.previousSlideIsNumbered,
        canContinueSplit: c.canContinueSplit,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.twoBullets: (c) => TwoBulletsEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        canContinueSplit: c.canContinueSplit,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.bulletsImage: (c) => BulletsImageEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        imageService: c.imageService,
        searchPaths: c.searchPaths,
        captionBasePath: c.captionBasePath,
        previousSlideIsNumbered: c.previousSlideIsNumbered,
        canContinueSplit: c.canContinueSplit,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.twoImages: (c) => TwoImagesEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        searchPaths: c.searchPaths,
        captionBasePath: c.captionBasePath,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.image: (c) => ImageSlideEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        imageService: c.imageService,
        searchPaths: c.searchPaths,
        captionBasePath: c.captionBasePath,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.video: (c) => VideoSlideEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        imageService: c.imageService,
        projectPath: c.captionBasePath,
        nestedInScrollView: c.nestedInScrollView,
        onSplit: c.onSplitVideo,
      ),
      SlideType.quote: (c) => QuoteEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        searchPaths: c.searchPaths,
        captionBasePath: c.captionBasePath,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.table: (c) => TableEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.freeMarkdown: (c) => FreeMarkdownEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.code: (c) => CodeEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.chart: (c) => ChartEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        onAddVariants: c.onAddChartVariants,
        projectPath: c.captionBasePath,
        themeAnimationDurationMs: c.themeAnimationDurationMs,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.cockpit: (c) => CockpitEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        themeAnimationDurationMs: c.themeAnimationDurationMs,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.question: (c) => QuestionEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        imageService: c.imageService,
        searchPaths: c.searchPaths,
        captionBasePath: c.captionBasePath,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.timeline: (c) => TimelineEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        themeAnimationDurationMs: c.themeAnimationDurationMs,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.scorecard: (c) => ScorecardEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.actions: (c) => ActionsEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.assets: (c) => AssetOverviewEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      // Informatieveiligheid: all five types now have structured editors
      // (`finding` P1-FIND, `checklist` P1-CHK, `scopeMatrix` P1-SCOPE,
      // `findingsSummary` P1-SUM, `signOff` P1-SIGN).
      SlideType.finding: (c) => FindingEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        imageService: c.imageService,
        projectPath: c.captionBasePath,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.checklist: (c) => ChecklistEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.findingsSummary: (c) => FindingsSummaryEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        deckFindingSeverities: c.deckFindingSeverities,
        deckResolvedCount: c.deckResolvedCount,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.scopeMatrix: (c) => ScopeMatrixEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.signOff: (c) => SignOffEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
        nestedInScrollView: c.nestedInScrollView,
      ),
    };
