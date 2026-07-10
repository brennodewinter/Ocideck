import 'package:flutter/material.dart';

import '../../models/slide.dart';
import '../../services/image_service.dart';
import 'bullets_editor.dart';
import 'bullets_image_editor.dart';
import 'chart_editor.dart';
import 'code_editor.dart';
import 'cockpit_editor.dart';
import 'free_markdown_editor.dart';
import 'image_slide_editor.dart';
import 'question_editor.dart';
import 'quote_editor.dart';
import 'scaffold_slide_editor.dart';
import 'section_editor.dart';
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

  const SlideEditorContext({
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    required this.searchPaths,
    required this.captionBasePath,
    required this.onAddChartVariants,
    required this.themeAnimationDurationMs,
    this.previousSlideIsNumbered = false,
    this.nestedInScrollView = false,
    this.onSplitVideo,
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
        nestedInScrollView: c.nestedInScrollView,
      ),
      SlideType.twoBullets: (c) => TwoBulletsEditor(
        key: c._key,
        slide: c.slide,
        onUpdate: c.onUpdate,
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
      // Informatieveiligheid-scaffold (P1-S): one shared free-Markdown editor
      // for all five types until each gains a structured editor.
      SlideType.finding: _scaffoldEditor,
      SlideType.findingsSummary: _scaffoldEditor,
      SlideType.checklist: _scaffoldEditor,
      SlideType.scopeMatrix: _scaffoldEditor,
      SlideType.signOff: _scaffoldEditor,
    };

Widget _scaffoldEditor(SlideEditorContext c) => ScaffoldSlideEditor(
  key: c._key,
  slide: c.slide,
  onUpdate: c.onUpdate,
  nestedInScrollView: c.nestedInScrollView,
);
